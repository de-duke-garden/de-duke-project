import { PropertiesClient } from "@/components/properties/PropertiesClient";

/** The property catalog -- search, filter, and paginate every listing on
 * the platform. Staff/Admin (both roles; GET /v1/listings is
 * require_roles(DEDUKE_STAFF, DEDUKE_ADMIN)). Each row links to
 * `/properties/:id`, the context hub other screens (Disputes, Moderation
 * Queue, Release Funds, Conversations) deep-link a listing_id into.
 */
export default function PropertiesPage() {
  return (
    <main className="p-lg">
      <h1 className="font-heading text-xl font-semibold">Properties</h1>
      <p className="text-text-secondary">
        Browse every property on the platform. Open one to see its full detail plus related
        disputes, moderation history, conversations, and transactions.
      </p>
      <div className="mt-lg">
        <PropertiesClient />
      </div>
    </main>
  );
}
