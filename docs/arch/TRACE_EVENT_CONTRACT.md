# TraceEvent v1 Contract

`TraceEvent` is the client-facing lifecycle event used by both:

- `GET /api/v1/channels/:channel_id/messages/:msg_id/trace`
- channel WebSocket frames whose `type` is `bot_trace`

The Gateway normalizes both transports before delivery. Clients must not define
transport-specific trace shapes.

## Fields

| Field | Type | Meaning |
| --- | --- | --- |
| `v` | integer | Contract version. Current value: `1`. |
| `id` | string | Identity of one lifecycle row; stable across REST and WebSocket. |
| `event_id` | string | Compatibility alias for `id`; new clients use `id`. |
| `msg_id` | string | Bot-turn message that owns the event. |
| `channel_id` | string/null | Channel scope. |
| `trace_seq` | integer/null | Durable per-message ordering; live-only events may be null. |
| `producer_seq` | integer/null | Producer ordering used to mint a stable id before persistence. |
| `kind` | string | `trace` or `approval`. |
| `phase` | string | Producer phase such as `tool_call`, `tool_call_update`, `plan`, or `approval`. |
| `status` | string/null | Normalized lifecycle status. |
| `title`, `message` | string/null | Human-readable summary and detail. |
| `data` | JSON/null | Structured tool/plan/approval detail. |
| `request_id` | string/null | Approval correlation id. |
| `tool_call_id` | string/null | Tool lifecycle correlation id. |
| `operation_kind` | string/null | `approval` or `tool`. |
| `operation_id` | string/null | Canonical lifecycle correlation id. |
| `is_terminal` | boolean | Whether this event closes its operation. |
| `approval_kind`, `decision`, `option_id`, `actor_id` | string/null | Approval lifecycle metadata. |
| `created_at` | RFC 3339 string | Event creation time. |

Terminal statuses are `completed`, `approved`, `denied`, `failed`, `cancelled`,
`refused`, `truncated`, and `max_turn_requests`.

Gateway normalization maps `running`/`started` to `in_progress`,
`complete`/`done`/`success`/`succeeded` to `completed`, and `error` to `failed`.
`id` and `operation_id` are intentionally different: opening and terminal tool
rows have distinct event ids but share one operation id.

## Coalescing

Every client applies the same rules:

1. Order durable events by `trace_seq`; keep arrival order for live-only events.
2. Correlate by `operation_kind + operation_id`. If there is no operation id,
   deduplicate the same persisted/live row by `id`.
3. A newer non-null scalar replaces the older value.
4. Merge JSON objects recursively. Missing or null newer keys keep the older
   value so terminal deltas cannot erase tool input, output, diff, or approval
   title detail.
5. Keep the opening event's `id` and first durable `trace_seq`; expose the newest
   lifecycle status and terminal flag.
6. Terminal closure is monotonic. A delayed non-terminal frame cannot reopen a
   completed, denied, failed, or cancelled operation.

This makes a live terminal delta and a later REST replay render as one identical
operation on iOS, Web, and the macOS desktop shell.
