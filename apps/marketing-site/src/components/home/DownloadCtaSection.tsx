"use client";

import styles from "./DownloadCtaSection.module.css";
import { SmartDownloadButton } from "@/components/SmartDownloadButton";

/**
 * Screen 32 section 7 -- "Download / Get Started CTA". Per the revised
 * hero-simplification update, this "reuses the same warm editorial
 * photography style as the Hero (a calm, resolved 'moved in' moment)
 * behind the App Store/Play Store badges, with the brand's logo mark
 * (static, at rest) placed above the headline as a simple closing brand
 * signature" (website-design-patterns.md) -- no illustration or animation
 * of any kind, matching the site's fully photography-led Cinematic 2D
 * approach.
 *
 * No separate "resolved moment" photograph has been generated yet, so
 * this reuses the Hero's own photograph under a heavier, fully dark scrim
 * (rather than the Hero's lighter top-only gradient) -- distinct enough
 * in treatment to read as its own moment rather than a repeat, while
 * staying within the same photography style per the docs.
 */
export function DownloadCtaSection() {
  return (
    <section className={styles.section} aria-labelledby="download-heading">
      {/* eslint-disable-next-line @next/next/no-img-element -- static export, no next/image optimizer available */}
      <img src="/hero-photo.webp" alt="" aria-hidden="true" className={styles.photo} />
      <div className={styles.scrim} aria-hidden="true" />

      <div className={styles.content}>
        {/* eslint-disable-next-line @next/next/no-img-element -- static export, no next/image optimizer available */}
        <img src="/logo.png" alt="De-Duke" className={styles.mark} />
        <h2 id="download-heading" className={styles.heading}>
          Your next home, verified from the start
        </h2>
        <p className={styles.body}>
          Download De-Duke to search verified listings, chat directly with hosts, and pay securely —
          all in one place.
        </p>
        <SmartDownloadButton />
      </div>
    </section>
  );
}
