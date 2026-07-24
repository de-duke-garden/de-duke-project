"use client";

import { useSyncExternalStore } from "react";

const QUERY = "(prefers-reduced-motion: reduce)";

function subscribe(callback: () => void) {
  const mediaQuery = window.matchMedia(QUERY);
  mediaQuery.addEventListener("change", callback);
  return () => mediaQuery.removeEventListener("change", callback);
}

function getSnapshot() {
  return window.matchMedia(QUERY).matches;
}

// Defaults to `false` on the server/first paint so the static export never
// flashes reduced content before hydration corrects it on a non-reduced-
// motion device.
function getServerSnapshot() {
  return false;
}

/**
 * Tracks the `prefers-reduced-motion` media query. Used sitewide to skip
 * the Hero's WebGL house-assembly, parallax, and hover motion per
 * website-design-patterns.md's Performance Strategies ("Reduced motion
 * respected").
 *
 * Uses `useSyncExternalStore` rather than an effect + `setState` -- this is
 * exactly the case it exists for (subscribing to state that lives outside
 * React, here the browser's media-query state) and it satisfies
 * `react-hooks/set-state-in-effect` without needing to suppress the rule.
 */
export function usePrefersReducedMotion(): boolean {
  return useSyncExternalStore(subscribe, getSnapshot, getServerSnapshot);
}
