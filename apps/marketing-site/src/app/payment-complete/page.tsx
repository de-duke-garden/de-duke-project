// Paystack Callback URL destination -- the page a user's BROWSER lands on
// after completing/cancelling checkout on Paystack's hosted payment page.
// Purely cosmetic: the mobile app never reads anything from this redirect
// (it opens Paystack's authorization_url in an external browser and
// detects return via AppLifecycleState.resumed, then re-fetches the real
// transaction status from the backend -- see
// apps/mobile/lib/features/checkout/screens/checkout_screen.dart). Actual
// payment confirmation is Paystack's signed webhook hitting
// POST /v1/checkout/webhook, never this page or anything the client
// reports -- per architecture.md's Payment Correctness rule, a client-side
// "success" is never trusted on its own, so this page deliberately does
// NOT claim the payment succeeded, even when Paystack's own query params
// suggest it did.
//
// Static, zero backend dependency (this app has none, per
// architecture.md's Marketing Website component) -- reading `reference`/
// `trxref` from the URL is client-only decoration (lets the user visually
// confirm which booking this was, nothing more), so this is a client
// component wrapped in Suspense per Next.js's useSearchParams
// requirement, not a server-rendered dynamic route.
"use client";

import { Suspense } from "react";
import { useSearchParams } from "next/navigation";

const colors = {
  primary: "#0D6B2D",
  surface: "#FFFFFF",
  surfaceSecondary: "#F4F6F5",
  textPrimary: "#12201C",
  textSecondary: "#5F6E68",
  border: "#E1E6E3",
};

function CheckmarkIcon() {
  return (
    <svg width="56" height="56" viewBox="0 0 56 56" fill="none" aria-hidden="true">
      <circle cx="28" cy="28" r="28" fill={colors.primary} opacity="0.12" />
      <path
        d="M18 29.5L24.5 36L38 21"
        stroke={colors.primary}
        strokeWidth="3"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  );
}

function PaymentCompleteContent() {
  // Paystack appends `reference`/`trxref` to whatever Callback URL is
  // configured on the account, regardless of whether the payment actually
  // succeeded -- shown here only as a visual anchor ("this is the booking
  // you were paying for"), never as a claim about payment outcome.
  const searchParams = useSearchParams();
  const reference = searchParams.get("reference") ?? searchParams.get("trxref");

  return (
    <main
      style={{
        minHeight: "100dvh",
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        padding: "2rem",
        background: colors.surfaceSecondary,
        fontFamily: "Inter, sans-serif",
      }}
    >
      <div
        style={{
          maxWidth: "420px",
          width: "100%",
          background: colors.surface,
          border: `1px solid ${colors.border}`,
          borderRadius: "16px",
          padding: "2.5rem 2rem",
          textAlign: "center",
        }}
      >
        <CheckmarkIcon />
        <h1
          style={{
            fontFamily: "Manrope, sans-serif",
            fontSize: "1.375rem",
            fontWeight: 700,
            color: colors.textPrimary,
            margin: "1.25rem 0 0.5rem",
          }}
        >
          You&apos;re all done here
        </h1>
        <p style={{ color: colors.textSecondary, fontSize: "0.9375rem", lineHeight: 1.5, margin: 0 }}>
          Return to the De-Duke app to see your booking and payment status -- we confirm every
          payment directly with Paystack, so the app always shows the real, up-to-date result even
          if this page closes before it loads.
        </p>
        {reference && (
          <p
            style={{
              color: colors.textSecondary,
              fontSize: "0.8125rem",
              fontFamily: "monospace",
              marginTop: "1.25rem",
              wordBreak: "break-all",
            }}
          >
            Reference: {reference}
          </p>
        )}
        <p style={{ color: colors.textSecondary, fontSize: "0.8125rem", marginTop: "1.5rem" }}>
          You can safely close this window now.
        </p>
      </div>
    </main>
  );
}

export default function PaymentCompletePage() {
  return (
    <Suspense fallback={null}>
      <PaymentCompleteContent />
    </Suspense>
  );
}
