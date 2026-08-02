import type { TraceEvent } from "@/types";

export const TRACE_EVENT_VERSION = 1;

export const TERMINAL_TRACE_STATUSES = new Set([
  "completed",
  "approved",
  "denied",
  "failed",
  "cancelled",
  "refused",
  "truncated",
  "max_turn_requests",
]);

type JsonObject = Record<string, unknown>;

function asObject(value: unknown): JsonObject | null {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    ? (value as JsonObject)
    : null;
}

function nonEmptyString(value: unknown): string | null {
  return typeof value === "string" && value.trim() ? value : null;
}

function normalizeTraceStatus(value: unknown): string | null {
  const status = nonEmptyString(value);
  if (!status) return null;
  if (status === "running" || status === "started") return "in_progress";
  if (["complete", "done", "success", "succeeded"].includes(status)) {
    return "completed";
  }
  if (status === "error") return "failed";
  return status;
}

function deepMergeOlderWithNewer(older: unknown, newer: unknown): unknown {
  if (newer === null || newer === undefined) return older;
  const oldObject = asObject(older);
  const newObject = asObject(newer);
  if (!oldObject || !newObject) return newer;

  const result: JsonObject = { ...oldObject };
  for (const [key, value] of Object.entries(newObject)) {
    result[key] = deepMergeOlderWithNewer(result[key], value);
  }
  return result;
}

/** Accept both TraceEvent v1 and the pre-v1 live payload during rollout. */
export function normalizeTraceEvent(raw: unknown): TraceEvent | null {
  const event = asObject(raw);
  if (!event) return null;
  const msgId = nonEmptyString(event.msg_id);
  const phase = nonEmptyString(event.phase);
  if (!msgId || !phase) return null;

  const data = asObject(event.data);
  const requestId =
    nonEmptyString(event.request_id) ?? nonEmptyString(data?.request_id);
  const toolCallId =
    nonEmptyString(event.tool_call_id) ??
    nonEmptyString(event.toolCallId) ??
    nonEmptyString(data?.tool_call_id) ??
    nonEmptyString(data?.toolCallId);
  const operationKind = requestId ? "approval" : toolCallId ? "tool" : null;
  const operationId = requestId ?? toolCallId;
  const createdAt = nonEmptyString(event.created_at) ?? new Date().toISOString();
  const id =
    nonEmptyString(event.id) ??
    nonEmptyString(event.event_id) ??
    operationId ??
    `${msgId}:${phase}:${createdAt}`;
  const status = normalizeTraceStatus(event.status);

  return {
    v: typeof event.v === "number" ? event.v : TRACE_EVENT_VERSION,
    id,
    event_id: nonEmptyString(event.event_id) ?? id,
    msg_id: msgId,
    channel_id: nonEmptyString(event.channel_id),
    trace_seq: typeof event.trace_seq === "number" ? event.trace_seq : null,
    producer_seq:
      typeof event.producer_seq === "number"
        ? event.producer_seq
        : typeof event.seq === "number"
          ? event.seq
          : null,
    kind:
      nonEmptyString(event.kind) ?? (phase === "approval" ? "approval" : "trace"),
    phase,
    status,
    title: nonEmptyString(event.title),
    message: nonEmptyString(event.message),
    data: event.data ?? null,
    request_id: requestId,
    tool_call_id: toolCallId,
    operation_kind:
      nonEmptyString(event.operation_kind) ?? operationKind,
    operation_id: nonEmptyString(event.operation_id) ?? operationId,
    is_terminal:
      typeof event.is_terminal === "boolean"
        ? event.is_terminal
        : TERMINAL_TRACE_STATUSES.has(status ?? ""),
    approval_kind:
      nonEmptyString(event.approval_kind) ??
      nonEmptyString(data?.approval_kind),
    decision: nonEmptyString(event.decision) ?? nonEmptyString(data?.decision),
    option_id: nonEmptyString(event.option_id) ?? nonEmptyString(data?.option_id),
    actor_id: nonEmptyString(event.actor_id) ?? nonEmptyString(data?.actor_id),
    created_at: createdAt,
  };
}

function mergeLifecycleEvent(older: TraceEvent, newer: TraceEvent): TraceEvent {
  const merged = { ...older } as TraceEvent & Record<string, unknown>;
  for (const [key, value] of Object.entries(newer)) {
    if (value !== null && value !== undefined) merged[key] = value;
  }
  merged.id = older.id;
  merged.event_id = older.event_id ?? older.id;
  merged.trace_seq = older.trace_seq ?? newer.trace_seq;
  merged.data = deepMergeOlderWithNewer(older.data, newer.data);
  merged.is_terminal =
    older.is_terminal ||
    newer.is_terminal ||
    TERMINAL_TRACE_STATUSES.has(newer.status ?? "");
  if (older.is_terminal && !newer.is_terminal) {
    merged.status = older.status;
  }
  return merged;
}

export function coalesceTraceEvents(
  ...sources: ReadonlyArray<ReadonlyArray<TraceEvent>>
): TraceEvent[] {
  const events = sources
    .flat()
    .map((event, arrival) => ({ event: normalizeTraceEvent(event), arrival }))
    .filter((item): item is { event: TraceEvent; arrival: number } => !!item.event)
    // ACP thought chunks are ephemeral stream state, not user-actionable steps.
    // Old connectors emitted them without a durable trace_seq, which caused the
    // coalescer to append "Thinking…" after prompt_finished on live screens.
    .filter((item) => item.event.phase !== "agent_thought_chunk")
    .sort((left, right) => {
      const leftSeq = left.event.trace_seq;
      const rightSeq = right.event.trace_seq;
      if (leftSeq !== null && rightSeq !== null && leftSeq !== rightSeq) {
        return leftSeq - rightSeq;
      }
      if (leftSeq !== null && rightSeq === null) return -1;
      if (leftSeq === null && rightSeq !== null) return 1;
      return left.arrival - right.arrival;
    });

  const result: TraceEvent[] = [];
  const indexes = new Map<string, number>();
  for (const { event } of events) {
    const key = event.operation_id
      ? `${event.operation_kind ?? "operation"}:${event.operation_id}`
      : `event:${event.id}`;
    const index = indexes.get(key);
    if (index === undefined) {
      indexes.set(key, result.length);
      result.push(event);
    } else {
      result[index] = mergeLifecycleEvent(result[index], event);
    }
  }
  return result;
}
