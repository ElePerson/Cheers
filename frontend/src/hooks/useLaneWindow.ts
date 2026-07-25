import { createContext, useContext } from "react";
import { useIsMobile } from "@/hooks/useIsMobile";
import { useWindowDrag, type WindowDrag } from "@/hooks/useWindowDrag";
import type { SpawnKind } from "@/features/chat/workbench/laneSnap";

// The work lane publishes its live bounding rect (viewport coords) here so the
// instrument panels floating inside it know the box to drag/resize within.
// `null` provider = no lane (mobile, or a window that floats over the viewport
// like the Channel files dialog).
export const LaneBoundsContext = createContext<(() => DOMRect | null) | null>(null);

export interface LaneWindow {
  /** Render as a draggable/resizable floating window: desktop AND inside a lane. */
  float: boolean;
  isMobile: boolean;
  /** Drag/resize/stacking + snap-to-zone state (see useWindowDrag). Inert when
   *  not floating. */
  drag: WindowDrag;
}

export interface LaneWindowOptions {
  /** Panel visibility — drives auto-spawn and occupant registry. */
  open?: boolean;
  /** Bias first-open placement (fill lane alone / prefer a free zone). */
  spawnKind?: SpawnKind;
}

// Shared wiring for the lane's instrument windows (ViewBoard / Workbench /
// Remote workspace / Channel files). Each panel keeps its own chrome and just
// spreads `drag.handleProps` onto its title bar and renders a ResizeGrip; this
// hook decides whether it floats (desktop, in a lane), binds it to the lane
// bounds, and turns on FancyZones-style snapping (the LaneZones overlay lights
// up the target zone; drop snaps position+size to it).
export function useLaneWindow(
  storageKey: string,
  options: LaneWindowOptions = {}
): LaneWindow {
  const isMobile = useIsMobile();
  const getBounds = useContext(LaneBoundsContext);
  const float = !isMobile && getBounds != null;
  const drag = useWindowDrag(storageKey, !isMobile, float ? getBounds! : undefined, {
    snap: float,
    spawnKind: float ? options.spawnKind : undefined,
    open: options.open,
  });
  return { float, isMobile, drag };
}
