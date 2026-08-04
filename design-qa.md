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

---

# iOS Git Trace Design QA

- Source visual truth: `/Users/haowei/.codex/generated_images/019fca9d-8cb9-7132-902c-8b3ab0f45542/exec-b169790d-d7d3-4068-a2c9-42232557ef7c.png`
- Implementation screenshot: `/tmp/cheers-git-trace-no-new-font/5CCED4C7-AA37-4D15-BCAD-0CCB75AC2386.png`
- Target viewport: iPhone 17 Pro simulator, portrait, 1206 × 2622 px (@3x)
- State: dark mode, completed `git_status` event with staged, unstaged, and untracked files

## Full-view comparison evidence

The implementation preserves the source hierarchy—navigation title, outcome summary, branch and counts, changed files, command context, then the secondary action—using spacing and semantic color instead of cards or dividers. The final simulator screenshot was captured by the UI test from the production SwiftUI view and compared at original resolution.

## Comparison history

- Pass 1 [P2]: long paths used body-sized text and wrapped, making the file section visually dense. Fixed with the existing system caption style, one-line layout, and middle truncation.
- Pass 1 [P2]: a single bottom toolbar action was rendered by iOS as a prominent centered circular control. Fixed by moving Copy command into the scroll content as a native borderless 44 pt action.
- Intentional difference: View diff is not shown because the authoritative `git_status` event currently contains status entries but no diff payload or queryable repository context. Adding a non-functional action would violate the backend contract.

## Final findings

No P0, P1, or P2 visual issues remain in the tested state. File rows scan cleanly, status is distinguished by color plus the Git status letter, and the screen contains no custom cards or separators.

final result: passed

---

# Web Workbench Design QA

## Target

- Source visual: `/Users/haowei/.codex/generated_images/019fcbb5-7c0d-7733-abe7-1a405c90e286/exec-5f15d5cc-3f4a-47da-9e1e-526352fe0f64.png`
- Implementation: `frontend/dev/workbench-preview.html`
- Captured implementation: `/Users/haowei/.codex/visualizations/2026/08/04/019fcbb5-7c0d-7733-abe7-1a405c90e286/web-workbench-implementation-final.png`
- Combined comparison: `/Users/haowei/.codex/visualizations/2026/08/04/019fcbb5-7c0d-7733-abe7-1a405c90e286/web-workbench-comparison-final.png`
- Comparison frame: 1280 × 720 CSS pixels, standard density, Code project / Codemap / Gateway fs.patch selected.

## Evidence reviewed

- Full Workbench frame: existing outer drawer header and controls remain intact.
- Focused interior: scene navigation, item tabs, Codemap canvas, selected-node inspector, status legend, and graph controls.
- Narrow state: horizontal scene navigation and dismissible inspector overlay.
- Interaction checks: scene switch, item switch, node selection, and graph zoom.
- Browser console: no warnings or errors in a fresh preview tab.

## Findings and resolution

1. **P1 — Wide Codemap incorrectly opened a modal-like bottom inspector.** The resize observer mounted before asynchronous content created its target. Fixed by observing again when the parsed document becomes available; wide panels now use the persistent right inspector.
2. **P2 — Redundant scene title row reduced canvas height and diverged from the selected layout.** Removed; content tabs now align directly above the renderer canvas.
3. **P2 — Codemap nodes collapsed into one vertical column because layout was based on dotted identifier depth.** Replaced with deterministic graph-depth layers derived from edges, producing meaningful branches and convergence.
4. **P3 — Preview emitted a duplicate React root warning after hot updates.** The preview now reuses its root.

## Result

passed
