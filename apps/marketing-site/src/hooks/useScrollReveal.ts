"use client";

import { useEffect, RefObject } from "react";
import { gsap, ScrollTrigger } from "@/lib/gsapClient";

/**
 * Shared "reveal on scroll enter" behavior used by every non-Hero section
 * (Differentiators panels, Trust Signals cards, About content, etc.) --
 * website-design-patterns.md: "every other section uses a single, calm
 * reveal-on-scroll-enter (mask-wipe or fade/slide, `ease-out-smooth`,
 * 400ms) with no continuous scroll-coupling." Applies to every element
 * matching `selector` inside `containerRef`, staggered per
 * `staggerSeconds`.
 */
export function useScrollReveal(
  containerRef: RefObject<HTMLElement | null>,
  selector: string,
  { stagger = 0.08, reduceMotion = false }: { stagger?: number; reduceMotion?: boolean } = {},
) {
  useEffect(() => {
    if (reduceMotion) return;
    const container = containerRef.current;
    if (!container) return;

    const targets = container.querySelectorAll(selector);
    if (!targets.length) return;

    const trigger = ScrollTrigger.create({
      trigger: container,
      start: "top 80%",
      once: true,
      onEnter: () => {
        gsap.to(targets, {
          opacity: 1,
          y: 0,
          duration: 0.4,
          ease: "power2.out", // approximates ease-out-smooth
          stagger,
        });
      },
    });

    return () => trigger.kill();
  }, [containerRef, selector, stagger, reduceMotion]);
}
