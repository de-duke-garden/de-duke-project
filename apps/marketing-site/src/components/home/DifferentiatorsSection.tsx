"use client";

import { useRef } from "react";
import styles from "./DifferentiatorsSection.module.css";
import { useScrollReveal } from "@/hooks/useScrollReveal";
import { TagIcon, ShieldCheckIcon, ChatIcon } from "@/components/icons";

const PANELS = [
  {
    icon: TagIcon,
    title: "Fixed Price, No Haggling",
    body: "Every listing shows a transparent, fixed price from the start — no negotiation, no surprise mark-ups when you're ready to close.",
  },
  {
    icon: ShieldCheckIcon,
    title: "Verified Hosts",
    body: "Owners, agents, companies, lawyers, architects, and surveyors are each verified against a type-specific process before their listings go live.",
  },
  {
    icon: ChatIcon,
    title: "Real-Time Chat, On-Platform",
    body: "Talk directly with the host and De-Duke's own support team in one place — so nothing important happens off-platform, unrecorded.",
  },
];

/** Screen 32 section 2 -- "Differentiators". Three stacked panels revealed
 * via a calm scroll-enter fade/slide (per website-design-patterns.md,
 * this section deliberately skips WebGL: "keeps this section light"). */
export function DifferentiatorsSection({ reduceMotion }: { reduceMotion: boolean }) {
  const containerRef = useRef<HTMLDivElement>(null);
  useScrollReveal(containerRef, `.${styles.panel}`, { reduceMotion });

  return (
    <section className={styles.section} aria-labelledby="differentiators-heading">
      <h2 id="differentiators-heading" className={styles.heading}>
        Why trust De-Duke over the usual way
      </h2>
      <div className={styles.grid} ref={containerRef}>
        {PANELS.map(({ icon: Icon, title, body }) => (
          <div key={title} className={styles.panel} style={reduceMotion ? { opacity: 1, transform: "none" } : undefined}>
            <Icon className={styles.icon} />
            <h3 className={styles.panelTitle}>{title}</h3>
            <p className={styles.panelBody}>{body}</p>
          </div>
        ))}
      </div>
    </section>
  );
}
