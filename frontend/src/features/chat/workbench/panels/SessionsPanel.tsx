// Sessions inspector — a ViewBoard listing every live session bound to the channel
// (channel.sessions.read), across all bots: primary + "other", with status + mode.
// The channel-wide view behind the composer's SessionSwitcher; the row matching the
// composer's selected session is highlighted.
//
// Not session-scoped (it LISTS sessions). Read-only — create/close/set_mode live in
// the session-control surface, not here. All ids/values render as inert text.
import { Layers, CircleDot } from "lucide-react";
import { registerViewBoard, type ViewBoardContext } from "../viewBoard";

interface SessionRow {
  session_id: string;
  bot_id: string;
  role: string;
  is_primary: boolean;
  status: string;
  last_used_at: string;
  session_config?: { mode?: string } & Record<string, unknown>;
}
interface SessionsRead {
  channel_id: string;
  sessions: SessionRow[];
}

// Status → dot color. Active/busy = working; idle = parked; paused = held;
// error/revoked = trouble. Unknown falls back to a neutral dot.
function statusColor(s: string): string {
  switch (s) {
    case "active":
    case "busy":
      return "text-emerald-500";
    case "idle":
      return "text-zinc-500";
    case "paused":
      return "text-amber-400";
    case "error":
    case "revoked":
    case "expired":
      return "text-red-400";
    default:
      return "text-zinc-600";
  }
}

function fmtTime(iso: string): string {
  if (!iso) return "—";
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return "—";
  return d.toLocaleString(undefined, { month: "short", day: "numeric", hour: "2-digit", minute: "2-digit" });
}

function SessionsBody({ data, ctx }: { data: SessionsRead; ctx: ViewBoardContext }) {
  const sessions = data.sessions ?? [];
  if (sessions.length === 0) {
    return (
      <div className="px-3 py-6 text-xs text-zinc-600 flex items-center gap-2">
        <Layers className="w-4 h-4" />
        No sessions yet
      </div>
    );
  }
  const selected = ctx.selectedSessionId || "";
  return (
    <table className="w-full text-xs">
      <thead>
        <tr className="text-zinc-500 border-b border-zinc-800">
          <th className="text-left font-normal px-3 py-1.5">Bot</th>
          <th className="text-left font-normal px-2 py-1.5">Session</th>
          <th className="text-left font-normal px-2 py-1.5">Mode</th>
          <th className="text-left font-normal px-3 py-1.5">Status</th>
          <th className="text-right font-normal px-3 py-1.5">Last used</th>
        </tr>
      </thead>
      <tbody>
        {sessions.map((s) => {
          const isSelected = selected && s.session_id === selected;
          const mode = typeof s.session_config?.mode === "string" ? s.session_config.mode : null;
          return (
            <tr
              key={s.session_id}
              className={`border-b border-zinc-900 text-zinc-300 ${
                isSelected ? "bg-emerald-500/10" : "hover:bg-zinc-800/40"
              }`}
            >
              <td className="px-3 py-1.5 font-mono text-zinc-400 truncate max-w-[100px]">
                {s.bot_id.slice(0, 8)}
              </td>
              <td className="px-2 py-1.5">
                <span className="font-mono text-zinc-200">{s.session_id.slice(0, 8)}</span>
                <span
                  className={`ml-1.5 text-[10px] px-1 py-0.5 rounded ${
                    s.is_primary ? "bg-zinc-700 text-zinc-200" : "bg-zinc-800 text-zinc-500"
                  }`}
                >
                  {s.is_primary ? "primary" : "other"}
                </span>
              </td>
              <td className="px-2 py-1.5 text-zinc-400">{mode ?? "—"}</td>
              <td className="px-3 py-1.5">
                <span className="inline-flex items-center gap-1">
                  <CircleDot className={`w-3 h-3 ${statusColor(s.status)}`} />
                  <span className="text-zinc-400">{s.status}</span>
                </span>
              </td>
              <td className="px-3 py-1.5 text-right tabular-nums text-zinc-500">
                {fmtTime(s.last_used_at)}
              </td>
            </tr>
          );
        })}
      </tbody>
    </table>
  );
}

registerViewBoard<SessionsRead>({
  id: "sessions",
  title: "Sessions",
  icon: Layers,
  verb: "channel.sessions.read",
  sessionScoped: false,
  makeParams: (ctx) => ({ channel_id: ctx.channelId }),
  render: (data, ctx) => <SessionsBody data={data} ctx={ctx} />,
});
