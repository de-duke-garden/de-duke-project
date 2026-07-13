/**
 * screens.md Screen 18: Shareable Summary (External View) -- FEAT-020.
 *
 * Deliberately "Web (external, unauthenticated)": a non-app-user approver
 * (e.g. David's manager) opens this from a link forwarded out of the
 * mobile app's Screen 17, with no De-Duke session of their own. This route
 * is allowlisted in src/middleware.ts's PUBLIC_PATHS, and this page never
 * calls getAdminSession()/the authenticated /api/backend proxy -- it fetches
 * the public GET /v1/share/:token endpoint directly, server-side, so no
 * session cookie is ever required or read.
 *
 * The Root Layout (src/app/layout.tsx) already renders bare `{children}`
 * (no AdminNav/sidebar) whenever there's no session -- true here by
 * construction, since an external visitor never has one -- so this page's
 * own markup is the entire visible surface, no admin chrome to suppress.
 */

const BACKEND_API_URL = process.env.BACKEND_API_URL ?? "http://localhost:8000";

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
      // Screen 18 has no client-side state to preserve across requests --
      // always fetch fresh so a just-revoked link reflects immediately.
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
    <div className="flex min-h-screen flex-col bg-surface text-text-primary">
      {/* Minimal branded header -- logo only, no navigation, per screens.md's
          Layout section for this screen. */}
      <header className="border-b border-border px-lg py-md">
        <span className="font-heading text-lg font-semibold text-primary">De-Duke</span>
      </header>

      <main className="mx-auto w-full max-w-2xl flex-1 px-lg py-2xl">
        {result.kind === "error" && (
          <div className="rounded-lg border border-border bg-surface-secondary p-lg text-center">
            <p className="font-heading text-lg font-semibold">Something went wrong</p>
            <p className="mt-xs text-text-secondary">
              We couldn&apos;t load this summary right now.
            </p>
            <a
              href={`/s/${token}`}
              className="mt-md inline-block text-primary underline underline-offset-2"
            >
              Try again
            </a>
          </div>
        )}

        {result.kind === "unavailable" && (
          <div className="rounded-lg border border-border bg-surface-secondary p-lg text-center">
            <p className="font-heading text-lg font-semibold">{result.message}</p>
          </div>
        )}

        {result.kind === "ok" && (
          <SummaryPanel summary={result.summary} />
        )}
      </main>

      <footer className="border-t border-border px-lg py-md text-center text-sm text-text-secondary">
        Shared via De-Duke &middot;{" "}
        <a href="https://www.de-duke.com" className="text-primary underline underline-offset-2">
          Learn about De-Duke
        </a>
      </footer>
    </div>
  );
}

function SummaryPanel({ summary }: { summary: SharedListingSummary }) {
  return (
    <div className="overflow-hidden rounded-lg border border-border shadow-md">
      {summary.primary_image_url && (
        // External, unauthenticated page kept dependency-free of
        // next/image's loader config; a plain <img> is the simplest
        // correct choice here.
        // eslint-disable-next-line @next/next/no-img-element
        <img
          src={summary.primary_image_url}
          alt={summary.title}
          className="h-64 w-full object-cover"
        />
      )}
      <div className="space-y-md p-lg">
        {!summary.listing_is_active && (
          <div className="rounded-md border border-warning bg-warning/10 px-md py-sm text-sm text-warning">
            This listing is no longer active on De-Duke.
          </div>
        )}

        <div>
          <h1 className="font-heading text-xl font-semibold">{summary.title}</h1>
          <p className="mt-xs text-text-secondary">
            {summary.location_address_line}, {summary.location_city}, {summary.location_state}
          </p>
        </div>

        <p className="font-heading text-2xl font-semibold text-primary">
          {formatPrice(summary)}
        </p>

        <div className="flex items-center gap-xs text-sm">
          <span
            className={
              summary.verification_status === "verified"
                ? "text-success"
                : "text-text-secondary"
            }
          >
            {summary.verification_status === "verified" ? "✓ Verified" : "Unverified"}
          </span>
        </div>

        {summary.key_terms.length > 0 && (
          <div>
            <h2 className="font-heading text-sm font-semibold uppercase tracking-wide text-text-secondary">
              Key Terms
            </h2>
            <ul className="mt-xs list-inside list-disc text-text-primary">
              {summary.key_terms.map((term) => (
                <li key={term}>{term}</li>
              ))}
            </ul>
          </div>
        )}
      </div>
    </div>
  );
}
