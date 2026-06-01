#!/usr/bin/env node
import { loadConfig } from "./config.js";
import { ConnectorRuntime } from "./runtime.js";
import { SessionStateStore } from "./state.js";

type Command = "run";

interface CliArgs {
  command: Command;
  configPath: string;
  help: boolean;
}

const COMMANDS = new Set<Command>(["run"]);
const RUST_DAEMON_COMMANDS = new Set(["start", "stop", "restart", "status", "logs"]);

function printUsage(): void {
  console.error(`Usage:
  agentnexus-acp-connector --config <path>
  agentnexus-acp-connector run --config <path>

Options:
  -c, --config <path>   Connector JSON config path
  -h, --help            Show this help

Daemon lifecycle commands moved to the Rust daemon in packages/agentnexus-acp-connector-rs.
`);
}

function parseArgs(argv: string[]): CliArgs {
  let command: Command = "run";
  let index = 0;
  if (argv[0] && !argv[0].startsWith("-")) {
    const raw = argv[0] as Command;
    if (!COMMANDS.has(raw)) {
      if (RUST_DAEMON_COMMANDS.has(argv[0])) {
        throw new Error(
          `daemon command "${argv[0]}" moved to the Rust daemon; run it through packages/agentnexus-acp-connector-rs`,
        );
      }
      throw new Error(`unknown command: ${argv[0]}`);
    }
    command = raw;
    index = 1;
  }

  const out: CliArgs = {
    command,
    configPath: "",
    help: false,
  };

  for (let i = index; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === "--config" || arg === "-c") {
      out.configPath = argv[++i] ?? "";
    } else if (arg === "--help" || arg === "-h") {
      out.help = true;
    } else {
      throw new Error(`unknown option: ${arg}`);
    }
  }
  return out;
}

async function runForeground(configPath: string): Promise<void> {
  if (!configPath) throw new Error("--config is required");
  const config = await loadConfig(configPath);
  const runtime = new ConnectorRuntime(
    config.accounts,
    new SessionStateStore(config.statePath!),
    console,
  );
  let stopping = false;
  const stop = async () => {
    if (stopping) return;
    stopping = true;
    await runtime.stop();
    process.exit(0);
  };
  process.on("SIGINT", () => void stop());
  process.on("SIGTERM", () => void stop());
  await runtime.start();
  console.info("agentnexus-acp-connector started accounts=%d", Object.keys(config.accounts).length);
}

async function main(): Promise<void> {
  const args = parseArgs(process.argv.slice(2));
  if (args.help) {
    printUsage();
    return;
  }
  if (args.command === "run") {
    await runForeground(args.configPath);
    return;
  }
}

main().catch((err) => {
  console.error(err instanceof Error ? err.message : err);
  process.exit(1);
});
