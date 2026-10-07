import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import {
  ensureLanFuStateMigration,
  LanFuStateMigrationError,
  resolveLanFuLegacyStateDirs,
  resolveLanFuStateDir,
} from "./lanfu-state-migration.js";

const roots: string[] = [];

afterEach(() => {
  for (const root of roots.splice(0)) fs.rmSync(root, { recursive: true, force: true });
});

function fixture() {
  const home = fs.mkdtempSync(path.join(os.tmpdir(), "lanfu-state-"));
  roots.push(home);
  const env = { OPENCLAW_HOME: home } as NodeJS.ProcessEnv;
  return {
    home,
    env,
    legacy: resolveLanFuLegacyStateDirs(env, () => home)[0]!,
    state: resolveLanFuStateDir(env, () => home),
  };
}

describe("LanFu default state migration", () => {
  it("backs up and validates an OpenClaw state tree while preserving the source", () => {
    const { env, legacy, state } = fixture();
    fs.mkdirSync(path.join(legacy, "agents", "main"), { recursive: true });
    fs.writeFileSync(path.join(legacy, "openclaw.json"), '{"gateway":{"mode":"local"}}\n');
    fs.writeFileSync(path.join(legacy, "agents", "main", "sessions.json"), "history");

    const result = ensureLanFuStateMigration({
      env,
      homedir: () => env.OPENCLAW_HOME!,
      now: () => new Date("2026-10-02T12:00:00.000Z"),
    });

    expect(result.status).toBe("migrated");
    if (result.status !== "migrated") return;
    expect(result.stateDir).toBe(state);
    expect(fs.existsSync(legacy)).toBe(true);
    expect(fs.readFileSync(path.join(state, "openclaw.json"), "utf8")).toContain("local");
    expect(fs.readFileSync(path.join(state, "agents", "main", "sessions.json"), "utf8")).toBe(
      "history",
    );
    expect(fs.existsSync(result.backupDir)).toBe(true);
    expect(fs.existsSync(state + ".migration.lock")).toBe(false);
    expect(ensureLanFuStateMigration({ env, homedir: () => env.OPENCLAW_HOME! }).status).toBe(
      "both-exist",
    );
  });

  it("does not merge when both state directories already exist", () => {
    const { env, legacy, state } = fixture();
    fs.mkdirSync(legacy, { recursive: true });
    fs.mkdirSync(state, { recursive: true });
    fs.writeFileSync(path.join(legacy, "legacy.txt"), "legacy");
    fs.writeFileSync(path.join(state, "current.txt"), "current");

    const result = ensureLanFuStateMigration({ env, homedir: () => env.OPENCLAW_HOME! });

    expect(result.status).toBe("both-exist");
    expect(fs.existsSync(path.join(state, "legacy.txt"))).toBe(false);
    expect(fs.readFileSync(path.join(state, "current.txt"), "utf8")).toBe("current");
  });

  it("does not touch an explicitly selected state target", () => {
    const { env, legacy, state } = fixture();
    fs.mkdirSync(legacy, { recursive: true });
    env.OPENCLAW_STATE_DIR = path.join(env.OPENCLAW_HOME!, "custom-state");

    const result = ensureLanFuStateMigration({ env, homedir: () => env.OPENCLAW_HOME! });

    expect(result.status).toBe("skipped-explicit-target");
    expect(fs.existsSync(state)).toBe(false);
    expect(fs.existsSync(legacy)).toBe(true);
  });

  it("refuses an interrupted migration lock without deleting source data", () => {
    const { env, legacy, state } = fixture();
    fs.mkdirSync(legacy, { recursive: true });
    fs.writeFileSync(state + ".migration.lock", "{}\n");

    expect(() => ensureLanFuStateMigration({ env, homedir: () => env.OPENCLAW_HOME! })).toThrow(
      LanFuStateMigrationError,
    );
    expect(fs.existsSync(legacy)).toBe(true);
    expect(fs.existsSync(state)).toBe(false);
  });
});
