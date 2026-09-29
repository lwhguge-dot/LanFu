import { normalizeAgentId } from "@openclaw/normalization-core/agent-id";
import { loadAgentTeamPreset, validateAgentTeamMemberIds } from "../agents/agent-roles.js";
import type { WizardPrompter } from "../wizard/prompts.js";
import { type FirstOnboardingAgent, validateFirstOnboardingAgentName } from "./onboard-agent.js";

export async function promptFirstOnboardingAgent(
  hasAuthoredRoster: boolean,
  requestedName: string | undefined,
  prompter: WizardPrompter,
  nonInteractive = false,
  options?: { team?: boolean; offerTeam?: boolean },
): Promise<FirstOnboardingAgent | undefined> {
  if (hasAuthoredRoster) {
    return undefined;
  }
  const createTeam =
    options?.team ??
    (options?.offerTeam === true &&
      !requestedName &&
      (await prompter.select({
        message: "What would you like to create?",
        initialValue: "one",
        options: [
          { value: "one", label: "One agent" },
          { value: "team", label: "A small team: a chief of staff plus specialists" },
        ],
      })) === "team");
  const teamPreset = createTeam ? await loadAgentTeamPreset() : undefined;
  const specialistIds = teamPreset?.specialists.map(({ id }) => id) ?? [];
  const validateName = (value: string) =>
    validateFirstOnboardingAgentName(value) ??
    (teamPreset
      ? validateAgentTeamMemberIds([normalizeAgentId(value), ...specialistIds])
      : undefined);
  const defaultName = teamPreset?.coordinator.id ?? "main";
  const name =
    requestedName ??
    (nonInteractive
      ? defaultName
      : await prompter.text({
          message: createTeam
            ? "What should we call your chief of staff?"
            : "你的助手叫什么名字？直接回车即默认助手「小蓝」（标识需为英文，如 main）",
          initialValue: defaultName,
          validate: validateName,
        }));
  const error = validateName(name);
  if (error) {
    throw new Error(error);
  }
  // Display-name default applies only when the caller accepted the default id
  // (no explicit request, input equals defaultName); custom names are respected verbatim.
  const displayName = !requestedName && name === defaultName ? "小蓝" : undefined;
  return { name, ...(displayName ? { displayName } : {}), ...(createTeam ? { team: true } : {}) };
}

export async function showSessionMigrationWarnings(
  prompter: WizardPrompter,
  warnings: readonly string[] | undefined,
): Promise<void> {
  if (warnings?.length) {
    await prompter.note(warnings.join("\n"), "Session history migration");
  }
}
