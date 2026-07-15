"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import {
  collection,
  doc,
  onSnapshot,
  orderBy,
  query,
  addDoc,
  serverTimestamp,
  updateDoc,
  Timestamp,
  type Firestore,
} from "firebase/firestore";

import { ChatUnavailableError, signInToChat } from "@/lib/firebaseChat";
import { TableSkeleton } from "@/components/ui/Skeleton";
import { StatusBadge } from "@/components/ui/StatusBadge";
import type { ChatConversation, ChatMessage } from "./types";

type LoadState = "loading" | "loaded" | "unavailable" | "error";

/** Minimal subset of GET /v1/listings/:id's response this panel actually
 * displays -- confirmed real gap: the conversation list/detail previously
 * showed only the raw `listingId`, and there was no way to see anything
 * about the property a conversation was about without leaving the console
 * entirely. */
interface ListingSummary {
  title: string;
  listingType: string;
  status: string;
  priceLabel: string;
  addressLine: string;
  city: string;
  state: string;
  // FEAT-042 -- the same host context a seeker sees on the mobile Listing
  // Detail screen's Host Profile card, surfaced here so staff have it
  // while mediating a conversation without leaving to open the full
  // Listing Detail (Admin View).
  hostBio: string | null;
}

async function requestChatToken(): Promise<string> {
  const response = await fetch("/api/backend/v1/chat/token", { method: "POST" });
  if (response.ok === false) {
    const body = await response.json().catch(() => null);
    throw new Error(body?.detail ?? "Could not obtain a chat session (" + response.status + ")");
  }
  const body = await response.json();
  return body.firebase_custom_token as string;
}

async function fetchListingSummary(listingId: string): Promise<ListingSummary | null> {
  const response = await fetch(`/api/backend/v1/listings/${listingId}`);
  if (response.ok === false) return null;
  const data = await response.json();
  const commercial = data.commercial as { price?: number } | null;
  const shortlet = data.shortlet as { nightly_price?: number } | null;
  const price = commercial?.price ?? shortlet?.nightly_price;
  return {
    title: (data.title as string) ?? `Listing ${listingId}`,
    listingType: (data.listing_type as string) ?? "",
    status: (data.status as string) ?? "",
    priceLabel:
      price != null
        ? `₦${Number(price).toLocaleString()}${shortlet ? "/night" : ""}`
        : "Price unavailable",
    addressLine: (data.location_address_line as string) ?? "",
    city: (data.location_city as string) ?? "",
    state: (data.location_state as string) ?? "",
    hostBio: (data.host_bio as string | null) ?? null,
  };
}

/** Batched via GET /v1/chat/users?ids=a,b,c (app/api/v1/chat_auth.py) --
 * one request per newly-seen id set rather than one per user, since a
 * conversation list can carry dozens of distinct client/property-
 * management/assigned-staff ids at once. */
async function fetchUserNames(ids: string[]): Promise<Record<string, string>> {
  if (ids.length === 0) return {};
  const response = await fetch(`/api/backend/v1/chat/users?ids=${ids.join(",")}`);
  if (response.ok === false) return {};
  const body = (await response.json()) as { id: string; full_name: string }[];
  return Object.fromEntries(body.map((u) => [u.id, u.full_name]));
}

function toMillis(value: unknown): number | null {
  if (value instanceof Timestamp) return value.toMillis();
  return null;
}

function conversationFromSnapshot(id: string, data: Record<string, unknown>): ChatConversation {
  return {
    id,
    listingId: (data.listingId as string) ?? "",
    clientId: (data.clientId as string) ?? "",
    propertyManagementId: (data.propertyManagementId as string) ?? "",
    assignedStaffId: (data.assignedStaffId as string | null) ?? null,
    lastMessageAt: toMillis(data.lastMessageAt),
    createdAt: toMillis(data.createdAt),
  };
}

function messageFromSnapshot(id: string, conversationId: string, data: Record<string, unknown>): ChatMessage {
  return {
    id,
    conversationId,
    senderId: (data.senderId as string | null) ?? null,
    senderRole: (data.senderRole as string | null) ?? null,
    messageType: (data.messageType as string) ?? "text",
    body: (data.body as string) ?? "",
    deliveryStatus: (data.deliveryStatus as string) ?? "sent",
    sentAt: toMillis(data.sentAt),
  };
}

/** screens.md Screen 22: Admin Conversation Oversight (Chat Oversight
 * Module). De-Duke Staff/Admin can view and post into any conversation,
 * per firestore.rules's isStaff() rule (both backend roles map to the
 * same "deduke_staff" Firestore claim, chat_service.chat_role_for). */
export function ChatOversightClient({ currentUserId }: { currentUserId: string }) {
  const [state, setState] = useState<LoadState>("loading");
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const [db, setDb] = useState<Firestore | null>(null);

  const [conversations, setConversations] = useState<ChatConversation[]>([]);
  const [searchListingId, setSearchListingId] = useState("");

  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [draft, setDraft] = useState("");
  const [sending, setSending] = useState(false);
  const [assigning, setAssigning] = useState(false);
  const [showListingDetail, setShowListingDetail] = useState(false);

  // Confirmed real gaps this fills: (1) every row showed the raw
  // `listingId` instead of the property's title -- resolved via
  // GET /v1/listings/:id per unique listing; (2) client/property-
  // management/assigned-staff ids showed as raw UUIDs -- resolved via the
  // new batched GET /v1/chat/users. Both are keyed maps populated lazily
  // as new ids appear in the live conversation stream, never re-fetched
  // once cached.
  const [listings, setListings] = useState<Record<string, ListingSummary>>({});
  const [userNames, setUserNames] = useState<Record<string, string>>({});
  const fetchingListingIds = useRef(new Set<string>());
  const fetchingUserIds = useRef(new Set<string>());

  // Sign in to Firestore once on mount.
  useEffect(() => {
    let cancelled = false;
    async function signIn() {
      try {
        const token = await requestChatToken();
        const firestore = await signInToChat(token);
        if (!cancelled) {
          setDb(firestore);
          setState("loaded");
        }
      } catch (e) {
        if (cancelled) return;
        if (e instanceof ChatUnavailableError) {
          setState("unavailable");
          setErrorMessage(e.message);
        } else {
          setState("error");
          setErrorMessage(e instanceof Error ? e.message : "Could not connect to chat.");
        }
      }
    }
    void signIn();
    return () => {
      cancelled = true;
    };
  }, []);

  // Subscribe to the conversation list once signed in. Firestore's own
  // `orderBy("lastMessageAt", "desc")` keeps this self-sorting newest-first
  // as messages arrive -- no separate client-side sort needed.
  useEffect(() => {
    if (!db) return;
    const q = query(collection(db, "conversations"), orderBy("lastMessageAt", "desc"));
    const unsubscribe = onSnapshot(
      q,
      (snapshot) => {
        setConversations(snapshot.docs.map((d) => conversationFromSnapshot(d.id, d.data())));
      },
      (err) => {
        setState("error");
        setErrorMessage(err.message);
      },
    );
    return unsubscribe;
  }, [db]);

  // Resolve listing titles for every conversation currently in view,
  // fetching only ids not already cached or already in flight.
  useEffect(() => {
    const missing = [...new Set(conversations.map((c) => c.listingId))].filter(
      (id) => id && !listings[id] && !fetchingListingIds.current.has(id),
    );
    if (missing.length === 0) return;
    missing.forEach((id) => fetchingListingIds.current.add(id));
    void Promise.all(
      missing.map(async (id) => {
        const summary = await fetchListingSummary(id);
        fetchingListingIds.current.delete(id);
        if (summary) setListings((prev) => ({ ...prev, [id]: summary }));
      }),
    );
  }, [conversations, listings]);

  // Resolve display names for every client/property-management/assigned-
  // staff id currently in view, batched into as few requests as possible.
  useEffect(() => {
    const seen = new Set<string>();
    for (const c of conversations) {
      if (c.clientId) seen.add(c.clientId);
      if (c.propertyManagementId) seen.add(c.propertyManagementId);
      if (c.assignedStaffId) seen.add(c.assignedStaffId);
    }
    const missing = [...seen].filter(
      (id) => !userNames[id] && !fetchingUserIds.current.has(id),
    );
    if (missing.length === 0) return;
    missing.forEach((id) => fetchingUserIds.current.add(id));
    void fetchUserNames(missing).then((names) => {
      missing.forEach((id) => fetchingUserIds.current.delete(id));
      if (Object.keys(names).length > 0) {
        setUserNames((prev) => ({ ...prev, ...names }));
      }
    });
  }, [conversations, userNames]);

  // Subscribe to the selected conversation's messages.
  useEffect(() => {
    if (!db || !selectedId) {
      setMessages([]);
      return;
    }
    const q = query(collection(db, "conversations", selectedId, "messages"), orderBy("sentAt", "asc"));
    const unsubscribe = onSnapshot(q, (snapshot) => {
      setMessages(snapshot.docs.map((d) => messageFromSnapshot(d.id, selectedId, d.data())));
    });
    return unsubscribe;
  }, [db, selectedId]);

  const scrollRef = useRef<HTMLDivElement>(null);
  useEffect(() => {
    scrollRef.current?.scrollTo({ top: scrollRef.current.scrollHeight });
  }, [messages]);

  // `duration-normal` slide-in for the conversation detail panel (branding.md
  // Admin Web Console motion system / screens.md Screen 22 Modernization
  // Notes) instead of a hard swap when a new conversation is selected.
  const [panelEntered, setPanelEntered] = useState(false);
  useEffect(() => {
    if (!selectedId) return;
    setPanelEntered(false);
    setShowListingDetail(false);
    const frame = requestAnimationFrame(() => setPanelEntered(true));
    return () => cancelAnimationFrame(frame);
  }, [selectedId]);

  const sendMessage = useCallback(async () => {
    if (!db || !selectedId || draft.trim().length === 0) return;
    setSending(true);
    try {
      await addDoc(collection(db, "conversations", selectedId, "messages"), {
        senderId: currentUserId,
        senderRole: "deduke_staff",
        messageType: "text",
        body: draft.trim(),
        deliveryStatus: "sent",
        sentAt: serverTimestamp(),
      });
      setDraft("");
    } finally {
      setSending(false);
    }
  }, [db, selectedId, draft, currentUserId]);

  // Confirmed real gap: nothing ever wrote `assignedStaffId` -- a staff
  // member joining a conversation never actually "picked it up" in any
  // durable sense, and there was no way to hand a conversation back for
  // another staff member to take over. firestore.rules already permits any
  // signed-in staff/admin to update `assignedStaffId` freely (see its own
  // comment: "Staff may update freely, e.g. assignedStaffId when picking
  // up an escalation") -- these two actions are the UI that was missing
  // for a capability the security rules already supported.
  const setAssignedStaff = useCallback(
    async (staffId: string | null) => {
      if (!db || !selectedId) return;
      setAssigning(true);
      try {
        await updateDoc(doc(db, "conversations", selectedId), { assignedStaffId: staffId });
      } finally {
        setAssigning(false);
      }
    },
    [db, selectedId],
  );

  if (state === "loading") {
    return <TableSkeleton rows={6} columns={3} />;
  }

  if (state === "unavailable") {
    return (
      <div className="rounded-md border border-warning bg-warning/10 p-md">
        <p className="text-sm">{errorMessage}</p>
        <p className="mt-xs text-sm text-text-secondary">
          Provision a Firebase project and set NEXT_PUBLIC_FIREBASE_* environment variables to
          enable Chat Oversight.
        </p>
      </div>
    );
  }

  if (state === "error") {
    return (
      <div className="rounded-md border border-error p-md">
        <p className="text-error">{errorMessage}</p>
      </div>
    );
  }

  const filtered = searchListingId.trim()
    ? conversations.filter((c) => {
        const term = searchListingId.trim().toLowerCase();
        const title = listings[c.listingId]?.title ?? "";
        return c.listingId.includes(searchListingId.trim()) || title.toLowerCase().includes(term);
      })
    : conversations;

  const selected = conversations.find((c) => c.id === selectedId) ?? null;
  const selectedListing = selected ? listings[selected.listingId] : null;
  const nameFor = (id: string | null) => (id ? (userNames[id] ?? id) : null);

  return (
    <div className="flex gap-md" style={{ height: "70vh" }}>
      <div className="w-1/3 overflow-y-auto border-r border-border pr-md dark:border-border-dark">
        <input
          type="text"
          placeholder="Filter by listing title or ID"
          value={searchListingId}
          onChange={(e) => setSearchListingId(e.target.value)}
          className="mb-sm w-full rounded-md border border-border bg-transparent p-sm text-sm"
        />

        {filtered.length === 0 && <p className="text-sm text-text-secondary">No conversations.</p>}

        {filtered.map((conversation) => {
          const assignedName = nameFor(conversation.assignedStaffId);
          return (
            <button
              key={conversation.id}
              type="button"
              onClick={() => setSelectedId(conversation.id)}
              className={
                "mb-xs block w-full rounded-md p-sm text-left text-sm transition-colors duration-[120ms] ease-out-smooth " +
                (conversation.id === selectedId
                  ? "bg-primary-light dark:bg-primary-light-dark"
                  : "hover:bg-surface-secondary dark:hover:bg-surface-secondary-dark")
              }
            >
              <p className="font-medium">
                {listings[conversation.listingId]?.title ?? `Listing ${conversation.listingId}`}
              </p>
              <p className="text-text-secondary">
                Client {nameFor(conversation.clientId)} / PM {nameFor(conversation.propertyManagementId)}
              </p>
              <div className="mt-xs">
                <StatusBadge
                  value={conversation.assignedStaffId ?? "unassigned"}
                  label={assignedName ? `Assigned: ${assignedName}` : "Unassigned"}
                  tone={conversation.assignedStaffId ? "primary" : "neutral"}
                />
              </div>
            </button>
          );
        })}
      </div>

      <div className="flex w-2/3 flex-col">
        {!selected && (
          <p className="text-text-secondary">Select a conversation to view the thread.</p>
        )}

        {selected && (
          <div
            key={selected.id}
            className={
              "flex flex-1 flex-col transition-all duration-[200ms] ease-out-smooth " +
              (panelEntered ? "translate-x-0 opacity-100" : "translate-x-4 opacity-0")
            }
          >
            <div className="mb-sm rounded-md border border-border p-sm dark:border-border-dark">
              <div className="flex items-start justify-between gap-sm">
                <div>
                  <p className="font-medium">
                    {selectedListing?.title ?? `Listing ${selected.listingId}`}
                  </p>
                  <p className="text-xs text-text-secondary">
                    Client {nameFor(selected.clientId)} / PM {nameFor(selected.propertyManagementId)}
                  </p>
                </div>
                {selectedListing && (
                  <button
                    type="button"
                    onClick={() => setShowListingDetail((v) => !v)}
                    className="shrink-0 rounded-md border border-border px-sm py-1 text-xs hover:bg-surface-secondary dark:border-border-dark dark:hover:bg-surface-secondary-dark"
                  >
                    {showListingDetail ? "Hide property" : "View property"}
                  </button>
                )}
              </div>

              {showListingDetail && selectedListing && (
                <dl className="mt-sm grid grid-cols-2 gap-x-sm gap-y-1 text-xs text-text-secondary">
                  <dt>Type</dt>
                  <dd className="capitalize">{selectedListing.listingType}</dd>
                  <dt>Price</dt>
                  <dd>{selectedListing.priceLabel}</dd>
                  <dt>Status</dt>
                  <dd className="capitalize">{selectedListing.status.replace("_", " ")}</dd>
                  <dt>Location</dt>
                  <dd>
                    {[selectedListing.addressLine, selectedListing.city, selectedListing.state]
                      .filter(Boolean)
                      .join(", ")}
                  </dd>
                  {/* FEAT-042 -- host bio spans both columns (a longer,
                      prose field, unlike the short type/price/status/
                      location facts above it). */}
                  {selectedListing.hostBio && (
                    <>
                      <dt className="col-span-2 mt-xs">Host bio</dt>
                      <dd className="col-span-2">{selectedListing.hostBio}</dd>
                    </>
                  )}
                </dl>
              )}

              <div className="mt-sm flex items-center gap-sm">
                <StatusBadge
                  value={selected.assignedStaffId ?? "unassigned"}
                  label={
                    nameFor(selected.assignedStaffId)
                      ? `Assigned: ${nameFor(selected.assignedStaffId)}`
                      : "Unassigned"
                  }
                  tone={selected.assignedStaffId ? "primary" : "neutral"}
                />
                {/* "Assign to me" also lets a different staff member take
                    over an already-assigned conversation -- firestore.rules
                    permits any staff to write assignedStaffId, by design
                    (see this file's setAssignedStaff docstring above). */}
                {selected.assignedStaffId !== currentUserId && (
                  <button
                    type="button"
                    onClick={() => void setAssignedStaff(currentUserId)}
                    disabled={assigning}
                    className="rounded-md border border-border px-sm py-1 text-xs hover:bg-surface-secondary disabled:opacity-60 dark:border-border-dark dark:hover:bg-surface-secondary-dark"
                  >
                    Assign to me
                  </button>
                )}
                {selected.assignedStaffId && (
                  <button
                    type="button"
                    onClick={() => void setAssignedStaff(null)}
                    disabled={assigning}
                    className="rounded-md border border-border px-sm py-1 text-xs hover:bg-surface-secondary disabled:opacity-60 dark:border-border-dark dark:hover:bg-surface-secondary-dark"
                  >
                    Release
                  </button>
                )}
              </div>
            </div>

            <div ref={scrollRef} className="flex-1 overflow-y-auto pr-sm">
              {messages.map((message) => (
                <div
                  key={message.id}
                  className={
                    "mb-sm max-w-[80%] rounded-md p-sm text-sm " +
                    (message.senderRole === "deduke_staff"
                      ? "ml-auto bg-primary text-white"
                      : "bg-surface-secondary dark:bg-surface-secondary-dark")
                  }
                >
                  <p className="text-xs opacity-70">{message.senderRole ?? "system"}</p>
                  <p>{message.body}</p>
                </div>
              ))}
            </div>

            <div className="mt-sm flex gap-sm">
              <input
                type="text"
                value={draft}
                onChange={(e) => setDraft(e.target.value)}
                onKeyDown={(e) => {
                  if (e.key === "Enter") void sendMessage();
                }}
                placeholder="Join the conversation..."
                disabled={sending}
                className="flex-1 rounded-md border border-border bg-transparent p-sm text-sm"
              />
              <button
                type="button"
                onClick={() => void sendMessage()}
                disabled={sending || draft.trim().length === 0}
                className="rounded-md bg-primary px-md py-sm text-sm font-medium text-white disabled:opacity-60"
              >
                Send
              </button>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
