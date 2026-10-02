// Legacy clawbot command namespace kept for QR/linking aliases.
import type { Command } from "commander";
import { registerQrCli } from "./qr-cli.js";

export function registerClawbotCli(program: Command) {
  const clawbot = program
    .command("clawbot")
    .description("Legacy clawbot command aliases")
    .addHelpText("after", () => `\n\n`);
  registerQrCli(clawbot);
}
