"use client";

import { useEffect, useRef } from "react";
import { gsap, ScrollTrigger } from "@/lib/gsapClient";
import styles from "./HeroSection.module.css";
import { SmartDownloadButton } from "@/components/SmartDownloadButton";

/** Resting scale applied to the photo at all times, before any Ken Burns
 * drift or mouse parallax is added. `object-fit: cover` fills the frame
 * with zero overflow margin, so without this the ±8px parallax translate
 * would expose the section's own background at the opposite edge; a 10%
 * overscale gives the photo comfortable overflow room (tens of px at any
 * realistic viewport width) well beyond the max translate + Ken Burns
 * drift combined, so no edge is ever exposed. */
const BASE_SCALE = 1.1;

/** Additional Ken Burns scale added on top of `BASE_SCALE`, reached once
 * the visitor has scrolled one full Hero-height, per website-design-
 * patterns.md's "1.0x -> 1.06x scale" (applied relative to the resting
 * frame, i.e. `BASE_SCALE` -> `BASE_SCALE + KEN_BURNS_MAX_SCALE`). */
const KEN_BURNS_MAX_SCALE = 0.06;

/** Max mouse-parallax translate offset in px, per website-design-
 * patterns.md's "subtle mouse-move parallax... max +-8px translate". */
const PARALLAX_MAX_OFFSET = 8;

/**
 * Screen 32's Hero -- "Welcome Home". Per the hero-simplification update
 * (revised) in `website-design-patterns.md`/`branding.md`, the house-
 * monogram "assembly" concept has been retired entirely (first a WebGL
 * scene, then an SVG illustration) in favor of the site's single,
 * simplest, most-reliable Cinematic 2D technique, used consistently
 * sitewide: a full-bleed editorial photograph with a Ken Burns drift and a
 * scroll-driven upward mask-wipe reveal into the Differentiators section.
 *
 * Scroll position across the section's own height (no pin needed -- this
 * section scrolls like any other, per the Main Animation Update's
 * `start: 'top top'` / `end: 'bottom top'`) drives both the Ken Burns
 * scale and a `clip-path` wipe that reveals the section's own background
 * (matching the next section's) from the bottom up. Mouse position drives
 * a subtle parallax translate on the photo. Headline reveals line-by-line
 * via GSAP on mount, per "Typography enters with intent."
 */
export function HeroSection({ reduceMotion }: { reduceMotion: boolean }) {
  const sectionRef = useRef<HTMLElement>(null);
  const contentRef = useRef<HTMLDivElement>(null);
  const maskRef = useRef<HTMLDivElement>(null);
  const photoRef = useRef<HTMLImageElement>(null);
  // Plain refs (not React state) for scroll progress and pointer position
  // -- both update up to 60x/second and only ever need to push a single
  // imperative `transform`/`clip-path` write, so routing them through
  // React state would force a render on every frame for no benefit.
  const progressRef = useRef(0);
  const pointerRef = useRef({ x: 0, y: 0 });

  // Combines the scroll-driven Ken Burns scale and the mouse-driven
  // parallax translate into one transform on the photo element.
  const applyPhotoTransform = () => {
    const photo = photoRef.current;
    if (!photo) return;
    const scale = BASE_SCALE + progressRef.current * KEN_BURNS_MAX_SCALE;
    const tx = pointerRef.current.x * PARALLAX_MAX_OFFSET;
    const ty = pointerRef.current.y * PARALLAX_MAX_OFFSET;
    photo.style.transform = `translate(${tx}px, ${ty}px) scale(${scale})`;
  };

  // Applies the resting `BASE_SCALE` on mount regardless of `reduceMotion`
  // -- the scroll/mousemove-driven effect below only ever adds *on top* of
  // this, so reduced-motion visitors still get the framing the overscan
  // margin depends on, just without any further drift/parallax.
  useEffect(() => {
    applyPhotoTransform();
  }, []);

  // Ken Burns drift + scroll-driven upward mask-wipe reveal, per
  // website-design-patterns.md's Main Animation Update (Hero section).
  useEffect(() => {
    if (reduceMotion) return;
    const section = sectionRef.current;
    const mask = maskRef.current;
    if (!section || !mask) return;

    const trigger = ScrollTrigger.create({
      trigger: section,
      start: "top top",
      end: "bottom top",
      scrub: true,
      onUpdate: (self) => {
        progressRef.current = self.progress;
        applyPhotoTransform();
        // Clips the photo/scrim layer from the bottom up, revealing the
        // section's own background (matching the Differentiators section
        // that follows) -- reads as the photo "wiping away" upward as the
        // visitor scrolls past the Hero.
        mask.style.clipPath = `inset(0 0 ${self.progress * 100}% 0)`;
      },
    });

    return () => trigger.kill();
  }, [reduceMotion]);

  // Headline/subhead/CTA entrance, timed to feel confident and unhurried
  // rather than firing instantly -- runs once on mount since the Hero is
  // always the first thing a visitor sees (no scroll needed to trigger it).
  useEffect(() => {
    const lines = contentRef.current?.querySelectorAll(`.${styles.headlineLine} span`);
    const tl = gsap.timeline({ defaults: { ease: "expo.out" }, delay: reduceMotion ? 0 : 0.2 });
    if (lines?.length) {
      tl.to(lines, { y: "0%", duration: reduceMotion ? 0 : 0.9, stagger: reduceMotion ? 0 : 0.12 });
    }
    tl.to(`.${styles.subhead}`, { opacity: 1, duration: reduceMotion ? 0 : 0.6 }, reduceMotion ? "<" : "-=0.4");
    tl.to(`.${styles.ctaRow}`, { opacity: 1, duration: reduceMotion ? 0 : 0.6 }, reduceMotion ? "<" : "-=0.4");
    return () => {
      tl.kill();
    };
  }, [reduceMotion]);

  // Subtle mouse parallax input for the photo layer (disabled with
  // reduced motion).
  useEffect(() => {
    if (reduceMotion) return;
    const handleMove = (event: MouseEvent) => {
      pointerRef.current = {
        x: (event.clientX / window.innerWidth) * 2 - 1,
        y: (event.clientY / window.innerHeight) * 2 - 1,
      };
      applyPhotoTransform();
    };
    window.addEventListener("mousemove", handleMove);
    return () => window.removeEventListener("mousemove", handleMove);
  }, [reduceMotion]);

  return (
    <section
      ref={sectionRef}
      className={styles.hero}
      aria-label="De-Duke — verified property, real conversations, deals that close"
    >
      <div ref={maskRef} className={styles.photoMask}>
        {/* eslint-disable-next-line @next/next/no-img-element -- static export, no next/image optimizer available */}
        <img
          ref={photoRef}
          src="/hero-photo.webp"
          alt=""
          aria-hidden="true"
          className={styles.photo}
          // Error state per screens.md: "Hero photograph fails to load ->
          // Falls back to a solid brand-color background with the headline
          // still legible." Hiding the broken image leaves `.hero`'s own
          // `--color-primary` background (with the same scrim/content on
          // top) doing exactly that, with no extra fallback markup needed.
          onError={(event) => {
            event.currentTarget.style.display = "none";
          }}
        />
      </div>

      <div className={styles.content} ref={contentRef}>
        <h1 className={styles.headline}>
          <span className={styles.headlineLine}>
            <span>Verified property.</span>
          </span>
          <span className={styles.headlineLine}>
            <span>Real conversations.</span>
          </span>
          <span className={styles.headlineLine}>
            <span>Deals that close.</span>
          </span>
        </h1>
        <p className={styles.subhead}>
          De-Duke gives Nigerians a trustworthy way to find and close real estate deals — sales,
          leases, and short-term rentals — at transparent, fixed prices, with every host verified
          from the start.
        </p>
        <div className={styles.ctaRow}>
          <SmartDownloadButton compact />
        </div>
      </div>
    </section>
  );
}
