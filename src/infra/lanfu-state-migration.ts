// Owns the one-time default-state migration from legacy OpenClaw directories to LanFu.
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { resolveRequiredHomeDir } from "./home-dir.js";

const LANFU_STATE_DIRNAME = ".lanfu";
const LEGACY_STATE_DIRNAMES = [".openclaw", ".clawdbot"] as const;
const MIGRATION_LOCK_SUFFIX = ".migration.lock";
const MIGRATION_BACKUP_MARKER = ".lanfu-migration-backup";

export type LanFuStateMigrationResult =
  | { status: "skipped-explicit-target" | "already-current" | "not-needed"; stateDir: string }
  | { status: "migrated"; stateDir: string; legacyDir: string; backupDir: string }
  | { status: "both-exist"; stateDir: string; legacyDir: string; warning: string };

export class LanFuStateMigrationError extends Error {
  constructor(message: string, options?: { cause?: unknown; backupDir?: string }) {
    super(message, options);
    this.name = "LanFuStateMigrationError";
    this.backupDir = options?.backupDir;
  }

  readonly backupDir?: string;
}

function hasExplicitTarget(env: NodeJS.ProcessEnv): boolean {
  return Boolean(env.OPENCLAW_STATE_DIR?.trim() || env.OPENCLAW_CONFIG_PATH?.trim());
}

function sameEntryKind(left: fs.Stats, right: fs.Stats): boolean {
  if (left.isDirectory() || right.isDirectory()) return left.isDirectory() && right.isDirectory();
  if (left.isFile() || right.isFile()) return left.isFile() && right.isFile();
  return left.isSymbolicLink() && right.isSymbolicLink();
}

function collectEntries(root: string): Map<string, fs.Stats> {
  const entries = new Map<string, fs.Stats>();
  const visit = (current: string, relative: string) => {
    for (const entry of fs.readdirSync(current, { withFileTypes: true })) {
      const childRelative = relative ? path.join(relative, entry.name) : entry.name;
      const child = path.join(current, entry.name);
      const stats = fs.lstatSync(child);
      entries.set(childRelative, stats);
      if (entry.isDirectory() && !entry.isSymbolicLink()) visit(child, childRelative);
    }
  };
  visit(root, "");
  return entries;
}

function validateCopiedTree(source: string, destination: string): void {
  const sourceEntries = collectEntries(source);
  const destinationEntries = collectEntries(destination);
  if (sourceEntries.size !== destinationEntries.size) {
    throw new Error(
      "migration validation entry count mismatch: " +
        sourceEntries.size +
        " != " +
        destinationEntries.size,
    );
  }
  for (const [relative, sourceStats] of sourceEntries) {
    const destinationStats = destinationEntries.get(relative);
    if (!destinationStats || !sameEntryKind(sourceStats, destinationStats)) {
      throw new Error("migration validation mismatch at " + relative);
    }
    if (sourceStats.isFile() && sourceStats.size !== destinationStats.size) {
      throw new Error("migration validation size mismatch at " + relative);
    }
  }
}

function resolveTimestamp(now: () => Date): string {
  return now().toISOString().replaceAll(":", "").replaceAll(".", "-");
}

function writeLock(lockPath: string, payload: Record<string, unknown>): number {
  const fd = fs.openSync(lockPath, "wx");
  fs.writeFileSync(fd, JSON.stringify(payload, null, 2) + "\n", "utf8");
  return fd;
}

export function resolveLanFuStateDir(
  env: NodeJS.ProcessEnv = process.env,
  homedir: () => string = os.homedir,
): string {
  return path.join(resolveRequiredHomeDir(env, homedir), LANFU_STATE_DIRNAME);
}

export function resolveLanFuLegacyStateDirs(
  env: NodeJS.ProcessEnv = process.env,
  homedir: () => string = os.homedir,
): string[] {
  const home = resolveRequiredHomeDir(env, homedir);
  return LEGACY_STATE_DIRNAMES.map((name) => path.join(home, name));
}

/** Ensure default state is in ~/.lanfu before any config/state readers are imported. */
export function ensureLanFuStateMigration(
  params: {
    env?: NodeJS.ProcessEnv;
    homedir?: () => string;
    now?: () => Date;
    pid?: number;
  } = {},
): LanFuStateMigrationResult {
  const env = params.env ?? process.env;
  const homedir = params.homedir ?? os.homedir;
  const stateDir = resolveLanFuStateDir(env, homedir);
  if (hasExplicitTarget(env)) return { status: "skipped-explicit-target", stateDir };
  if (fs.existsSync(stateDir)) {
    const legacyDir = resolveLanFuLegacyStateDirs(env, homedir).find((candidate) =>
      fs.existsSync(candidate),
    );
    if (legacyDir) {
      return {
        status: "both-exist",
        stateDir,
        legacyDir,
        warning:
          "Both " +
          stateDir +
          " and legacy state " +
          legacyDir +
          " exist. LanFu uses " +
          stateDir +
          " and does not merge or delete the legacy directory.",
      };
    }
    return { status: "already-current", stateDir };
  }

  const legacyDir = resolveLanFuLegacyStateDirs(env, homedir).find((candidate) =>
    fs.existsSync(candidate),
  );
  if (!legacyDir) return { status: "not-needed", stateDir };

  const lockPath = stateDir + MIGRATION_LOCK_SUFFIX;
  if (fs.existsSync(lockPath)) {
    throw new LanFuStateMigrationError(
      "LanFu state migration is already in progress or was interrupted. Inspect " +
        lockPath +
        ", preserve " +
        legacyDir +
        ", and retry after resolving the lock.",
    );
  }

  const now = params.now ?? (() => new Date());
  const backupDir = path.join(
    path.dirname(legacyDir),
    path.basename(legacyDir) + "." + MIGRATION_BACKUP_MARKER + "-" + resolveTimestamp(now),
  );
  fs.mkdirSync(path.dirname(stateDir), { recursive: true });
  let lockFd: number | undefined;
  let lockAcquired = false;
  try {
    lockFd = writeLock(lockPath, {
      product: "LanFu",
      operation: "state-migration",
      legacyDir,
      stateDir,
      backupDir,
      pid: params.pid ?? process.pid,
      startedAt: now().toISOString(),
    });
    lockAcquired = true;
    fs.cpSync(legacyDir, backupDir, { recursive: true, dereference: false, errorOnExist: true });
    fs.cpSync(legacyDir, stateDir, { recursive: true, dereference: false, errorOnExist: true });
    validateCopiedTree(legacyDir, stateDir);
    return { status: "migrated", stateDir, legacyDir, backupDir };
  } catch (cause) {
    fs.rmSync(stateDir, { recursive: true, force: true });
    throw new LanFuStateMigrationError(
      "LanFu could not migrate legacy state from " +
        legacyDir +
        " to " +
        stateDir +
        ". The legacy directory was preserved; backup: " +
        backupDir +
        ".",
      { cause, backupDir },
    );
  } finally {
    if (lockFd !== undefined) fs.closeSync(lockFd);
    if (lockAcquired) fs.rmSync(lockPath, { force: true });
  }
}
