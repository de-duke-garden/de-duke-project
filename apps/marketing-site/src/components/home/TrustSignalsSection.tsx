"use client";

import { useRef } from "react";
import styles from "./TrustSignalsSection.module.css";
import { useCountUp } from "@/hooks/useCountUp";
import { useScrollReveal } from "@/hooks/useScrollReveal";

// Placeholder trust-signal figures -- this site has zero backend
// dependency (per architecture.md), so these are not live API-backed
// numbers. Marketing/growth owns keeping these accurate as real numbers
// come in post-launch; kept as one small, easily-edited array rather than
// scattered through JSX so an update is a one-line content change.
const STATS = [
  { value: 6, suffix: "", label: "Host verification types supported" },
  { value: 2, suffix: "", label: "Listing types — Commercial & Shortlet" },
  { value: 100, suffix: "%", label: "Fixed-price listings, no negotiation" },
];

const TESTIMONIALS = [
  {
    quote: "“Knowing every host is verified before I even message them changes how I search.”",
    attribution: "Early guest tester, Lagos",
  },
  {
    quote: "“Listing at a fixed price and chatting with buyers in one place saved me the back-and-forth.”",
    attribution: "Early host tester, Abuja",
  },
  {
    quote: "“Having De-Duke staff visible in the thread makes disputes feel less risky for everyone.”",
    attribution: "Early agency tester, Port Harcourt",
  },
];

function StatCounter({
  value,
  suffix,
  label,
  reduceMotion,
}: {
  value: number;
  suffix: string;
  label: string;
  reduceMotion: boolean;
}) {
  const ref = useRef<HTMLDivElement>(null);
  const animated = useCountUp(ref, value, { reduceMotion });
  return (
    <div className={styles.stat} ref={ref}>
      <div className={styles.statValue}>
        {animated}
        {suffix}
      </div>
      <div className={styles.statLabel}>{label}</div>
    </div>
  );
}

/** Screen 32 section 6 -- "Trust Signals / Social Proof". */
export function TrustSignalsSection({ reduceMotion }: { reduceMotion: boolean }) {
  const containerRef = useRef<HTMLDivElement>(null);
  useScrollReveal(containerRef, `.${styles.card}`, { reduceMotion });

  return (
    <section className={styles.section} aria-labelledby="trust-heading">
      <h2 id="trust-heading" className={styles.heading}>
        Built on verification, not vibes
      </h2>
      <div className={styles.stats}>
        {STATS.map((stat) => (
          <StatCounter key={stat.label} {...stat} reduceMotion={reduceMotion} />
        ))}
      </div>
      <div className={styles.testimonials} ref={containerRef}>
        {TESTIMONIALS.map((testimonial) => (
          <div
            className={styles.card}
            key={testimonial.attribution}
            style={reduceMotion ? { opacity: 1, transform: "none" } : undefined}
          >
            <p className={styles.quote}>{testimonial.quote}</p>
            <p className={styles.attribution}>{testimonial.attribution}</p>
          </div>
        ))}
      </div>
    </section>
  );
}
