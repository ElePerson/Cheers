import { useCallback, useEffect, useRef, useState } from "react";

/**
 * Hover-visible state that survives the gap between a trigger and a floating
 * panel anchored a few pixels away from it (e.g. a message row and its hover
 * action bar, rendered via `FloatingLayer`). Hiding on a plain `onMouseLeave`
 * fires the instant the cursor exits the trigger's box — including mid-move
 * *toward* the panel — so the panel (and its `pointer-events-none` while
 * hidden) vanishes underneath the pointer before the click lands. Delaying
 * the hide by `hideDelayMs` gives the cursor time to reach the panel and call
 * `show` again, which cancels the pending hide.
 */
export function useHoverIntent(hideDelayMs = 250): {
  visible: boolean;
  show: () => void;
  hide: () => void;
} {
  const [visible, setVisible] = useState(false);
  const hideTimer = useRef<ReturnType<typeof setTimeout> | null>(null);

  const clearPendingHide = () => {
    if (hideTimer.current !== null) {
      clearTimeout(hideTimer.current);
      hideTimer.current = null;
    }
  };

  const show = useCallback(() => {
    clearPendingHide();
    setVisible(true);
  }, []);

  const hide = useCallback(() => {
    clearPendingHide();
    hideTimer.current = setTimeout(() => setVisible(false), hideDelayMs);
  }, [hideDelayMs]);

  useEffect(() => clearPendingHide, []);

  return { visible, show, hide };
}
