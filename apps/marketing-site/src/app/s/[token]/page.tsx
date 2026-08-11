// Screen 18 -- Shareable Summary (External View), FEAT-020.
//
// Deliberately "Web (external, unauthenticated)": a non-app-user approver
// (e.g. a manager reviewing a property forwarded from the mobile app) opens
// this from a link with no De-Duke session.
//
// Server component: fetches the public GET /v1/share/:token endpoint
// server-side, so no session cookie is ever required or read and the token
// is never exposed to client JS beyond the URL itself. This dynamic route
// is why the marketing site dropped output: "export" (see next.config.ts) --
// it renders on Vercel as a server function while every other page stays
// static.
//
// No marketing chrome (Navbar/Footer): this is a focused summary view for a
// visitor who arrived from a share link, not a browsing session. Styled with
// the site's design tokens so it still reads as De-Duke.

import type { Metadata } from "next";
import styles from "./page.module.css";

export const metadata: Metadata = {
  title: "Shared Property - De-Duke",
  description: "A property shared from De-Duke.",
};

const BACKEND_API_URL = process.env.BACKEND_API_URL ?? "https://api.de-duke.com";

type SharedListingSummary = {
  listing_id: string;
  title: string;
  listing_type: string;
  location_city: string;
  location_state: string;
  location_address_line: string;
  price: number;
  price_label: string;
  key_terms: string[];
  verification_status: string;
  primary_image_url: string | null;
  listing_is_active: boolean;
};

type ShareStatus = {
  status: "revoked" | "expired" | "not_found";
  message: string;
};

type FetchResult =
  | { kind: "ok"; summary: SharedListingSummary }
  | { kind: "unavailable"; message: string }
  | { kind: "error" };

async function fetchSharedSummary(token: string): Promise<FetchResult> {
  let response: Response;
  try {
    response = await fetch(`${BACKEND_API_URL}/v1/share/${token}`, {
      // Always fetch fresh so a just-revoked link reflects immediately.
      cache: "no-store",
    });
  } catch {
    return { kind: "error" };
  }
  if (!response.ok) {
    return { kind: "error" };
  }
  const body = (await response.json()) as SharedListingSummary | ShareStatus;
  if ("status" in body) {
    return { kind: "unavailable", message: body.message };
  }
  return { kind: "ok", summary: body };
}

function formatPrice(summary: SharedListingSummary): string {
  const amount = new Intl.NumberFormat("en-NG", {
    style: "currency",
    currency: "NGN",
    maximumFractionDigits: 0,
  }).format(summary.price);
  return summary.price_label ? `${amount} (${summary.price_label})` : amount;
}

export default async function SharedListingSummaryPage({
  params,
}: {
  params: Promise<{ token: string }>;
}) {
  const { token } = await params;
  const result = await fetchSharedSummary(token);

  return (
    <main className={styles.page}>
      <header className={styles.header}>
        <img src="/logo.png" alt="De-Duke" className={styles.logo} />
      </header>

      <section className={styles.card}>
        {result.kind === "error" && (
          <div className={styles.center}>
            <h1>Something went wrong</h1>
            <p>We couldn&apos;t load this summary right now.</p>
            <a href={`/s/${token}`} className={styles.link}>
              Try again
            </a>
          </div>
        )}

        {result.kind === "unavailable" && (
          <div className={styles.center}>
            <h1>{result.message}</h1>
          </div>
        )}

        {result.kind === "ok" && <SummaryPanel summary={result.summary} />}
      </section>

      <footer className={styles.footer}>
        Shared via De-Duke &middot;{" "}
        <a href="https://www.de-duke.com" className={styles.link}>
          Learn about De-Duke
        </a>
      </footer>
    </main>
  );
}

function SummaryPanel({ summary }: { summary: SharedListingSummary }) {
  return (
    <article>
      {summary.primary_image_url && (
        // External, unauthenticated page kept dependency-free of
        // next/image's loader config; a plain <img> is the simplest
        // correct choice here.
        // eslint-disable-next-line @next/next/no-img-element
        <img src={summary.primary_image_url} alt={summary.title} className={styles.image} />
      )}
      <div className={styles.content}>
        {!summary.listing_is_active && (
          <p className={styles.inactive}>This listing is no longer active on De-Duke.</p>
        )}

        <h1>{summary.title}</h1>
        <p className={styles.muted}>
          {summary.location_address_line}, {summary.location_city}, {summary.location_state}
        </p>

        <p className={styles.price}>{formatPrice(summary)}</p>

        <p className={styles.verification}>
          {summary.verification_status === "verified" ? "✓ Verified" : "Unverified"}
        </p>

        {summary.key_terms.length > 0 && (
          <div className={styles.terms}>
            <h2>Key Terms</h2>
            <ul>
              {summary.key_terms.map((term) => (
                <li key={term}>{term}</li>
              ))}
            </ul>
          </div>
        )}
      </div>
    </article>
  );
}
