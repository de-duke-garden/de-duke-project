import { Suspense } from "react";

import { ReleaseFundsClient } from "@/components/release-funds/ReleaseFundsClient";

/** FEAT-043: Admin-Only Escrow Release. Lives under the (admin) route
 * group -- unlike commission-config (Staff read-only / Admin write), the
 * backend has no Staff-readable variant of this endpoint at all
 * (GET /v1/wallet/admin/releasable is require_roles(DEDUKE_ADMIN) only),
 * so this page itself is Admin-only, matching staff-management's pattern.
 */
export default function ReleaseFundsPage() {
  return (
    <main className="p-lg">
      <h1 className="font-heading text-xl font-semibold">Release Funds</h1>
      <p className="text-text-secondary">
        Paid transactions, filterable by whether they&apos;re still held in escrow
        or already released. Releasing credits the payee&apos;s Wallet -- confirm
        the necessary handover has taken place first. Released transactions
        stay visible here as a persisted log, not removed once acted on.
      </p>
      <div className="mt-lg">
        <Suspense fallback={null}>
          <ReleaseFundsClient />
        </Suspense>
      </div>
    </main>
  );
}
