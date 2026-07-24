"use client";

import { useRef } from "react";
import styles from "./ForAgenciesSection.module.css";
import { useScrollReveal } from "@/hooks/useScrollReveal";

/**
 * Screen 32 section 5 — "For Agencies". Speaks directly to Ngozi-type
 * visitors. Uses the AI-generated editorial photograph from
 * website-design-patterns.md's Asset Generation Prompt 3 (agency
 * lifestyle photography), with a subtle Ken Burns drift (1.0x to 1.08x on
 * hover/enter) per the documented motion strategy.
 */
export function ForAgenciesSection({ reduceMotion }: { reduceMotion: boolean }) {
  const containerRef = useRef<HTMLDivElement>(null);
  useScrollReveal(containerRef, `.${styles.copy} > *`, { reduceMotion, stagger: 0.06 });

  return (
    <section className={styles.section} aria-labelledby="agencies-heading">
      <div className={styles.photo}>
        {/* eslint-disable-next-line @next/next/no-img-element -- static export, no next/image optimizer available */}
        <img
          src="/agency-workspace.webp"
          alt="An agent showing a client a property tour on a tablet outside a verified listing"
          className={styles.photoImage}
        />
      </div>
      <div className={styles.copy} ref={containerRef}>
        <p className={styles.eyebrow}>For Agencies</p>
        <h2 id="agencies-heading" className={styles.heading}>
          Built for teams managing real volume
        </h2>
        <p className={styles.body}>
          Verify once as an Agency, then list every managed property at a fixed price with your
          team visible in every conversation. As your listing volume grows, De-Duke is building the
          coordination and portfolio tools agencies like yours actually need.
        </p>
        <ul className={styles.list}>
          <li>Agency-level verification covering every listing you manage</li>
          <li>Real-time chat with De-Duke staff visible on every listing conversation</li>
          <li>The same transparent, fixed-price model across your whole portfolio</li>
        </ul>
      </div>
    </section>
  );
}
