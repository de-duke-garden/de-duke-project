"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import {
  collection,
  doc,
  onSnapshot,
  orderBy,
  query,
  addDoc,
  updateDoc,
  serverTimestamp,
  Timestamp,
  type Firestore,
} from "firebase/firestore";

import { ChatUnavailableError, signInToChat } from "@/lib/firebaseChat";
import { TableSkeleton } from "@/components/ui/Skeleton";
import { StatusBadge } from "@/components/ui/StatusBadge";
import type { ChatMessage } from "../chat/types";
import type { SupportConversation } from "./types";

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

function conversationFromSnapshot(
  id: string,
  data: Record<string, unknown>,
): SupportConversation {
  return {
    id,
    userId: (data.userId as string) ?? "",
    assignedStaffId: (data.assignedStaffId as string | null) ?? null,
    status: (data.status as string) ?? "open",
    lastMessageAt: toMillis(data.lastMessageAt),
    createdAt: toMillis(data.createdAt),
  };
}

function messageFromSnapshot(
  id: string,
  conversationId: string,
  data: Record<string, unknown>,
): ChatMessage {
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

/** screens.md Screen 26: Admin General Support Inbox -- FEAT-029.
 * Structurally identical to ChatOversightClient (same Firestore
 * sign-in/subscribe/send pattern), against `support_conversations`
 * instead of `conversations`. Any signed-in Staff/Admin can view and
 * reply to any support conversation, per firestore.rules's isStaff(). */
export function SupportInboxClient({ currentUserId }: { currentUserId: string }) {
  const [state, setState] = useState<LoadState>("loading");
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const [db, setDb] = useState<Firestore | null>(null);

  const [conversations, setConversations] = useState<SupportConversation[]>([]);
  const [statusFilter, setStatusFilter] = useState<"all" | "open" | "resolved">("open");

  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [draft, setDraft] = useState("");
  const [sending, setSending] = useState(false);

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

  useEffect(() => {
    if (!db) return;
    const q = query(collection(db, "support_conversations"), orderBy("lastMessageAt", "desc"));
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

  useEffect(() => {
    if (!db || !selectedId) {
      setMessages([]);
      return;
    }
    const q = query(
      collection(db, "support_conversations", selectedId, "messages"),
      orderBy("sentAt", "asc"),
    );
    const unsubscribe = onSnapshot(q, (snapshot) => {
      setMessages(snapshot.docs.map((d) => messageFromSnapshot(d.id, selectedId, d.data())));
    });
    return unsubscribe;
  }, [db, selectedId]);

  const scrollRef = useRef<HTMLDivElement>(null);
  useEffect(() => {
    scrollRef.current?.scrollTo({ top: scrollRef.current.scrollHeight });
  }, [messages]);

  // `duration-normal` slide-in for the conversation panel, matching
  // Conversation Oversight (screens.md Screen 26 Modernization Notes).
  const [panelEntered, setPanelEntered] = useState(false);
  useEffect(() => {
    if (!selectedId) return;
    setPanelEntered(false);
    const frame = requestAnimationFrame(() => setPanelEntered(true));
    return () => cancelAnimationFrame(frame);
  }, [selectedId]);

  const sendMessage = useCallback(async () => {
    if (!db || !selectedId || draft.trim().length === 0) return;
    setSending(true);
    try {
      await addDoc(collection(db, "support_conversations", selectedId, "messages"), {
        senderId: currentUserId,
        senderRole: "deduke_staff",
        messageType: "text",
        body: draft.trim(),
        deliveryStatus: "sent",
        sentAt: serverTimestamp(),
      });
      await updateDoc(doc(db, "support_conversations", selectedId), {
        lastMessageAt: serverTimestamp(),
      });
      setDraft("");
    } finally {
      setSending(false);
    }
  }, [db, selectedId, draft, currentUserId]);

  const markResolved = useCallback(async () => {
    if (!db || !selectedId) return;
    await updateDoc(doc(db, "support_conversations", selectedId), { status: "resolved" });
  }, [db, selectedId]);

  if (state === "loading") {
    return <TableSkeleton rows={6} columns={3} />;
  }

  if (state === "unavailable") {
    return (
      <div className="rounded-md border border-warning bg-warning/10 p-md">
        <p className="text-sm">{errorMessage}</p>
        <p className="mt-xs text-sm text-text-secondary">
          Provision a Firebase project and set NEXT_PUBLIC_FIREBASE_* environment variables to
          enable the Support Inbox.
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

  const filtered =
    statusFilter === "all" ? conversations : conversations.filter((c) => c.status === statusFilter);
  const selected = conversations.find((c) => c.id === selectedId) ?? null;

  if (conversations.length === 0) {
    return <p className="text-text-secondary">Inbox is clear.</p>;
  }

  return (
    <div className="flex gap-md" style={{ height: "70vh" }}>
      <div className="w-1/3 overflow-y-auto border-r border-border pr-md dark:border-border-dark">
        <div className="mb-sm flex gap-sm">
          {(["open", "resolved", "all"] as const).map((f) => (
            <button
              key={f}
              type="button"
              className={`rounded-full border px-md py-1 text-xs capitalize ${
                statusFilter === f
                  ? "border-primary bg-primary text-white"
                  : "border-border text-text-secondary"
              }`}
              onClick={() => setStatusFilter(f)}
            >
              {f}
            </button>
          ))}
        </div>

        {filtered.length === 0 && <p className="text-sm text-text-secondary">No conversations.</p>}

        {filtered.map((conversation) => (
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
            <p className="font-medium">User {conversation.userId}</p>
            <div className="mt-xs">
              <StatusBadge
                value={conversation.status}
                label={conversation.status}
                tone={conversation.status === "resolved" ? "success" : "primary"}
              />
            </div>
            {conversation.assignedStaffId && (
              <p className="mt-xs text-xs text-primary">Assigned: {conversation.assignedStaffId}</p>
            )}
          </button>
        ))}
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
            <div className="mb-sm flex items-center justify-between">
              <div className="flex items-center gap-sm text-sm text-text-secondary">
                <span>Status:</span>
                <StatusBadge
                  value={selected.status}
                  label={selected.status}
                  tone={selected.status === "resolved" ? "success" : "primary"}
                />
              </div>
              {selected.status !== "resolved" && (
                <button
                  type="button"
                  className="rounded-md border border-border px-md py-1 text-xs"
                  onClick={() => void markResolved()}
                >
                  Mark resolved
                </button>
              )}
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
                placeholder="Reply..."
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
