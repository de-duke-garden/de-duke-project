"use client";

import { useEffect, useRef, useState } from "react";
import { ScrollTrigger } from "@/lib/gsapClient";
import styles from "./PinnedStepSequence.module.css";

export interface Step {
  title: string;
  body: string;
}

/**
 * Screen 32's "Pinned Step Sequence" custom component -- reused for both
 * the Guest and Host "How It Works" paths (website-design-patterns.md:
 * "differing only in step content and a secondary accent color for the
 * Host path"). A thin progress line fills and the active step highlights
 * as the visitor scrolls through the section.
 *
 * Implementation note: uses a scroll-scrubbed progress readout to drive
 * the active step rather than a true `position: sticky`/GSAP `pin` --
 * simpler and layout-safe while still satisfying the described behavior
 * ("Progress indicator... fills as user scrolls through the pinned
 * section"); swap in true pinning later if the design calls for a more
 * literal held-in-place illustration.
 */
export function PinnedStepSequence({
  heading,
  steps,
  accentColor,
  reduceMotion,
  illustrationSrc,
  illustrationAlt,
}: {
  heading: string;
  steps: Step[];
  accentColor: string;
  reduceMotion: boolean;
  /** Editorial photo shown behind the current step's label -- per
   * website-design-patterns.md's Asset Inventory ("editorial photography
   * -- guest/host/agency lifestyle shots"). Optional: falls back to the
   * plain label-only panel when not provided. */
  illustrationSrc?: string;
  illustrationAlt?: string;
}) {
  const sectionRef = useRef<HTMLElement>(null);
  const trackRef = useRef<HTMLDivElement>(null);
  const [activeIndex, setActiveIndex] = useState(0);
  const [fillPercent, setFillPercent] = useState(0);
  // With reduced motion, render the fully-progressed state directly rather
  // than syncing state to match via an effect.
  const displayFillPercent = reduceMotion ? 100 : fillPercent;
  const displayActiveIndex = reduceMotion ? steps.length - 1 : activeIndex;

  useEffect(() => {
    if (reduceMotion) return;
    const section = sectionRef.current;
    if (!section) return;

    const trigger = ScrollTrigger.create({
      trigger: section,
      start: "top 60%",
      end: "bottom 40%",
      scrub: 0.3,
      onUpdate: (self) => {
        const progress = self.progress;
        setFillPercent(progress * 100);
        setActiveIndex(Math.min(steps.length - 1, Math.floor(progress * steps.length)));
      },
    });

    return () => trigger.kill();
  }, [reduceMotion, steps.length]);

  return (
    <section
      ref={sectionRef}
      className={styles.section}
      style={{ ["--accent-color" as string]: accentColor }}
      aria-labelledby={`${heading.replace(/\s+/g, "-").toLowerCase()}-heading`}
    >
      <h2 id={`${heading.replace(/\s+/g, "-").toLowerCase()}-heading`} className={styles.heading}>
        {heading}
      </h2>
      <div className={styles.layout}>
        <div className={styles.progressTrack} ref={trackRef}>
          <div className={styles.progressLine} />
          <div className={styles.progressFill} style={{ height: `${displayFillPercent}%` }} />
          {steps.map((step, index) => (
            <div className={styles.step} key={step.title}>
              <div className={`${styles.dot} ${index <= displayActiveIndex ? styles.dotActive : ""}`}>
                {index + 1}
              </div>
              <div>
                <p className={styles.stepTitle}>{step.title}</p>
                <p className={styles.stepBody}>{step.body}</p>
              </div>
            </div>
          ))}
        </div>
        <div className={styles.illustration}>
          {illustrationSrc ? (
            <>
              {/* eslint-disable-next-line @next/next/no-img-element -- static export, no next/image optimizer available */}
              <img src={illustrationSrc} alt={illustrationAlt ?? ""} className={styles.illustrationPhoto} />
              <p className={`${styles.illustrationLabel} ${styles.illustrationLabelOnPhoto}`}>
                {steps[displayActiveIndex]?.title}
              </p>
            </>
          ) : (
            <p className={styles.illustrationLabel}>{steps[displayActiveIndex]?.title}</p>
          )}
        </div>
      </div>
    </section>
  );
}
