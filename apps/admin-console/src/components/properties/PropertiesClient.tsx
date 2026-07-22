"use client";

import { useCallback, useEffect, useState } from "react";
import Link from "next/link";

import { StatusBadge } from "@/components/ui/StatusBadge";
import { TableSkeleton } from "@/components/ui/Skeleton";
import {
  LISTING_STATUS_FILTERS,
  LISTING_STATUS_TONE,
  LISTING_TYPE_FILTERS,
} from "./types";
import type { ListingListResponse, ListingSummary } from "./types";

const API_BASE_URL = "/api/backend/v1";

type LoadState = "loading" | "loaded" | "empty" | "error";

async function fetchListings(params: {
  search: string;
  statusFilter: string;
  typeFilter: string;
  cursor: string | null;
}): Promise<ListingListResponse> {
  const query = new URLSearchParams();
  if (params.search.trim()) query.set("search", params.search.trim());
  if (params.statusFilter) query.set("status_filter", params.statusFilter);
  if (params.typeFilter) query.set("listing_type", params.typeFilter);
  if (params.cursor) query.set("cursor", params.cursor);
  query.set("limit", "24");

  const response = await fetch(`${API_BASE_URL}/listings?${query.toString()}`);
  if (!response.ok) {
    throw new Error(`Failed to load properties (${response.status})`);
  }
  return response.json();
}

/** The `/properties` list -- search, status/type filters, and cursor
 * ("Load more") pagination against GET /v1/listings, staff/admin-only.
 * Deliberately NOT an unbounded/offset-paginated query (AGENTS.md) --
 * every property in the catalog stays reachable without the query cost
 * scaling with how far a staff member has paged.
 *
 * Each card links to `/properties/:id` -- the context hub other admin
 * console screens (Disputes, Moderation Queue, Release Funds,
 * Conversations) deep-link into via a listing's id, per that page's own
 * docstring.
 */
export function PropertiesClient() {
  const [search, setSearch] = useState("");
  const [statusFilter, setStatusFilter] = useState("");
  const [typeFilter, setTypeFilter] = useState("");

  const [state, setState] = useState<LoadState>("loading");
  const [items, setItems] = useState<ListingSummary[]>([]);
  const [cursor, setCursor] = useState<string | null>(null);
  const [loadingMore, setLoadingMore] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  const load = useCallback(async () => {
    setState("loading");
    try {
      const data = await fetchListings({ search, statusFilter, typeFilter, cursor: null });
      setItems(data.items);
      setCursor(data.next_cursor);
      setState(data.items.length === 0 ? "empty" : "loaded");
    } catch (e) {
      setErrorMessage(e instanceof Error ? e.message : "Something went wrong.");
      setState("error");
    }
  }, [search, statusFilter, typeFilter]);

  // Debounced search -- avoids firing a request on every keystroke while
  // typing into the search field; filter pill changes below trigger `load`
  // immediately via the same effect since they change one of its deps.
  useEffect(() => {
    const timeout = setTimeout(() => void load(), 300);
    return () => clearTimeout(timeout);
  }, [load]);

  async function handleLoadMore() {
    if (!cursor) return;
    setLoadingMore(true);
    try {
      const data = await fetchListings({ search, statusFilter, typeFilter, cursor });
      setItems((prev) => [...prev, ...data.items]);
      setCursor(data.next_cursor);
    } catch (e) {
      setErrorMessage(e instanceof Error ? e.message : "Something went wrong.");
    } finally {
      setLoadingMore(false);
    }
  }

  return (
    <>
      <div className="flex flex-wrap items-center gap-sm">
        <input
          type="text"
          placeholder="Search by title, address, city, or state"
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          className="w-full max-w-sm rounded-md border border-border bg-transparent p-sm text-sm"
        />
        <select
          value={statusFilter}
          onChange={(e) => setStatusFilter(e.target.value)}
          className="rounded-md border border-border bg-transparent p-sm text-sm"
        >
          {LISTING_STATUS_FILTERS.map((f) => (
            <option key={f.value} value={f.value}>
              {f.label}
            </option>
          ))}
        </select>
        <select
          value={typeFilter}
          onChange={(e) => setTypeFilter(e.target.value)}
          className="rounded-md border border-border bg-transparent p-sm text-sm"
        >
          {LISTING_TYPE_FILTERS.map((f) => (
            <option key={f.value} value={f.value}>
              {f.label}
            </option>
          ))}
        </select>
      </div>

      <div className="mt-md">
        {state === "loading" && <TableSkeleton rows={6} columns={4} />}

        {state === "error" && (
          <div className="rounded-md border border-error p-md">
            <p className="text-error">{errorMessage}</p>
            <button
              type="button"
              className="mt-sm rounded-md border border-border px-md py-sm text-sm"
              onClick={() => void load()}
            >
              Retry
            </button>
          </div>
        )}

        {state === "empty" && (
          <p className="text-text-secondary">No properties match these filters.</p>
        )}

        {state === "loaded" && (
          <>
            <div className="grid grid-cols-1 gap-md sm:grid-cols-2 lg:grid-cols-3">
              {items.map((item) => (
                <Link
                  key={item.id}
                  href={`/properties/${item.id}`}
                  className="rounded-lg border border-border p-md transition-colors duration-150 ease-out-smooth hover:bg-surface-secondary dark:border-border-dark dark:hover:bg-surface-secondary-dark"
                >
                  {item.primary_image_url && (
                    // eslint-disable-next-line @next/next/no-img-element
                    <img
                      src={item.primary_image_url}
                      alt=""
                      className="mb-sm h-32 w-full rounded-md object-cover"
                    />
                  )}
                  <p className="font-medium">{item.title}</p>
                  <p className="text-sm text-text-secondary">
                    {[item.location_city, item.location_state].filter(Boolean).join(", ")}
                  </p>
                  <div className="mt-sm flex items-center gap-sm">
                    <StatusBadge
                      value={item.status}
                      label={item.status.replace(/_/g, " ")}
                      tone={LISTING_STATUS_TONE[item.status] ?? "neutral"}
                    />
                    <span className="text-xs capitalize text-text-secondary">
                      {item.listing_type}
                    </span>
                  </div>
                </Link>
              ))}
            </div>

            {cursor && (
              <div className="mt-lg flex justify-center">
                <button
                  type="button"
                  className="rounded-md border border-border px-md py-sm text-sm"
                  onClick={() => void handleLoadMore()}
                  disabled={loadingMore}
                >
                  {loadingMore ? "Loading..." : "Load more"}
                </button>
              </div>
            )}
          </>
        )}
      </div>
    </>
  );
}
