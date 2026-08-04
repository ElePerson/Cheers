# Tool Presentation Design

> Implementation target: Web and macOS first. iOS consumes the same wire type in the next phase.

## Selected direction

The tool row is one quiet, continuous surface. It does not use timelines,
connectors, table grids, row separators, nested outlines, or decorative badges.
Hierarchy comes from spacing, typography, opacity, and alignment.

- The activity row contains the tool icon, operation, short target, terminal state,
  and one disclosure affordance.
- The detail surface contains branch/context, a compact result list, and text
  disclosures for the command or diff.
- Green is reserved for success/additions; muted red is reserved for
  failures/deletions. All other tool categories remain neutral.
- Desktop may align secondary metadata to the right. At narrow widths paths wrap,
  metadata stacks, and controls retain a minimum 44-point hit target.

## Unified parsing boundary

The Gateway owns source classification and emits `TraceEvent.data.presentation`.
Web, macOS, and iOS parse that versioned descriptor into platform-native types;
they do not maintain separate regular-expression tables.

```text
ACP producer payload
  -> Gateway alias/command matching
  -> ToolPresentation v1
  -> Web parser -> React renderer
                -> macOS Tauri webview (same renderer)
                -> iOS parser/SwiftUI renderer (next phase)
```

The interactive reference is [tool-presentation-prototype.html](tool-presentation-prototype.html).
The wire-level contract is documented in
[TOOL_PRESENTATION.md](../arch/TOOL_PRESENTATION.md).

