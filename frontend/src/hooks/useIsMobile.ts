import { useSyncExternalStore } from "react";

/**
 * Single source of truth for the app's mobile breakpoint. Kept in lockstep with
 * Tailwind's `md` screen (768px): every `max-md:` utility in the codebase and every
 * JS-side `useIsMobile()` check flips at exactly the same width, so layout structure
 * (JSX branches) and styling (classes) can never disagree. Desktop (>= 768px, and in
 * particular >= 1024px) renders exactly as before — all mobile behavior is additive
 * below this breakpoint.
 */
export const MOBILE_MEDIA_QUERY = "(max-width: 767px)";

function subscribe(onChange: () => void): () => void {
  const mql = window.matchMedia(MOBILE_MEDIA_QUERY);
  mql.addEventListener("change", onChange);
  return () => mql.removeEventListener("change", onChange);
}

function getSnapshot(): boolean {
  return window.matchMedia(MOBILE_MEDIA_QUERY).matches;
}

// SSR/snapshot fallback: this app is a pure SPA, but keep the server snapshot
// deterministic (desktop) for tooling that renders without a window.
function getServerSnapshot(): boolean {
  return false;
}

/** True below Tailwind's `md` breakpoint (i.e. on phones). Live-updates on resize/rotate. */
export function useIsMobile(): boolean {
  return useSyncExternalStore(subscribe, getSnapshot, getServerSnapshot);
}
