"use client";

import { useState } from "react";
import styles from "./SmartDownloadButton.module.css";
import { APP_STORE_URL, PLAY_STORE_URL, storeUrlFor } from "@/lib/platform";
import { useDetectedPlatform } from "@/hooks/useDetectedPlatform";

const QR_SIZE = 96;

function qrSrcFor(url: string): string {
  return `https://api.qrserver.com/v1/create-qr-code/?size=${QR_SIZE * 2}x${QR_SIZE * 2}&data=${encodeURIComponent(url)}`;
}

/**
 * FEAT-039: Smart Download Button. iOS/Android visitors get a single CTA
 * that routes straight to their store listing; desktop visitors get a QR
 * code (scan-to-download) plus both store badges as a fallback, per
 * FEAT-039's acceptance criteria ("Redirect logic fails gracefully (shows
 * both store badges) if platform detection is inconclusive").
 *
 * Desktop's QR fallback shows one code per store, each clearly labeled --
 * a single QR pointed at one store's URL would silently fail for visitors
 * on the other platform, so App Store and Google Play get their own code
 * and their own caption rather than sharing one.
 *
 * Shared between the Hero and Download CTA sections (Screen 32's "Smart
 * Download Button" custom component).
 */
export function SmartDownloadButton({ compact = false }: { compact?: boolean }) {
  // "desktop" (both badges, no QR) during SSR/first paint -- the safest,
  // most-functional default before client-side UA detection resolves,
  // matching FEAT-039's "fails gracefully" requirement.
  const platform = useDetectedPlatform();
  const [appStoreQrFailed, setAppStoreQrFailed] = useState(false);
  const [playStoreQrFailed, setPlayStoreQrFailed] = useState(false);

  const primaryUrl = storeUrlFor(platform);
  const isDesktop = platform === "desktop";

  return (
    <div className={styles.wrap}>
      <div className={styles.badgeRow}>
        {primaryUrl ? (
          <a href={primaryUrl} className={styles.storeBadge} data-testid="smart-download-primary">
            {platform === "ios" ? "Download on the App Store" : "Get it on Google Play"}
          </a>
        ) : (
          <>
            <a href={APP_STORE_URL} className={styles.storeBadge}>
              Download on the App Store
            </a>
            <a href={PLAY_STORE_URL} className={styles.storeBadge}>
              Get it on Google Play
            </a>
          </>
        )}
      </div>

      {!compact && (
        <div className={`${styles.qrWrap} ${isDesktop ? styles.visible : ""}`}>
          <p className={styles.qrHeading}>Or scan to download</p>
          <div className={styles.qrGrid}>
            <div className={styles.qrCard}>
              {!appStoreQrFailed && (
                // eslint-disable-next-line @next/next/no-img-element -- external QR service, not an optimizable local asset
                <img
                  src={qrSrcFor(APP_STORE_URL)}
                  alt="QR code to download De-Duke on the App Store"
                  width={QR_SIZE}
                  height={QR_SIZE}
                  onError={() => setAppStoreQrFailed(true)}
                />
              )}
              <p className={styles.qrCaption}>
                <span className={styles.qrLabel}>iOS</span>
                Scan for the App Store
              </p>
            </div>
            <div className={styles.qrDivider} aria-hidden="true" />
            <div className={styles.qrCard}>
              {!playStoreQrFailed && (
                // eslint-disable-next-line @next/next/no-img-element -- external QR service, not an optimizable local asset
                <img
                  src={qrSrcFor(PLAY_STORE_URL)}
                  alt="QR code to download De-Duke on Google Play"
                  width={QR_SIZE}
                  height={QR_SIZE}
                  onError={() => setPlayStoreQrFailed(true)}
                />
              )}
              <p className={styles.qrCaption}>
                <span className={styles.qrLabel}>Android</span>
                Scan for Google Play
              </p>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
