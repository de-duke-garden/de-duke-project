"use client";

import { useEffect, useState } from "react";
import styles from "./Preloader.module.css";

/**
 * "A simple, understated fade-in of the De-Duke wordmark/logo mark
 * (static, no draw-on animation) over the brand green while initial hero
 * photography loads; resolves directly into the Hero's first frame so the
 * preloader feels like a brief, calm pause rather than a separate loading
 * screen." (website-design-patterns.md Global Motion Elements --
 * Preloader, revised hero-simplification update.) Held for a short
 * minimum duration so it never flashes on a fast connection, and
 * force-hidden well before the performance budget's asset-preload target
 * regardless.
 */
export function Preloader() {
  const [hidden, setHidden] = useState(false);

  useEffect(() => {
    const timer = setTimeout(() => setHidden(true), 500);
    return () => clearTimeout(timer);
  }, []);

  return (
    <div className={`${styles.preloader} ${hidden ? styles.hidden : ""}`} aria-hidden={hidden}>
      {/* eslint-disable-next-line @next/next/no-img-element -- static export, no next/image optimizer available */}
      <img src="/logo.png" alt="" className={styles.mark} />
    </div>
  );
}
