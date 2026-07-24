// FEAT-039: platform detection for the Smart Download Button. Client-only
// (no backend dependency, per architecture.md's Marketing Website
// component) -- reads the browser's own UA string, and fails gracefully to
// "desktop" (showing both store badges + QR, never a broken/blank action)
// whenever detection is inconclusive, per FEAT-039's acceptance criteria.

export type VisitorPlatform = "ios" | "android" | "desktop";

// Sourced directly from official store listings -- App Store Connect /
// Google Play Console assign these once the app is submitted. Kept in one
// place so a real listing URL only ever needs to change here.
export const APP_STORE_URL = "https://apps.apple.com/app/de-duke/id0000000000";
export const PLAY_STORE_URL = "https://play.google.com/store/apps/details?id=com.deduke.app";

/**
 * Detects the visitor's platform from `navigator.userAgent`.
 * Always safe to call during SSR/SSG -- returns "desktop" when `window` is
 * unavailable, so the statically-exported page never throws. Also doubles
 * as `useSyncExternalStore`'s server snapshot for `useDetectedPlatform`
 * below.
 */
export function detectPlatform(): VisitorPlatform {
  if (typeof navigator === "undefined") return "desktop";

  const ua = navigator.userAgent || "";

  // iPadOS 13+ reports as "Macintosh" but exposes touch points -- checked
  // first so iPads route to the App Store rather than falling through to
  // the desktop QR-code fallback.
  const isIPadOS = ua.includes("Macintosh") && navigator.maxTouchPoints > 1;
  if (/iPhone|iPad|iPod/.test(ua) || isIPadOS) return "ios";
  if (/Android/.test(ua)) return "android";

  return "desktop";
}

/** Resolves the correct store URL for a given platform. Returns null for
 * "desktop", since desktop visitors get a QR code + both badges instead of
 * a single redirect target. */
export function storeUrlFor(platform: VisitorPlatform): string | null {
  if (platform === "ios") return APP_STORE_URL;
  if (platform === "android") return PLAY_STORE_URL;
  return null;
}

// Cached the same way useLowEndDevice caches its computation -- UA doesn't
// change mid-session, so there's nothing to subscribe to. Exported for
// `useDetectedPlatform` (src/hooks/useDetectedPlatform.ts) to build a
// `useSyncExternalStore`-based hook on top of, instead of `setState` inside
// an effect.
let cachedPlatform: VisitorPlatform | null = null;

export function getPlatformSnapshot(): VisitorPlatform {
  if (cachedPlatform === null) cachedPlatform = detectPlatform();
  return cachedPlatform;
}

export function subscribePlatformNoop(): () => void {
  return () => {};
}

export function getServerPlatformSnapshot(): VisitorPlatform {
  return "desktop"; // Matches detectPlatform()'s own SSR fallback.
}
