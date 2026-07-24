"use client";

import { useSyncExternalStore } from "react";
import {
  VisitorPlatform,
  getPlatformSnapshot,
  getServerPlatformSnapshot,
  subscribePlatformNoop,
} from "@/lib/platform";

/**
 * FEAT-039: reactive read of the visitor's detected platform (iOS/Android/
 * desktop), for `SmartDownloadButton`. `useSyncExternalStore` rather than
 * an effect + `setState` -- the UA string is static for the session, so
 * this is a one-shot external read, exactly what the hook is for.
 */
export function useDetectedPlatform(): VisitorPlatform {
  return useSyncExternalStore(subscribePlatformNoop, getPlatformSnapshot, getServerPlatformSnapshot);
}
