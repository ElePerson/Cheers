# iOS Composer Design QA

- Source visual truth: `/var/folders/tn/l7kr202d20q7j7rcxdy62pwc0000gn/T/codex-clipboard-4c4431fc-a7be-44e7-9d9c-8f730233927d.png`
- Implementation screenshot: unavailable; the signed build is installed and running on the connected iPhone, but CoreDevice does not expose screen capture
- Target viewport: connected iPhone 17, portrait
- Source pixels: 580 × 186
- State: empty, focused ChatGPT-style message composer

## Full-view comparison evidence

Blocked. The source was inspected at original resolution and the production SwiftUI implementation was built, installed, and launched on the connected iPhone. A matching implementation screenshot cannot be captured through CoreDevice, and the simulator does not contain the authenticated channel state.

## Code-level structure check

- Overall shell uses SwiftUI's native `Capsule()` with `.regularMaterial`.
- Composer is presented from the chat screen's bottom `safeAreaInset`; the surrounding area is transparent and no full-width toolbar background is drawn.
- The message timeline reserves the floating control's height so the final message can scroll above it instead of being obscured.
- Controls use native `Menu`, multiline `TextField`, `Button`, and SF Symbols.
- Control order is `plus`, input, `@`, `mic`, and `arrow.up`; each button uses the same 44 pt hit region and the row aligns them on the capsule's vertical center.
- Only one voice control remains. The blue primary action is exclusively the send button and is disabled for an empty draft.
- The input field uses `.textFieldStyle(.plain)` so no second nested outline appears inside the capsule.
- Existing attachment, mention, dictation, send, loading, and disabled behaviors remain connected.

## Findings

- [P2] True-device floating spacing, vertical centering, and material contrast are not visually proven.
  - Location: the full Composer capsule.
  - Evidence: source visual is available; matching implementation screenshot is unavailable.
  - Impact: the system material may need a small contrast adjustment against the channel background.
  - Fix: capture the installed channel screen in the empty Composer state and compare it with the source.

## Required fidelity surfaces

- Shape: native capsule, not a fixed-radius rounded rectangle.
- Icons: SF Symbols only; no custom icon assets required.
- Spacing: compact internal spacing with 44 pt minimum control targets.
- Interaction: `@` inserts a mention token and focuses the field; `mic` controls dictation; `arrow.up` sends a non-empty draft.
- Placement: floating above the bottom safe area rather than occupying a row in the main chat stack.

final result: blocked
