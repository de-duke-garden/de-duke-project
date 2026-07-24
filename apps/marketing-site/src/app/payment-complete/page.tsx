// Paystack Callback URL destination -- the page a user's BROWSER lands on
// after completing/cancelling checkout on Paystack's hosted payment page.
//
// On Android with the app installed, this page should rarely even render:
// apps/mobile/android/app/src/main/AndroidManifest.xml registers a
// verified App Link (autoVerify) for https://de-duke.com/payment-complete
// (backed by public/.well-known/assetlinks.json below), so Android
// intercepts the redirect before the browser loads this page at all and
// opens the app directly at go_router's '/payment-complete' route, which
// forwards straight into Transaction Detail. This page is the fallback
// for everyone else: iOS (no Universal Links configured yet -- see
// assetlinks.json's own comment), an unverified/first-run Android device,
// or a browser that doesn't honor App Links. The "Open the De-Duke app"
// link below covers that fallback case explicitly rather than leaving the
// user stranded on a page that can't act any further.
//
// Purely cosmetic beyond that: the mobile app never TRUSTS anything read
// from this redirect (it re-fetches the real transaction status from the
// backend once opened -- see
// apps/mobile/lib/features/checkout/screens/checkout_screen.dart, and, for
// the App-Links-driven open, the '/payment-complete' route in
// app_router.dart). Actual payment confirmation is Paystack's signed
// webhook hitting POST /v1/checkout/webhook, never this page or anything
// the client reports -- per architecture.md's Payment Correctness rule, a
// client-side "success" is never trusted on its own, so this page
// deliberately does NOT claim the payment succeeded, even when Paystack's
// own query params suggest it did.
//
// Static, zero backend dependency (this app has none, per
// architecture.md's Marketing Website component) -- reading `reference`/
// `trxref`/`transaction_id` from the URL is client-only decoration (lets
// the user visually confirm which booking this was, and builds the
// fallback deep link below), so this is a client component wrapped in
// Suspense per Next.js's useSearchParams requirement, not a
// server-rendered dynamic route.
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
  // Our OWN param (apps/backend/app/api/v1/checkout.py's initiate_checkout
  // builds this into the callback_url it sends Paystack) -- unlike
  // reference/trxref above, this is the exact id go_router's
  // '/payment-complete' route needs to land on the right Transaction
  // Detail screen, so the fallback link below carries it through
  // unchanged rather than relying on the app to resolve a reference.
  const transactionId = searchParams.get("transaction_id");
  const fallbackDeepLink = transactionId
    ? `https://de-duke.com/payment-complete?transaction_id=${encodeURIComponent(transactionId)}`
    : "https://de-duke.com/payment-complete";

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
          Return to the De-Duke app to see your booking and payment status — we confirm every
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
        {/* Only rendered at all on a device/browser where Android's
            verified App Link didn't already intercept this navigation
            before this page loaded (see this file's header comment) --
            re-issuing the SAME https URL as a plain link lets the OS
            retry App Link resolution (useful right after install, before
            verification finishes propagating) rather than just linking to
            an app store or doing nothing. */}
        <a
          href={fallbackDeepLink}
          style={{
            display: "inline-block",
            marginTop: "1.5rem",
            padding: "0.75rem 1.5rem",
            background: colors.primary,
            color: colors.surface,
            borderRadius: "999px",
            fontWeight: 600,
            fontSize: "0.9375rem",
            textDecoration: "none",
          }}
        >
          Open the De-Duke app
        </a>
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
