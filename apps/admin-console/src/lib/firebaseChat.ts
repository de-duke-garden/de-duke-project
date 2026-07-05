/**
 * Client-side Firebase/Firestore access for the Chat Oversight Module
 * (FEAT-010, screens.md Screen 22).
 *
 * Real-time chat lives entirely in Firestore -- the admin console connects
 * directly (never proxied through the backend), same as the mobile app
 * (apps/mobile/lib/features/chat/data/chat_repository.dart). The backend's
 * only role is issuing a scoped custom auth token (POST /v1/chat/token,
 * called via the same-origin proxy so the session cookie can be exchanged
 * for it) that this module signs in with, then reads/writes Firestore
 * directly, gated by apps/backend/firestore.rules's `role: "deduke_staff"`
 * claim (shared by both deduke_staff and deduke_admin backend roles).
 *
 * No Firebase project is provisioned in this environment (every
 * NEXT_PUBLIC_FIREBASE_* value below is unset) -- every function here
 * fails closed with a clear "not configured" error rather than throwing an
 * opaque Firebase SDK error, mirroring app/services/chat_service.py's own
 * ChatServiceUnavailableError pattern on the backend.
 */

import { type FirebaseApp, getApps, initializeApp } from "firebase/app";
import { getAuth, signInWithCustomToken, type Auth } from "firebase/auth";
import { getFirestore, type Firestore } from "firebase/firestore";

export class ChatUnavailableError extends Error {}

const firebaseConfig = {
  apiKey: process.env.NEXT_PUBLIC_FIREBASE_API_KEY,
  authDomain: process.env.NEXT_PUBLIC_FIREBASE_AUTH_DOMAIN,
  projectId: process.env.NEXT_PUBLIC_FIREBASE_PROJECT_ID,
};

function isConfigured(): boolean {
  return Boolean(firebaseConfig.apiKey && firebaseConfig.authDomain && firebaseConfig.projectId);
}

let cachedApp: FirebaseApp | null = null;

function getFirebaseApp(): FirebaseApp {
  if (!isConfigured()) {
    throw new ChatUnavailableError(
      "Chat is not configured yet -- NEXT_PUBLIC_FIREBASE_* environment variables are unset.",
    );
  }
  if (cachedApp) return cachedApp;
  const existing = getApps();
  cachedApp = existing.length > 0 ? existing[0]! : initializeApp(firebaseConfig);
  return cachedApp;
}

/** Exchanges a Firebase custom token (from POST /v1/chat/token, proxied)
 * for a signed-in Firestore session. Call once per admin-console session. */
export async function signInToChat(customToken: string): Promise<Firestore> {
  const app = getFirebaseApp();
  const auth: Auth = getAuth(app);
  await signInWithCustomToken(auth, customToken);
  return getFirestore(app);
}
