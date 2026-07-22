import Link from "next/link";

import { PropertyDetailClient } from "@/components/properties/PropertyDetailClient";

/** The property detail page other admin console screens (Disputes,
 * Moderation Queue, Release Funds, Conversations) deep-link a listing_id
 * into via each row's Listing/Property id -- see those screens' own
 * client components. */
export default async function PropertyDetailPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  return (
    <main className="p-lg">
      <Link href="/properties" className="text-sm text-text-secondary underline">
        &larr; Properties
      </Link>
      <div className="mt-sm">
        <PropertyDetailClient listingId={id} />
      </div>
    </main>
  );
}
