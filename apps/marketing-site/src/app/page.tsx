"use client";

// Screen 32 -- Marketing: Home (Hero -> Download CTA). FEAT-036's full
// cinematic build-out, assembled from the sequential per-section
// components in src/components/home/ (Hero, Differentiators, How It
// Works x2, For Agencies, Trust Signals, Download CTA), sharing a single
// Lenis smooth-scroll instance and GSAP ScrollTrigger context, per
// website-design-patterns.md's single-render-loop/single-scene rule.
import { Navbar } from "@/components/Navbar";
import { Footer } from "@/components/Footer";
import { Preloader } from "@/components/home/Preloader";
import { HeroSection } from "@/components/home/HeroSection";
import { DifferentiatorsSection } from "@/components/home/DifferentiatorsSection";
import { HowItWorksSection } from "@/components/home/HowItWorksSection";
import { ForAgenciesSection } from "@/components/home/ForAgenciesSection";
import { TrustSignalsSection } from "@/components/home/TrustSignalsSection";
import { DownloadCtaSection } from "@/components/home/DownloadCtaSection";
import { usePrefersReducedMotion } from "@/hooks/usePrefersReducedMotion";
import { useLenis } from "@/hooks/useLenis";

export default function HomePage() {
  const reduceMotion = usePrefersReducedMotion();

  // Lenis smooth scroll is scoped to this page only (marketing sections) --
  // /about and /legal/* never call this hook, per the Global Motion
  // Elements' "native browser scroll on Legal & Policy pages" rule.
  useLenis(!reduceMotion);

  return (
    <>
      <Preloader />
      <Navbar overPhoto />
      <main>
        <HeroSection reduceMotion={reduceMotion} />
        <DifferentiatorsSection reduceMotion={reduceMotion} />
        <HowItWorksSection reduceMotion={reduceMotion} />
        <ForAgenciesSection reduceMotion={reduceMotion} />
        <TrustSignalsSection reduceMotion={reduceMotion} />
        <DownloadCtaSection />
      </main>
      <Footer />
    </>
  );
}
