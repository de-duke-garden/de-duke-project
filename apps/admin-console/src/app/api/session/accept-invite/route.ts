/**
 * Accept-Invite Route Handler -- FEAT-033 AC ("the invitee sets their own
 * password via an emailed invitation link"). Proxies to the Backend API
 * Service's POST /v1/auth/accept-invite and, on success, sets the same
 * httpOnly session cookie /api/session's login POST does -- the invitee
 * lands signed in immediately after choosing their password, without a
 * separate login step.
 */

import { NextRequest, NextResponse } from "next/server";
import { cookies } from "next/headers";

import { SESSION_COOKIE_NAME } from "@/lib/auth";

const API_BASE_URL = process.env.NEXT_PUBLIC_API_BASE_URL ?? "http://localhost:8000/v1";

// Mirrors /api/session/route.ts's own constant -- kept in sync manually,
// see that file's comment for why.
const SESSION_MAX_AGE_SECONDS = 60 * 60 * 24 * 14;

export async function POST(request: NextRequest) {
  const { userId, inviteToken, newPassword } = await request.json();

  if (!userId || !inviteToken || !newPassword) {
    return NextResponse.json(
      { detail: "Missing invite details or new password." },
      { status: 400 },
    );
  }

  let backendResponse: Response;
  try {
    backendResponse = await fetch(`${API_BASE_URL}/auth/accept-invite`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        user_id: userId,
        invite_token: inviteToken,
        new_password: newPassword,
      }),
      cache: "no-store",
    });
  } catch {
    return NextResponse.json(
      { detail: "Could not reach the De-Duke backend. Try again shortly." },
      { status: 503 },
    );
  }

  if (!backendResponse.ok) {
    const body = await backendResponse.json().catch(() => ({}));
    return NextResponse.json(
      { detail: body.detail ?? "This invite link is invalid or has already been used." },
      { status: backendResponse.status },
    );
  }

  const body = await backendResponse.json();

  // Same Staff/Admin-only gate as /api/session's login handler -- an
  // agency team member's invite token (FEAT-012) also flows through this
  // shared backend endpoint, but must never gain Admin Web Console access.
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
