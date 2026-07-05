"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import {
  collection,
  onSnapshot,
  orderBy,
  query,
  addDoc,
  serverTimestamp,
  Timestamp,
  type Firestore,
} from "firebase/firestore";

import { ChatUnavailableError, signInToChat } from "@/lib/firebaseChat";
import type { ChatConversation, ChatMessage } from "./types";

type LoadState = "loading" | "loaded" | "unavailable" | "error";

async function requestChatToken(): Promise<string> {
  const response = await fetch("/api/backend/v1/chat/token", { method: "POST" });
  if (response.ok === false) {
    const body = await response.json().catch(() => null);
    throw new Error(body?.detail ?? "Could not obtain a chat session (" + response.status + ")");
  }
  const body = await response.json();
  return body.firebase_custom_token as string;
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

  // Subscribe to the conversation list once signed in.
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

  if (state === "loading") {
    return <p className="text-text-secondary">Connecting to chat...</p>;
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
    ? conversations.filter((c) => c.listingId.includes(searchListingId.trim()))
    : conversations;

  const selected = conversations.find((c) => c.id === selectedId) ?? null;

  return (
    <div className="flex gap-md" style={{ height: "70vh" }}>
      <div className="w-1/3 overflow-y-auto border-r border-border pr-md dark:border-border-dark">
        <input
          type="text"
          placeholder="Filter by listing ID"
          value={searchListingId}
          onChange={(e) => setSearchListingId(e.target.value)}
          className="mb-sm w-full rounded-md border border-border bg-transparent p-sm text-sm"
        />

        {filtered.length === 0 && <p className="text-sm text-text-secondary">No conversations.</p>}

        {filtered.map((conversation) => (
          <button
            key={conversation.id}
            type="button"
            onClick={() => setSelectedId(conversation.id)}
            className={
              "mb-xs block w-full rounded-md p-sm text-left text-sm " +
              (conversation.id === selectedId
                ? "bg-primary-light dark:bg-primary-light-dark"
                : "hover:bg-surface-secondary dark:hover:bg-surface-secondary-dark")
            }
          >
            <p className="font-medium">Listing {conversation.listingId}</p>
            <p className="text-text-secondary">
              Client {conversation.clientId} / PM {conversation.propertyManagementId}
            </p>
            {conversation.assignedStaffId && (
              <p className="text-xs text-primary">Assigned: {conversation.assignedStaffId}</p>
            )}
          </button>
        ))}
      </div>

      <div className="flex w-2/3 flex-col">
        {!selected && (
          <p className="text-text-secondary">Select a conversation to view the thread.</p>
        )}

        {selected && (
          <>
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
          </>
        )}
      </div>
    </div>
  );
}
