"use client";

import { PinnedStepSequence } from "./PinnedStepSequence";

// Step content matches the real product flows in user_flow.md Flow 1
// (Guest) and Flow 2 (Host) exactly, per FEAT-036's acceptance criteria:
// "each reflecting the actual current product flows."

const GUEST_STEPS = [
  {
    title: "Search",
    body: "Find verified listings near you with fixed, transparent pricing — no scrolling through the same handful of duplicate posts.",
  },
  {
    title: "Chat",
    body: "Message the host and De-Duke's own support team, together in one thread, before you commit.",
  },
  {
    title: "Confirm & Hold",
    body: "Reserve the listing at its fixed price — a 15-minute hold keeps it yours while you complete payment.",
  },
  {
    title: "Pay",
    body: "Check out securely, get an instant confirmation, and receive an emailed receipt for your records.",
  },
];

const HOST_STEPS = [
  {
    title: "Choose Host Type",
    body: "Owner, Agent, Company, Lawyer, Architect, or Surveyor — each with its own verification process built around how that host actually operates.",
  },
  {
    title: "Submit Documents",
    body: "Upload the specific documents your host type requires, once.",
  },
  {
    title: "Get Verified",
    body: "Owner-type listings get a quick staff review before going live; professionally-verified types unlock faster.",
  },
  {
    title: "List & Get Paid",
    body: "Publish at your fixed price, chat directly with interested guests, and get paid out to your wallet once De-Duke releases funds.",
  },
];

/** Screen 32 sections 3 & 4 — "How It Works" Guest and Host paths. */
export function HowItWorksSection({ reduceMotion }: { reduceMotion: boolean }) {
  return (
    <>
      <PinnedStepSequence
        heading="How It Works — For Guests"
        steps={GUEST_STEPS}
        accentColor="#0D6B2D"
        reduceMotion={reduceMotion}
        illustrationSrc="/guest-lifestyle.webp"
        illustrationAlt="A guest reviewing a listing on her phone"
      />
      <PinnedStepSequence
        heading="How It Works — For Hosts"
        steps={HOST_STEPS}
        accentColor="#D98E04"
        reduceMotion={reduceMotion}
        illustrationSrc="/agency-lifestyle.webp"
        illustrationAlt="A host standing in front of his verified property"
      />
    </>
  );
}
