import styles from "./DownloadCTA.module.css";
import { SmartDownloadButton } from "@/components/SmartDownloadButton";

/**
 * Screen 33's closing "Download CTA" -- deliberately matches the Home
 * page's Download CTA section (components/home/DownloadCtaSection.tsx)
 * design exactly: full-bleed editorial photograph, dark scrim, static
 * brand mark, heading, and the same platform-aware Smart Download Button
 * (FEAT-039), so the install moment reads identically wherever a visitor
 * hits it on the site. Breaks out of the About page's centered text
 * column to go full-bleed.
 */
export function DownloadCTA() {
  return (
    <div className={styles.breakout}>
      <section className={styles.section} aria-labelledby="about-download-heading">
        {/* eslint-disable-next-line @next/next/no-img-element -- static export, no next/image optimizer available */}
        <img src="/hero-photo.webp" alt="" aria-hidden="true" className={styles.photo} />
        <div className={styles.scrim} aria-hidden="true" />

        <div className={styles.content}>
          {/* eslint-disable-next-line @next/next/no-img-element -- static export, no next/image optimizer available */}
          <img src="/logo.png" alt="De-Duke" className={styles.mark} />
          <h2 id="about-download-heading" className={styles.heading}>
            Ready to see it for yourself?
          </h2>
          <p className={styles.body}>
            Download De-Duke to search verified listings, chat directly with hosts, and pay
            securely — all in one place.
          </p>
          <SmartDownloadButton />
        </div>
      </section>
    </div>
  );
}
