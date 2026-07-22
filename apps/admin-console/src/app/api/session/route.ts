/**
 * Session Route Handler -- proxies login/logout to the Backend API Service
 * and manages the httpOnly session cookie. Kept server-side only so the
 * access token is never exposed to client-side JavaScript (XSS-safe).
 */

import { NextRequest, NextResponse } from "next/server";
import { cookies } from "next/headers";

import { SESSION_COOKIE_NAME } from "@/lib/auth";

const API_BASE_URL = process.env.NEXT_PUBLIC_API_BASE_URL ?? "http://localhost:8000/v1";

// Mirrors app/core/config.py's access_token_expire_minutes default (14 days)
// -- kept in sync manually since the cookie's Max-Age can't ask the backend
// what the token's expiry actually is without decoding it.
const SESSION_MAX_AGE_SECONDS = 60 * 60 * 24 * 14;

export async function POST(request: NextRequest) {
  const { email, password } = await request.json();

  if (!email || !password) {
    return NextResponse.json({ detail: "Email and password are required." }, { status: 400 });
  }

  let backendResponse: Response;
  try {
    backendResponse = await fetch(`${API_BASE_URL}/auth/login`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ email, password }),
      cache: "no-store",
    });
  } catch {
    return NextResponse.json(
      { detail: "Could not reach the De-Duke backend. Try again shortly." },
      { status: 503 },
    );
  }

  if (!backendResponse.ok) {
    // Mirror the backend's error rather than inventing a generic one --
    // FEAT-001 AC: "Invalid credentials show a clear, specific error message".
    const body = await backendResponse.json().catch(() => ({}));
    return NextResponse.json(
      { detail: body.detail ?? "Invalid email or password." },
      { status: backendResponse.status },
    );
  }

  const body = await backendResponse.json();

  // De-Duke Staff/Admin only -- a guest/host/agency account can
  // authenticate against the same backend endpoint, but must never gain
  // access to the Admin Web Console. Enforced here AND (redundantly, on
  // purpose) by every backend endpoint's own role checks.
  if (body.role !== "deduke_staff" && body.role !== "deduke_admin") {
    return NextResponse.json(
      { detail: "This account does not have access to the Admin Web Console." },
      { status: 403 },
    );
  }

  const cookieStore = await cookies();
  cookieStore.set(SESSION_COOKIE_NAME, body.access_token, {
    httpOnly: true,
    secure: process.env.NODE_ENV === "production",
    sameSite: "lax",
    path: "/",
    maxAge: SESSION_MAX_AGE_SECONDS,
  });

  return NextResponse.json({ status: "ok" });
}

export async function DELETE() {
  const cookieStore = await cookies();
  cookieStore.delete(SESSION_COOKIE_NAME);
  return NextResponse.json({ status: "ok" });
}
