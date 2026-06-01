# agentnexus-acp-connector Rust daemon

Rust process supervisor for the AgentNexus ACP connector.

The TypeScript package still owns the foreground ACP runtime. This Rust binary
owns daemon lifecycle commands: `start`, `stop`, `restart`, `status`, and
`logs`. Its `run` command validates the connector JSON config, locates the
built TypeScript foreground runner, and executes it under process-group signal
control.

The Agent Bridge WebSocket protocol helpers formerly published as the
standalone `@haowei0520/bridge-client` package now live in this Rust crate under
`src/bridge.rs`.

```bash
cd packages/agentnexus-acp-connector
npm install
npm run build

cd ../agentnexus-acp-connector-rs
cargo run -- start --config ../agentnexus-acp-connector/agentnexus-acp.json --name opencode-main
cargo run -- status --name opencode-main
cargo run -- logs --name opencode-main --lines 120
cargo run -- stop --name opencode-main
```

Set `AGENTNEXUS_ACP_HOME=/path/to/state` or pass `--home /path/to/state` to
change the daemon metadata and log directory. Set
`AGENTNEXUS_ACP_TS_CLI=/absolute/path/to/dist/cli.js` if the Rust daemon cannot
auto-detect the TypeScript foreground runner.
