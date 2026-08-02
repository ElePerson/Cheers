# Message Trace Experience

> Status: proposed. This document defines the mobile and macOS presentation of
> per-message agent activity, including tool, edit, write, approval, and failure
> events.

## Product decision

Trace belongs to the bot message that owns the run. It is exposed through one
persistent trace button directly below that message's content; it is not rendered
as loose italic status text and it is not hidden in the message hover toolbar.

The same button is present while the message is running and after it completes:

- Running: spinner + current action + event count, for example
  `Editing MessageItem.tsx · 4 steps`.
- Completed: check + compact summary, for example `4 actions · 8.2s`.
- Failed: error icon + failing action, for example `Write failed · 4 steps`.
- No recorded activity: hide the button after completion.

This makes the control discoverable on touch devices, keeps activity attached to
the correct response, and avoids moving the user's target when the run finishes.

## Message layout

### Mobile

- Use a single full-width message column with 12px horizontal page padding.
- Keep avatar, sender, BOT badge, and timestamp on one compact header row.
- Bot content starts below the header and may use the full available width.
- Place the trace button immediately after the response content and before files,
  context chips, and message actions.
- The trace button has a minimum 44px touch target, but visually remains a quiet,
  borderless zinc surface consistent with the existing design system.
- Do not rely on hover. Reply, copy, forward, and select live in the existing
  long-press or overflow action surface.
- While the bot has not emitted text yet, show the trace button in the normal body
  position with `Thinking…`; do not show a separate bouncing-dots row plus a second
  trace label.

Tapping the trace button opens a bottom sheet. The sheet uses 85vh maximum height,
a sticky title (`Agent activity`), the running state or final duration, a scrollable
event list, and a sticky close affordance. The message remains visible behind the
sheet so ownership is clear.

### macOS / desktop

- Preserve the current avatar gutter and readable message width.
- Place the same persistent trace button below the bot response. It must not be
  part of the hover-only reply/copy/forward toolbar.
- Clicking the button expands the timeline inline when the list is short (up to
  six events). For longer traces, or when an event detail is opened, use a right
  inspector panel so code and diffs retain useful width.
- The inspector title links back to the owning message and remains open while the
  user compares events.
- Keyboard: the button and every event row are focusable; Enter/Space opens,
  Escape closes the detail layer, and focus returns to the invoking row.

## Timeline

The timeline is live. Events append without collapsing the panel, the active row
shows a restrained spinner, and completed rows settle to a check without changing
position. Updates for the same `tool_call_id` update an existing row rather than
adding duplicate `tool_call` and `tool_call_update` rows.

Event rows use a consistent structure:

1. category icon;
2. human action label;
3. short target, usually a command, file name, or tool name;
4. status and elapsed time;
5. chevron when detail is available.

Suggested labels:

| Event | Compact row | Detail view |
|---|---|---|
| Generic tool | `Search · MessageItem` | Tool name, sanitized input, output preview, status, duration |
| Read | `Read · MessageItem.tsx` | Path, requested range, returned excerpt |
| Edit | `Edit · MessageItem.tsx` | Unified diff, additions/deletions, result |
| Write | `Write · MESSAGE_TRACE_EXPERIENCE.md` | Path, size, content preview, result |
| Command | `Run · frontend tests` | Command, working directory, exit code, output |
| Approval | `Approval · terminal command` | Request, options, actor, decision, time |
| Plan | `Plan updated · 2/4` | Step list and current states |
| Failure | `Write failed · MessageItem.tsx` | Error message and retry context when safe |

Use the connector-provided tool name as the primary identity when it is known.
Map known tools to friendly verbs, but always retain the original tool name in
the detail header. Unknown tools fall back to a humanized name and generic wrench
icon; they remain clickable when they carry detail.

## Event details

Yes, individual events can be clickable by tool name. Selection is driven by the
event payload, not by hard-coded UI routes.

- Mobile: tapping an event replaces the timeline sheet body with a detail page;
  a Back control returns to the same scroll position.
- macOS: selecting an event opens the right inspector. Selecting another row
  updates the inspector without closing the timeline.
- Text and JSON use selectable monospace blocks with Copy actions.
- Edits render a unified diff with file header and addition/deletion counts.
- Writes show a content preview and offer `Open file` only when the workspace
  resolver confirms the path belongs to the current bot workspace.
- Command output is collapsed by default after 20 lines and never auto-scrolls
  the whole conversation.
- Secrets, environment values, authorization headers, and policy-hidden payloads
  must be removed server-side before delivery. The UI should not attempt to be
  the security boundary.

An event row without useful detail is not a dead button: render it as a static
row with no chevron and no hover/pressed treatment.

## Motion and status

- Use opacity and icon transitions of 120–180ms; do not animate timeline height
  for every live event.
- Honor `prefers-reduced-motion`; replace spinners with a static progress glyph.
- Keep colors quiet: zinc for normal activity, amber for waiting approval, red
  for failure, and indigo only for focus/selection.
- Announce new running labels through one polite live region, throttled so rapid
  tool updates do not overwhelm screen readers.

## Required data contract

The current frontend keeps only `message._trace: string`, which cannot power the
timeline. Introduce a per-message live event collection keyed by event identity:

```ts
interface LiveTraceEvent {
  id: string;
  tool_call_id?: string;
  phase: string;
  category: "tool" | "read" | "edit" | "write" | "command" | "plan" | "approval";
  tool_name?: string;
  title: string;
  status: "pending" | "in_progress" | "completed" | "failed";
  message?: string;
  started_at?: string;
  completed_at?: string;
  duration_ms?: number;
  detail?: {
    input?: unknown;
    output?: unknown;
    path?: string;
    diff?: string;
    exit_code?: number;
  };
}
```

The gateway's live `bot_trace` frame should forward the stable event id,
`tool_call_id`, phase, status, title, message, sanitized `data`, and timestamps.
On completion, the UI reconciles this live collection with the durable trace API
by id/tool-call id and trace sequence. Reloading the channel therefore produces
the same timeline the user saw during execution.

## Acceptance criteria

- A trace button appears on mobile before the first response token and updates
  through completion without relocating.
- The button is associated with exactly one bot message and exposes that message's
  events only.
- Tool, edit, write, command, plan, approval, and failure rows have distinct,
  readable labels.
- Events with detail open on both mobile and macOS; events without detail are not
  styled as clickable.
- Live and reloaded timelines preserve order and do not duplicate tool updates.
- Long commands, JSON, diffs, and output never force horizontal page scrolling.
- Touch targets, keyboard focus, reduced motion, and screen-reader status updates
  are covered by component tests.
