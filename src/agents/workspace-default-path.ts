/**
 * Default agent workspace resolver.
 *
 * Derives the process workspace directory from env, profile, and home-directory state.
 */
import os from "node:os";
import path from "node:path";
import { normalizeOptionalLowercaseString } from "@openclaw/normalization-core/string-coerce";
import { resolveProfileStateDir } from "../cli/profile-utils.js";
import { resolveStateDir } from "../config/state-dir.js";

/** Resolve the default agent workspace directory from env/profile/home state. */
export function resolveDefaultAgentWorkspaceDir(
  env: NodeJS.ProcessEnv = process.env,
  homedir: () => string = os.homedir,
): string {
  const workspaceDir = env.OPENCLAW_WORKSPACE_DIR?.trim();
  if (workspaceDir) {
    return path.resolve(workspaceDir);
  }
  const profile = env.OPENCLAW_PROFILE?.trim();
  if (profile && normalizeOptionalLowercaseString(profile) !== "default") {
    return path.join(resolveProfileStateDir(profile, env, homedir), "workspace");
  }
  // The workspace must live inside the resolved state directory. An earlier
  // fallback hardcoded ~/.openclaw/workspace while the state dir itself defaults
  // to ~/.lanfu, which silently spawned a legacy directory next to the real
  // state on every machine and left workspace data outside the state tree.
  return path.join(resolveStateDir(env, homedir), "workspace");
}
