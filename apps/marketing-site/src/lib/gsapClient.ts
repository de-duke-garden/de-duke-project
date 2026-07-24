"use client";

// Single shared GSAP + ScrollTrigger registration point. Previously each
// component/hook that used ScrollTrigger (HeroSection, PinnedStepSequence,
// useScrollReveal, useLenis) tracked its own local `registered` flag and
// called `gsap.registerPlugin(ScrollTrigger)` independently -- since
// module evaluation/effect order isn't guaranteed across those files,
// `ScrollTrigger.create()` could run before registration completed,
// throwing "_context is not a function" (ScrollTrigger's internal
// context() hook is only wired in by registerPlugin). Registering once
// here, at module load, and having every consumer import ScrollTrigger
// from this file instead of "gsap/ScrollTrigger" directly, removes the
// ordering hazard entirely.
import { gsap } from "gsap";
import { ScrollTrigger } from "gsap/ScrollTrigger";

gsap.registerPlugin(ScrollTrigger);

export { gsap, ScrollTrigger };
