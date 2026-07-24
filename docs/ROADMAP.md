# Cheers Roadmap

> **Language**: English | [中文](ROADMAP.zh-CN.md)

The public, product-facing milestone roadmap and current preview status.

This is the English default edition prepared for the open-source documentation set. The full Chinese version is preserved next to this file for readers who prefer Chinese or need the original historical wording.

> For the engineering **execution** plan (milestone-by-milestone build order, acceptance gates, refactor items R1–R14), see [docs/arch/ROADMAP.md](arch/ROADMAP.md) — that is a separate, working engineering document; this file is the public product roadmap.

## Key Topics

- M1 core chat path
- M2 multi-agent collaboration
- M3 Coordinator routing
- Portal phase planning
- Long-term reliability and knowledge-base work

## Current Guidance

- Prefer the English `.md` file as the default public entry point.
- Use the `.zh-CN.md` file as the Chinese mirror.
- For implementation details, verify against the current code and the user/operations documentation first.
- Historical design notes may describe planned features; when in doubt, treat README, `docs/help/`, and the current code as authoritative.

## Strategic Direction

> **Not a better Slack — the governance workspace for agent fleets. Chat is the
> interface; governance is the product.**

Teams are heading toward running 5–20 agents, not one. At that point the hard
questions — who may command which agent, whose budget it spends, who approved
which action, where agents collaborate — can only be answered by the party that
**owns the identity, permission, and audit model**. That is what Cheers builds:
bots as first-class members of Cheers's *own* governance model, not guests inside
someone else's chat app. (Full competitive analysis: [COMPARISON.md](COMPARISON.md).)

Three phases:

1. **Make governance undeniable** — approval UX as smooth as reviewing a PR
   (diff preview, one-click approve/deny, decision recorded to audit); per-bot /
   per-channel **cost budgets** that pause and escalate on overrun (governance,
   not just tracking); **audit export** and retention policy, turning the
   Viewboard trail into a compliance feature for self-hosted enterprises.
2. **Ship an official Slack/Discord bridge as the adoption funnel** — `@` a
   Cheers bot from Slack; work runs in a Cheers channel under full permissions
   and audit; results post back with a link to the full trail. Teams start
   without migrating; the bridge is the funnel, the platform is the product.
3. **Multi-agent orchestration** — a channel as the governed "meeting room"
   where several external agents (ACP/MCP) and humans work under one grant
   matrix, with the Workbench as the shared blackboard and humans as approval
   nodes. As agents commoditize, the scarce layer is the governed space they
   share.

Roadmap filter for new items: **does this make multi-agent governance stronger?**

### Fleet view — follow-ups

The Fleet view (workspace mission control: approvals inbox + bot roster) shipped
its live P2 (`bot_processing` chips, rail approval badge). Recorded next:

- **Bot-to-bot dispatch under the grant matrix** (in progress) — an agent may
  `@` another agent to hand off a subtask, but every such dispatch passes a new
  `dispatch` capability in the `user ▸ group ▸ role ▸ *` matrix (deny wins,
  owner-only default) and is audited. This is the governance edge no bridge can
  match — see [docs/design/BOT_DISPATCH.md](design/BOT_DISPATCH.md).
- **Fleet P3** (recorded, not started) — in-channel mini fleet strip (a compact
  per-channel roster in the work lane) and approvals-inbox filters (by bot / by
  operation kind / by channel).

### Resource context — attachable Cheers resources as agent context

The Cheers-native `@context`: any participant attaches Cheers's own resources
(plan, board, file, message/thread, decisions) as structured context to an agent
invocation — two producers (human manual pick, bot automatic handoff) over one
foundation, with consumer-governed reads. Design:
[docs/design/RESOURCE_CONTEXT.md](design/RESOURCE_CONTEXT.md). Phases:
F0 foundation → F1 human picker → F2 bot handoff → F3 suggested context.

## Near-Term Plans

### Next priorities (2026 H2)

Product focus after the Passkey / iOS friends / desktop updater wave:

1. **iOS App hardening** (native `apps/ios` is shipped; no longer deferred behind PWA) — tracking [#318](https://github.com/ElePerson/Cheers/issues/318)
   - [ ] **UI** — spacing-first / HIG alignment, localization gaps, dense-list and decorative-divider cleanup.
   - [ ] **Tracing** — end-to-end client/gateway correlation for login, push, realtime reconnect, and approval deep-links (so mobile regressions are diagnosable).
   - [ ] **Policy & security** — App Store / privacy disclosures, remote-operations copy, AI-consent surfaces, session/trusted-device behavior parity with web/desktop.
2. **macOS desktop — security & policy polish** — tracking [#319](https://github.com/ElePerson/Cheers/issues/319)
   - [ ] Ship and keep in sync the same policy surfaces as web (privacy, support, remote operations, account deletion) inside the Tauri shell / About / Settings.
   - [ ] Harden updater + signing UX (Gatekeeper notes, trusted feed, Settings → About → Check for updates).
   - [ ] Connector/daemon security defaults (least privilege, clear remote-ops warnings).
3. **Plugin / Workbench mechanism — integration tests & optimization** — tracking [#320](https://github.com/ElePerson/Cheers/issues/320)
   - [ ] Integration-test matrix for official plugins + template installs (load, fs bridge, save/reload, permission denials).
   - [ ] Performance / reliability pass (cold start, large boards, failure recovery).
   - [ ] Document the plugin contract for third-party authors and keep examples green in CI.

### UI

- [ ] Unify UI hover states.
- [ ] Apply the spacing-first grouping rule to the native iOS surfaces; replace
      presentation-only dividers while retaining row rules only for dense data.
- [ ] Fix missing Chinese and English localization coverage.
- [ ] Optimize default options.

### Backend

- [ ] Clean up and organize backend code.
- [ ] Clarify message queue responsibilities and flow.
- [ ] Plan remote bot workspace isolation, including per-bot working directories, permission boundaries, cleanup policy, and deployment/runtime safeguards.

### Features

- [ ] DingTalk integration.
- [x] PWA + Web Push: installable web app; approval requests and @mentions
      reach the approver's lock screen and deep-link back to the pending card.
- [x] iOS native app (v1 shipped) — **next:** UI / tracing / policy & security (see Next priorities).
- [ ] Android app — same gate as historical mobile strategy; revisit after iOS hardening.

## Client Strategy & Boundaries

Where each client surface starts and stops. Decided 2026-07 alongside the
PWA/Web Push work; the guiding split: **the gateway is the control plane and
sole source of truth; local machines are the data plane** (see
[arch/ARCHITECTURE_OVERVIEW.md](arch/ARCHITECTURE_OVERVIEW.md)).

### Mobile = consume + approve (PWA + native iOS)

The mobile jobs are: approve a blocked permission request, glance at running
work, reply when mentioned. PWA + Web Push
(`frontend/src/sw.ts`, gateway `infra/web_push.rs`) remains the universal
path; native iOS (`apps/ios`) is now shipping for push reliability and
deeper OS integration. Near-term work is hardening (UI / tracing /
policy & security), not green-field feature parity races with desktop.
Android stays gated until iOS hardening proves the native investment.

### Desktop = the chat shell + the connector's graphical home

**Status: shipping (`apps/macos`, Tauri v2; desktop-v0.1.x releases).** The desktop client
hosts the SAME built frontend as the web deployment (chat shell included —
no UI rewrite), adds tray residency + native notifications (WKWebView has no
Web Push, so nudges arrive over the user-scoped WS), and differentiates as
**the graphical home of the connector daemon**. Near-term focus shifts to
**security & policy polish** (see Next priorities). Its value, in priority order:

1. **Daemon lifecycle** — bundle `cce-acp-connector` as a
   sidecar, start-with-app + revive on crash (the macOS answer to the
   systemd-linger pitfall), GUI start/stop/status/logs and TOML editing. This
   converts connector onboarding from ops work into "install an app", and is
   the only item that *requires* a native artifact.
2. **Same-machine fast path (data plane only)** — when the desktop app detects
   a co-located connector, bypass the gateway round-trip for bulk data:
   open/transfer workspace files directly (the local ops already exist in
   `bridge_runtime::handle_workspace_req`; they lack only a local entry point —
   extend `loopback.rs` with a discoverable port+token under `CHEERS_ACP_HOME`),
   attach to live terminal/output streams, and show approval context (command,
   diff) read straight from the local daemon.
3. Tray + global hotkey, "open in local editor" for agent-touched files.

**Red lines** (violating these forfeits the product's core value):

- Messages and permission *decisions* always go through the gateway — never a
  local bypass. Persistence, multi-device sync, other members' visibility, and
  the audit trail all hang off the gateway being the single source of truth.
- No UI rewrite: the desktop shell hosts the same built frontend.
- The same-machine link carries *data* (files, streams, context), not *control*.

## Related Documentation

- [Documentation Home](help/README.md)
- [User Manual](help/使用说明书.md)
- [Engineering execution roadmap](arch/ROADMAP.md)
