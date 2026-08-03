import { useCallback, useMemo, useRef, useState } from "react";
import {
  ChevronRight,
  ChevronDown,
  Wrench,
  ListTodo,
  ShieldCheck,
  Check,
  X,
  XCircle,
  Clock,
  Zap,
  Loader2,
  type LucideIcon,
} from "lucide-react";
import { cn } from "@/lib/cn";
import { fetchMessageTrace } from "@/api/approval";
import { PopoverPanel, usePopoverDismiss } from "@/components/ui/popover";
import type { TraceEvent } from "@/types";
import { DiffView } from "./DiffView";
import { coalesceTraceEvents } from "./traceEvent";

interface Props {
  channelId: string;
  msgId: string;
  liveEvents?: TraceEvent[];
}

/** Icon + tone + short label for a persisted trace row. Approval rows get the
 *  shield/check/x family; agent-progress rows map by phase. */
// Keep the timeline quiet and monochrome (Codex/Claude style): icons carry the
// category, but the palette stays muted zinc so steps read as ambient progress
// rather than a loud status board. Color is reserved for genuine failures (and a
// soft amber for a still-pending approval).
function eventMeta(e: TraceEvent): { Icon: LucideIcon; tone: string; label: string } {
  if (e.kind === "approval") {
    const ak = e.approval_kind ?? "";
    if (ak === "resolved") {
      const ok = (e.decision ?? "").startsWith("allow");
      return ok
        ? { Icon: Check, tone: "text-zinc-500", label: "Approved" }
        : { Icon: X, tone: "text-red-400/70", label: "Denied" };
    }
    if (ak === "expired" || ak === "rejected") {
      return { Icon: X, tone: "text-zinc-600", label: ak === "expired" ? "Expired" : "Rejected" };
    }
    if (ak === "auto_allowed") {
      return { Icon: Check, tone: "text-zinc-500", label: "Auto-allowed" };
    }
    return { Icon: ShieldCheck, tone: "text-amber-400/70", label: "Approval" };
  }
  switch (e.phase) {
    case "tool_call":
    case "tool_call_update":
      return { Icon: Wrench, tone: "text-zinc-500", label: "Tool" };
    case "plan":
      return { Icon: ListTodo, tone: "text-zinc-500", label: "Plan" };
    case "prompt_finished":
      return { Icon: Check, tone: "text-zinc-500", label: "Done" };
    case "prompt_started":
      return { Icon: Zap, tone: "text-zinc-500", label: "Start" };
    case "prompt_failed":
    case "terminal_ack_failed":
      return { Icon: XCircle, tone: "text-red-400/70", label: "Failed" };
    default:
      return { Icon: Clock, tone: "text-zinc-600", label: e.phase || "Event" };
  }
}

// Map the ACP tool-call status vocabulary (pending/in_progress/completed/failed)
// to human labels — mirrors PlanBoardPanel's group labels — with a humanize
// fallback so an unknown token never renders as raw snake_case.
const STATUS_LABELS: Record<string, string> = {
  pending: "Pending",
  in_progress: "In progress",
  completed: "Completed",
  failed: "Failed",
};

function statusLabel(status: string): string {
  return (
    STATUS_LABELS[status] ??
    status.replace(/_/g, " ").replace(/^\w/, (c) => c.toUpperCase())
  );
}

type JsonRecord = Record<string, unknown>;

function asRecord(value: unknown): JsonRecord | null {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    ? (value as JsonRecord)
    : null;
}

function formatJson(value: unknown): string {
  return JSON.stringify(value, null, 2) ?? String(value);
}

function DetailValue({ value }: { value: unknown }) {
  return (
    <pre className="whitespace-pre-wrap break-words font-mono">
      {typeof value === "string" ? value : formatJson(value)}
    </pre>
  );
}

function stringField(record: JsonRecord | null, ...keys: string[]): string | null {
  for (const key of keys) {
    const value = record?.[key];
    if (typeof value === "string" && value.trim()) return value;
  }
  return null;
}

interface FileDiff {
  path: string;
  oldText: string;
  newText: string;
}

function fileDiffs(data: JsonRecord | null): FileDiff[] {
  const blocks = Array.isArray(data?.content) ? data.content : [];
  return blocks.flatMap((block, index) => {
    const diff = asRecord(block);
    if (diff?.type !== "diff") return [];
    return [{
      path: stringField(diff, "path") ?? `File ${index + 1}`,
      oldText: stringField(diff, "oldText", "old_text") ?? "",
      newText: stringField(diff, "newText", "new_text") ?? "",
    }];
  });
}

/** A bounded unified representation for DiffView. ACP sends full before/after
 * files, so intentionally cap this inspector preview rather than expanding the
 * message indefinitely. */
function fileDiffPreview({ path, oldText, newText }: FileDiff): string {
  const limit = 12_000;
  const clip = (text: string) =>
    text.length > limit ? `${text.slice(0, limit)}\n… preview truncated` : text;
  const oldLines = clip(oldText).split("\n").map((line) => `-${line}`);
  const newLines = clip(newText).split("\n").map((line) => `+${line}`);
  return [
    `diff --git a/${path} b/${path}`,
    `--- a/${path}`,
    `+++ b/${path}`,
    `@@ -1,${oldLines.length} +1,${newLines.length} @@`,
    ...oldLines,
    ...newLines,
  ].join("\n");
}

function FileEditInspector({ diffs }: { diffs: FileDiff[] }) {
  const [selectedPath, setSelectedPath] = useState(diffs[0]?.path ?? "");
  const selected = diffs.find((diff) => diff.path === selectedPath) ?? diffs[0];
  if (!selected) return null;
  return (
    <div className="grid min-h-64 grid-cols-[minmax(9rem,11rem)_minmax(0,1fr)] gap-3">
      <div className="min-w-0 space-y-1 py-1">
        {diffs.map((diff) => (
          <button
            key={diff.path}
            type="button"
            onClick={() => setSelectedPath(diff.path)}
            className={cn(
              "w-full truncate rounded-lg px-2 py-1.5 text-left font-mono text-[11px] text-zinc-400 transition-colors hover:bg-zinc-800 hover:text-zinc-200",
              diff.path === selected.path && "bg-indigo-600/15 text-indigo-200",
            )}
            title={diff.path}
          >
            {diff.path}
          </button>
        ))}
      </div>
      <DiffView diff={fileDiffPreview(selected)} className="max-h-80 rounded-lg bg-zinc-950" />
    </div>
  );
}

function eventPreview(event: TraceEvent): string | null {
  const data = asRecord(event.data);
  const input = asRecord(data?.input);
  const command = stringField(input, "command") ?? stringField(data, "command");
  const filePath = stringField(input, "path", "filePath", "file_path");
  const diffs = fileDiffs(data);
  if (diffs.length) return `${diffs.length} file${diffs.length === 1 ? "" : "s"} changed`;
  if (command) return command;
  if (filePath) return filePath;
  if (event.kind === "approval" && event.decision) return event.decision;
  if (event.message && event.message !== event.title) return event.message;
  if (event.status) return statusLabel(event.status);
  return null;
}

/** The inspector deliberately omits the single-line row's preview. It exposes
 * only the additional context needed to inspect the operation. */
function TraceEventInspector({ event }: { event: TraceEvent }) {
  const data = asRecord(event.data);
  const input = asRecord(data?.input);
  const cwd = stringField(input, "cwd", "working_directory");
  const filePath = stringField(input, "path", "filePath", "file_path");
  const diffs = fileDiffs(data);
  const planEntries = Array.isArray(data?.entries) ? data.entries : null;
  const output = data?.output;
  const metadata = {
    phase: event.phase,
    kind: event.kind,
    event_id: event.event_id ?? event.id,
    ...(event.tool_call_id ? { tool_call_id: event.tool_call_id } : {}),
    ...(event.request_id ? { request_id: event.request_id } : {}),
    created_at: event.created_at,
  };

  return (
    <div className="space-y-3 p-3 text-[11px] text-zinc-400">
      {diffs.length > 0 && <FileEditInspector diffs={diffs} />}
      {planEntries && (
        <div className="space-y-1.5">
          <div className="text-[10px] font-medium uppercase tracking-wide text-zinc-400">Plan</div>
          {planEntries.length > 0 ? (
            <ol className="space-y-1 pl-4 list-decimal">
              {planEntries.map((entry, index) => {
                const item = asRecord(entry);
                const content =
                  typeof item?.content === "string"
                    ? item.content
                    : formatJson(entry);
                const status = typeof item?.status === "string" ? item.status : null;
                return (
                  <li key={`${index}-${content}`} className="break-words">
                    <span className="text-zinc-300">{content}</span>
                    {status && (
                      <span className="ml-1.5 text-zinc-500">
                        {statusLabel(status)}
                      </span>
                    )}
                  </li>
                );
              })}
            </ol>
          ) : (
            <div>No plan entries reported.</div>
          )}
        </div>
      )}

      {cwd && (
        <div>
          <div className="text-[10px] font-medium uppercase tracking-wide text-zinc-400">Working directory</div>
          <div className="mt-1 font-mono text-zinc-200">{cwd}</div>
        </div>
      )}
      {!diffs.length && filePath && (
        <div>
          <div className="text-[10px] font-medium uppercase tracking-wide text-zinc-400">File</div>
          <div className="mt-1 font-mono text-zinc-200">{filePath}</div>
        </div>
      )}
      {output != null && (
        <div>
          <div className="mb-1 text-[10px] font-medium uppercase tracking-wide text-zinc-400">Output</div>
          <div className="max-h-56 overflow-auto rounded-lg bg-zinc-950 px-2.5 py-2 text-zinc-300"><DetailValue value={output} /></div>
        </div>
      )}
      <details>
        <summary className="cursor-pointer select-none text-zinc-400 hover:text-zinc-200">Raw event data</summary>
        <div className="mt-2 max-h-64 overflow-auto">
          <DetailValue value={{ ...metadata, ...(data ? { data } : {}) }} />
        </div>
      </details>
    </div>
  );
}

function TraceItem({
  event,
  active,
  onToggle,
}: {
  event: TraceEvent;
  active: boolean;
  onToggle: () => void;
}) {
  const rootRef = useRef<HTMLDivElement>(null);
  const { Icon, tone, label } = eventMeta(event);
  const preview = eventPreview(event);
  const close = useCallback(() => {
    if (active) onToggle();
  }, [active, onToggle]);
  usePopoverDismiss(active, close, rootRef);

  return (
    <div ref={rootRef} className="relative min-w-0">
      <button
        type="button"
        onClick={onToggle}
        aria-expanded={active}
        aria-label={`${active ? "Hide" : "Show"} details for ${event.title || label}`}
        className={cn(
          "flex h-7 w-full items-center gap-2 rounded-lg px-2 text-left transition-colors hover:bg-zinc-900/70",
          active && "bg-indigo-600/15",
        )}
      >
        <Icon className={cn("h-3.5 w-3.5 shrink-0", tone)} />
        <span className="min-w-0 max-w-[45%] shrink truncate text-[11px] font-medium text-zinc-200">
          {event.title || label}
        </span>
        {preview && (
          <span className="min-w-0 flex-1 truncate font-mono text-[10px] text-zinc-400" title={preview}>
            {preview}
          </span>
        )}
        {event.status && (
          <span className="shrink-0 text-[10px] text-zinc-400">
            {statusLabel(event.status)}
          </span>
        )}
        <ChevronRight
          className={cn(
            "h-3 w-3 shrink-0 text-zinc-500 transition-transform",
            active && "rotate-90 text-indigo-400",
          )}
        />
      </button>
      {active && (
        <PopoverPanel placement="down" className="w-[min(42rem,calc(100vw-2rem))] max-h-[min(32rem,calc(100vh-2rem))] overflow-auto">
          <TraceEventInspector event={event} />
        </PopoverPanel>
      )}
    </div>
  );
}

/**
 * Collapsible "agent steps" panel for a completed bot turn. Lazily fetches the
 * durable trace timeline (docs/arch/TRACE_PERSISTENCE.md) on first expand and
 * renders each persisted step — including approval events interleaved inline.
 * Self-hides when a turn has no recorded steps.
 */
export function BotTracePanel({ channelId, msgId, liveEvents = [] }: Props) {
  const [expanded, setExpanded] = useState(false);
  const [activeEventId, setActiveEventId] = useState<string | null>(null);
  const [events, setEvents] = useState<TraceEvent[] | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const displayedEvents = useMemo(
    () => coalesceTraceEvents(events ?? [], liveEvents),
    [events, liveEvents],
  );

  async function load() {
    if (loading) return;
    setLoading(true);
    setError(null);
    try {
      const res = await fetchMessageTrace(channelId, msgId);
      setEvents(res.events ?? []);
    } catch (e) {
      // Leave events === null so the next expand retries.
      setError(e instanceof Error ? e.message : "Failed to load trace");
    } finally {
      setLoading(false);
    }
  }

  function toggle() {
    const next = !expanded;
    setExpanded(next);
    if (next && events === null && !loading) void load();
  }

  // Once we've loaded and found nothing, drop the toggle entirely (no noise).
  if (events !== null && displayedEvents.length === 0 && !expanded) return null;

  // Approvals resolved during this turn — surfaced as a shield badge so the reveal
  // doubles as "review this turn's approvals" (their inline cards are hidden once resolved).
  const approvalCount = displayedEvents.filter((e) => e.kind === "approval").length;

  return (
    <div className="mt-1 max-w-md">
      <button
        type="button"
        onClick={toggle}
        aria-expanded={expanded}
        title={expanded ? "Hide agent steps" : "Show agent steps"}
        className="flex items-center gap-1.5 text-[11px] text-zinc-400 hover:text-zinc-200 transition-colors"
      >
        {expanded ? (
          <ChevronDown className="w-3 h-3" />
        ) : (
          <ChevronRight className="w-3 h-3" />
        )}
        <span>
          Agent steps
          {events !== null || displayedEvents.length > 0
            ? ` · ${displayedEvents.length}`
            : ""}
        </span>
        {approvalCount > 0 && (
          <span className="inline-flex items-center gap-0.5 text-zinc-400">
            <ShieldCheck className="w-3 h-3" />
            {approvalCount}
          </span>
        )}
        {loading && <Loader2 className="w-3 h-3 animate-spin" />}
      </button>

      {expanded && displayedEvents.length > 0 && (
        <div className="mt-2 flex flex-col gap-1">
          {displayedEvents.map((event) => (
            <TraceItem
              key={event.id}
              event={event}
              active={activeEventId === event.id}
              onToggle={() =>
                setActiveEventId((current) =>
                  current === event.id ? null : event.id,
                )
              }
            />
          ))}
        </div>
      )}

      {expanded && events && displayedEvents.length === 0 && !loading && !error && (
        <div className="mt-1 px-2.5 text-[11px] text-zinc-400">
          No steps recorded.
        </div>
      )}

      {expanded && error && !loading && (
        <div className="mt-1 px-2.5 flex items-center gap-2 text-[11px] text-red-400">
          <span>Failed to load steps.</span>
          <button
            type="button"
            onClick={() => void load()}
            className="text-zinc-400 hover:text-zinc-200 underline underline-offset-2"
          >
            Retry
          </button>
        </div>
      )}
    </div>
  );
}
