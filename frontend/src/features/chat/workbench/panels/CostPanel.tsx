// ② Cost dashboard panel — renders per-bot token/cost totals + context window
// (channel.usage.read). Registered into the workbench like FilePanel.
//
// All numbers below come from the agent's own usage_update telemetry and are
// rendered as INERT TEXT (formatted numbers / JSX children) — never as HTML.
//
// FOLLOW-UP (out of scope here): the chain-budget pause-gate (block a turn when a
// channel's cumulative cost crosses a cap) lives in shared dispatch, not this read
// panel; wire it where turns are admitted, not in the dashboard.
import { useCallback } from "react";
import { Coins, Gauge, RefreshCw } from "lucide-react";
import { registerPanel, type PanelContext } from "../panelRegistry";
import { useResourceQuery } from "../useResourceQuery";

interface BotUsage {
  bot_id: string;
  input_tokens: number | null;
  output_tokens: number | null;
  total_tokens: number | null;
  context_window: number | null;
  cost_usd: number | null;
}
interface UsageRead {
  channel_id: string;
  bots: BotUsage[];
}

// Inert formatters: thousands-separated integers and a USD amount. A missing
// value renders as an em dash rather than "0", so "no data" reads differently
// from "measured zero".
function fmtInt(n: number | null | undefined): string {
  if (n === null || n === undefined || Number.isNaN(n)) return "—";
  return Math.round(n).toLocaleString("en-US");
}
function fmtUsd(n: number | null | undefined): string {
  if (n === null || n === undefined || Number.isNaN(n)) return "—";
  return n.toLocaleString("en-US", {
    style: "currency",
    currency: "USD",
    minimumFractionDigits: 2,
    maximumFractionDigits: 4,
  });
}

function CostPanel({ ctx }: { ctx: PanelContext }) {
  const { data, loading, error, refetch } = useResourceQuery<UsageRead>(
    ctx.sendResourceReq,
    "channel.usage.read",
    { channel_id: ctx.channelId },
    !!ctx.channelId
  );

  // Live telemetry trickles in as turns run; let the user pull a fresh aggregate.
  // (useResourceQuery already re-runs automatically when ctx.channelId changes.)
  const onRefresh = useCallback(() => refetch(), [refetch]);

  const bots = data?.bots ?? [];

  return (
    <div className="flex flex-col h-full text-sm">
      <div className="flex items-center gap-2 px-3 h-8 border-b border-zinc-800 flex-shrink-0">
        <Coins className="w-3.5 h-3.5 text-zinc-500" />
        <span className="text-xs text-zinc-300">Cost &amp; usage</span>
        <div className="flex-1" />
        {loading && <span className="text-[10px] text-zinc-600">Loading…</span>}
        <button onClick={onRefresh} title="Refresh">
          <RefreshCw className="w-3.5 h-3.5 text-zinc-500 hover:text-zinc-300" />
        </button>
      </div>

      <div className="flex-1 overflow-auto">
        {error && (
          <div className="px-3 py-3 text-xs text-red-400">{error}</div>
        )}

        {!error && bots.length === 0 && (
          <div className="px-3 py-6 text-xs text-zinc-600 flex items-center gap-2">
            <Gauge className="w-4 h-4" />
            {loading ? "Loading usage…" : "No usage reported yet"}
          </div>
        )}

        {!error && bots.length > 0 && (
          <table className="w-full text-xs">
            <thead>
              <tr className="text-zinc-500 border-b border-zinc-800">
                <th className="text-left font-normal px-3 py-1.5">Bot</th>
                <th className="text-right font-normal px-2 py-1.5">Input</th>
                <th className="text-right font-normal px-2 py-1.5">Output</th>
                <th className="text-right font-normal px-2 py-1.5">Total</th>
                <th className="text-right font-normal px-2 py-1.5">Context</th>
                <th className="text-right font-normal px-3 py-1.5">Cost</th>
              </tr>
            </thead>
            <tbody>
              {bots.map((b) => (
                <tr
                  key={b.bot_id}
                  className="border-b border-zinc-900 hover:bg-zinc-800/40 text-zinc-300"
                >
                  {/* bot_id is an opaque id, rendered as inert text */}
                  <td className="px-3 py-1.5 font-mono text-zinc-200 truncate max-w-[140px]">
                    {b.bot_id}
                  </td>
                  <td className="px-2 py-1.5 text-right tabular-nums text-zinc-400">
                    {fmtInt(b.input_tokens)}
                  </td>
                  <td className="px-2 py-1.5 text-right tabular-nums text-zinc-400">
                    {fmtInt(b.output_tokens)}
                  </td>
                  <td className="px-2 py-1.5 text-right tabular-nums text-zinc-200">
                    {fmtInt(b.total_tokens)}
                  </td>
                  {/* context window = latest snapshot; an at-a-glance pressure gauge */}
                  <td className="px-2 py-1.5 text-right tabular-nums">
                    <span className="inline-flex items-center gap-1 text-zinc-400">
                      <Gauge className="w-3 h-3 text-zinc-600" />
                      {fmtInt(b.context_window)}
                    </span>
                  </td>
                  <td className="px-3 py-1.5 text-right tabular-nums text-emerald-400">
                    {fmtUsd(b.cost_usd)}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>
    </div>
  );
}

registerPanel({
  id: "cost",
  title: "Cost",
  render: (ctx) => <CostPanel ctx={ctx} />,
});

export default CostPanel;
