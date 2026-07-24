"use client";

import { useEffect } from "react";
import Lenis from "lenis";
import { gsap, ScrollTrigger } from "@/lib/gsapClient";

/**
 * Mounts Lenis smooth scroll, scoped to the marketing sections (Hero
 * through Download CTA) per website-design-patterns.md's Global Motion
 * Elements: "Lenis for smoothed scroll on the marketing sections... native
 * browser scroll on Legal & Policy pages." Only ever called from the Home
 * page tree -- Legal/About pages never mount this hook, so they keep
 * native scroll and stay free of the animation-library JS weight (per the
 * Performance Strategies section).
 *
 * Wires Lenis's scroll tick into GSAP's ScrollTrigger so `scrub`/pinned
 * ScrollTrigger animations (the Hero house-assembly, the pinned "How It
 * Works" step sequences) read from the same smoothed scroll position
 * instead of native `window.scrollY`.
 */
export function useLenis(enabled: boolean): void {
  useEffect(() => {
    if (!enabled) return;

    const lenis = new Lenis({
      duration: 1.1,
      easing: (t: number) => 1 - Math.pow(1 - t, 3), // approximates ease-out-smooth
      smoothWheel: true,
    });

    lenis.on("scroll", ScrollTrigger.update);

    const onTick = (time: number) => {
      lenis.raf(time * 1000);
    };
    gsap.ticker.add(onTick);
    gsap.ticker.lagSmoothing(0);

    return () => {
      lenis.destroy();
      gsap.ticker.remove(onTick);
    };
  }, [enabled]);
}
