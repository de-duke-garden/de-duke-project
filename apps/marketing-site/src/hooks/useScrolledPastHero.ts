"use client";

import { useSyncExternalStore } from "react";

// Roughly matches the Hero's `min-height: 100vh` -- switches the Home
// page's Navbar from transparent (floating over the Hero's photograph) to
// a solid background once the visitor has scrolled past it, per the
// standard "transparent-over-hero, solid-after" nav pattern. Only
// meaningful on the Home page (see Navbar's `overPhoto` prop) -- pages
// without a hero render the nav solid unconditionally instead of
// consulting this hook's result.
const THRESHOLD_RATIO = 0.85;

function subscribe(callback: () => void) {
  window.addEventListener("scroll", callback, { passive: true });
  window.addEventListener("resize", callback);
  return () => {
    window.removeEventListener("scroll", callback);
    window.removeEventListener("resize", callback);
  };
}

function getSnapshot(): boolean {
  return window.scrollY > window.innerHeight * THRESHOLD_RATIO;
}

function getServerSnapshot(): boolean {
  return false; // Transparent by default before hydration/scroll info is available.
}

/** Whether the visitor has scrolled roughly past the Hero section. */
export function useScrolledPastHero(): boolean {
  return useSyncExternalStore(subscribe, getSnapshot, getServerSnapshot);
}
