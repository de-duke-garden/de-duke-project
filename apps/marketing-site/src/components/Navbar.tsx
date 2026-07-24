"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import styles from "./Navbar.module.css";
import { useScrolledPastHero } from "@/hooks/useScrolledPastHero";
import { CloseIcon, MenuIcon } from "./icons";

/** Sitewide nav -- links to Home, About/Product (FEAT-038), and legal
 * (FEAT-037) per screens.md's Marketing Website navigation requirements.
 *
 * `overPhoto` should be `true` only on the Home page, where the Navbar
 * starts transparent, floating over the Hero's dark-scrimmed photograph
 * with white text (+ a subtle text-shadow for legibility over lighter
 * parts of the image), then gains its solid background + hairline border
 * once the visitor scrolls roughly past the Hero.
 *
 * Every other page (About, and any future non-hero page) has no
 * photograph to float over, so the nav renders solid/opaque from the very
 * first frame instead of reusing that same scroll-triggered transition --
 * `useScrolledPastHero`'s threshold is calibrated to the Hero's height and
 * is otherwise meaningless on these pages, so gating solidity on it there
 * left the nav transparent (no background, no separating border/shadow)
 * while floating over ordinary page content for most of the scroll, only
 * turning solid past an arbitrary, unrelated scroll distance. */
export function Navbar({ overPhoto = false }: { overPhoto?: boolean }) {
  const scrolledPastHero = useScrolledPastHero();
  const solid = !overPhoto || scrolledPastHero;
  const lightText = overPhoto && !scrolledPastHero;
  const [menuOpen, setMenuOpen] = useState(false);

  // Lock body scroll while the mobile nav drawer is open, and let Escape
  // close it -- both are expected behaviors for an overlay nav on mobile.
  useEffect(() => {
    if (!menuOpen) return;
    const previousOverflow = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === "Escape") setMenuOpen(false);
    };
    window.addEventListener("keydown", onKeyDown);
    return () => {
      document.body.style.overflow = previousOverflow;
      window.removeEventListener("keydown", onKeyDown);
    };
  }, [menuOpen]);

  return (
    <nav
      className={`${styles.nav} ${solid ? styles.solid : ""} ${lightText ? styles.lightText : ""}`}
      aria-label="Main"
    >
      <Link href="/" className={styles.brand}>
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img
          src="/logo.png"
          alt=""
          width={28}
          height={28}
          aria-hidden="true"
          className={lightText ? styles.markLight : undefined}
        />
        De-Duke
      </Link>

      <div className={styles.links}>
        <Link href="/about">About</Link>
        <Link href="/legal/privacy-policy">Legal</Link>
      </div>

      <button
        type="button"
        className={`${styles.menuTrigger} ${lightText ? styles.menuTriggerLight : ""}`}
        aria-label="Open menu"
        aria-expanded={menuOpen}
        aria-controls="mobile-nav-panel"
        onClick={() => setMenuOpen(true)}
      >
        <MenuIcon className={styles.menuIcon} />
      </button>

      {/* Overlay + slide-in panel are always mounted (not conditionally
         rendered) so the open/close transitions can animate both ways --
         `.open` toggles opacity/transform, and `visibility`+
         `pointer-events` (rather than `display: none`) keep it out of the
         way and untabbable while closed without killing the transition. */}
      <div
        className={`${styles.overlay} ${menuOpen ? styles.overlayOpen : ""}`}
        onClick={() => setMenuOpen(false)}
        aria-hidden="true"
      />
      <div
        id="mobile-nav-panel"
        className={`${styles.panel} ${menuOpen ? styles.panelOpen : ""}`}
        role="dialog"
        aria-modal="true"
        aria-label="Main"
        inert={!menuOpen ? true : undefined}
      >
        <button
          type="button"
          className={styles.closeButton}
          aria-label="Close menu"
          onClick={() => setMenuOpen(false)}
        >
          <CloseIcon className={styles.menuIcon} />
        </button>
        <div className={styles.panelLinks}>
          <Link href="/about" onClick={() => setMenuOpen(false)}>
            About
          </Link>
          <Link href="/legal/privacy-policy" onClick={() => setMenuOpen(false)}>
            Legal
          </Link>
        </div>
      </div>
    </nav>
  );
}
