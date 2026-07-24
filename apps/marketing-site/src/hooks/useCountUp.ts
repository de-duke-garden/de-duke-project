"use client";

import { RefObject, useEffect, useState } from "react";

/**
 * Lightweight count-up-from-zero animation, triggered once the target
 * element scrolls into view -- Screen 32's Trust Signals section
 * ("Numbers... count up from zero as the section enters the viewport").
 * Hand-rolled rather than pulling in a dedicated count-up library, per
 * website-design-patterns.md's "lightweight count-up library" guidance --
 * this is a ~20 line requestAnimationFrame loop, not worth a dependency.
 */
export function useCountUp(
  targetRef: RefObject<HTMLElement | null>,
  endValue: number,
  { durationMs = 1400, reduceMotion = false }: { durationMs?: number; reduceMotion?: boolean } = {},
) {
  const [value, setValue] = useState(0);

  useEffect(() => {
    // With reduced motion, the return value below renders `endValue`
    // directly -- skip wiring the observer/animation loop entirely rather
    // than animating and then calling setState to override it.
    if (reduceMotion) return;
    const node = targetRef.current;
    if (!node) return;

    const observer = new IntersectionObserver(
      ([entry]) => {
        if (!entry.isIntersecting) return;
        observer.disconnect();

        const start = performance.now();
        const tick = (now: number) => {
          const progress = Math.min(1, (now - start) / durationMs);
          const eased = 1 - Math.pow(1 - progress, 3); // ease-out-smooth-ish
          setValue(Math.round(eased * endValue));
          if (progress < 1) requestAnimationFrame(tick);
        };
        requestAnimationFrame(tick);
      },
      { threshold: 0.4 },
    );

    observer.observe(node);
    return () => observer.disconnect();
  }, [targetRef, endValue, durationMs, reduceMotion]);

  // Reduced motion (or any failure of the IntersectionObserver reveal path
  // -- e.g. a privacy tool disabling it) should never leave a stat stuck
  // at 0 -- jump straight to the final value instead of animating.
  return reduceMotion ? endValue : value;
}
