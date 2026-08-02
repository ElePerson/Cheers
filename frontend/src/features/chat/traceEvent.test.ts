import { describe, expect, it } from "vitest";
import type { TraceEvent } from "@/types";
import { coalesceTraceEvents, normalizeTraceEvent } from "./traceEvent";

describe("TraceEvent v1", () => {
  it("normalizes a legacy live tool payload", () => {
    const event = normalizeTraceEvent({
      event_id: "call-1",
      msg_id: "message-1",
      phase: "tool_call_update",
      status: "completed",
      data: { tool_call_id: "call-1" },
    });

    expect(event).toMatchObject({
      v: 1,
      id: "call-1",
      tool_call_id: "call-1",
      operation_kind: "tool",
      operation_id: "call-1",
      is_terminal: true,
    });
  });

  it("normalizes cross-agent status vocabulary", () => {
    const event = normalizeTraceEvent({
      msg_id: "message-1",
      phase: "tool_call_update",
      status: "done",
      tool_call_id: "call-1",
    });

    expect(event?.status).toBe("completed");
    expect(event?.is_terminal).toBe(true);
  });

  it("coalesces REST and live lifecycle rows without losing detail", () => {
    const opening = normalizeTraceEvent({
      v: 1,
      id: "row-1",
      msg_id: "message-1",
      trace_seq: 1,
      kind: "trace",
      phase: "tool_call",
      status: "in_progress",
      title: "Write novel.txt",
      data: {
        tool_call_id: "call-1",
        input: { path: "novel.txt", content: "draft" },
      },
      created_at: "2026-08-02T09:00:00Z",
    }) as TraceEvent;
    const terminal = normalizeTraceEvent({
      v: 1,
      id: "call-1",
      msg_id: "message-1",
      kind: "trace",
      phase: "tool_call_update",
      status: "completed",
      data: { tool_call_id: "call-1", output: { bytes: 5 }, input: null },
      created_at: "2026-08-02T09:00:01Z",
    }) as TraceEvent;

    const [merged] = coalesceTraceEvents([opening], [terminal]);
    expect(merged.id).toBe("row-1");
    expect(merged.trace_seq).toBe(1);
    expect(merged.title).toBe("Write novel.txt");
    expect(merged.status).toBe("completed");
    expect(merged.is_terminal).toBe(true);
    expect(merged.data).toEqual({
      tool_call_id: "call-1",
      input: { path: "novel.txt", content: "draft" },
      output: { bytes: 5 },
    });
  });

  it("deduplicates the same non-lifecycle row across transports", () => {
    const event = normalizeTraceEvent({
      id: "plan-1",
      msg_id: "message-1",
      phase: "plan",
      status: "completed",
      created_at: "2026-08-02T09:00:00Z",
    }) as TraceEvent;

    expect(coalesceTraceEvents([event], [event])).toHaveLength(1);
  });

  it("does not reopen a terminal operation when a stale frame arrives", () => {
    const terminal = normalizeTraceEvent({
      id: "call-1",
      msg_id: "message-1",
      phase: "tool_call_update",
      status: "completed",
      data: { tool_call_id: "call-1" },
      created_at: "2026-08-02T09:00:01Z",
    }) as TraceEvent;
    const stale = normalizeTraceEvent({
      id: "call-1",
      msg_id: "message-1",
      phase: "tool_call_update",
      status: "in_progress",
      data: { tool_call_id: "call-1" },
      created_at: "2026-08-02T09:00:00Z",
    }) as TraceEvent;

    const [merged] = coalesceTraceEvents([terminal], [stale]);
    expect(merged.is_terminal).toBe(true);
    expect(merged.status).toBe("completed");
  });

  it("does not render transient thought chunks as lifecycle steps", () => {
    const finished = normalizeTraceEvent({
      id: "finished-1",
      msg_id: "message-1",
      trace_seq: 3,
      phase: "prompt_finished",
      status: "completed",
      created_at: "2026-08-02T09:00:02Z",
    }) as TraceEvent;
    const thought = normalizeTraceEvent({
      id: "thought-1",
      msg_id: "message-1",
      producer_seq: 2,
      phase: "agent_thought_chunk",
      status: "running",
      created_at: "2026-08-02T09:00:01Z",
    }) as TraceEvent;

    expect(coalesceTraceEvents([finished], [thought])).toEqual([finished]);
  });
});
