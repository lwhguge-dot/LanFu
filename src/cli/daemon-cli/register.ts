// Legacy `daemon` command registration, backed by the same Gateway service commands.
import type { Command } from "commander";
import { addGatewayServiceCommands } from "./register-service-commands.js";

/** Register the legacy daemon command group. */
export function registerDaemonCli(program: Command) {
  const daemon = program
    .command("daemon")
    .description("Manage the Gateway service (launchd/systemd/schtasks)")
    .option("--json", "Output JSON", false)
    .addHelpText("after", () => `\n\n`);

  addGatewayServiceCommands(daemon, {
    statusDescription: "Show service install status + probe connectivity/capability",
  });
}
