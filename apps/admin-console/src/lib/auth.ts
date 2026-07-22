/**
 * Server-side session/role guard for the Admin Web Console.
 *
 * Enforces role checks the same way the backend does (AGENTS.md: never rely
 * on hiding UI elements client-side). Staff-level accounts get Staff-tier
 * routes; Admin-only routes (commission config, staff management) additionally
 * require the deduke_admin role -- checked here AND re-checked by the
 * Backend API Service on every request.
 *
 * Session model: the access token issued by POST /v1/auth/login is stored
 * in an httpOnly, secure cookie (never readable by client-side JS). This
 * module never decodes the JWT itself or holds the signing secret -- it
 * calls the backend's GET /v1/auth/me on every request needing a session,
 * so token validity/expiry/role is always authoritative from the backend,
 * not re-derived locally.
 */

import { cookies } from "next/headers";

export type StaffRole = "deduke_staff" | "deduke_admin";

export const SESSION_COOKIE_NAME = "deduke_admin_session";

export interface AdminSession {
  userId: string;
  role: StaffRole;
  fullName: string;
  email: string | null;
}

const API_BASE_URL = process.env.NEXT_PUBLIC_API_BASE_URL ?? "http://localhost:8000/v1";

/**
 * Reads the session cookie (if any) and resolves it against the backend.
 * Returns null if there is no cookie, the token is invalid/expired, or the
 * account's role is not deduke_staff/deduke_admin (e.g. a guest/host
 * token should never grant access to this console, even if somehow
 * presented here).
 */
export async function getAdminSession(): Promise<AdminSession | null> {
  const cookieStore = await cookies();
  const token = cookieStore.get(SESSION_COOKIE_NAME)?.value;
  if (!token) return null;

  try {
    const response = await fetch(`${API_BASE_URL}/auth/me`, {
      headers: { Authorization: `Bearer ${token}` },
      cache: "no-store",
    });
    if (!response.ok) return null;

    const body = await response.json();
    if (body.role !== "deduke_staff" && body.role !== "deduke_admin") {
      return null;
    }

    return {
      userId: body.user_id,
      role: body.role,
      fullName: body.full_name,
      email: body.email,
    };
  } catch {
    // Backend unreachable -- fail closed (no session), never fail open.
    return null;
  }
}

export function requireAdminRole(
  session: AdminSession | null,
): session is AdminSession & { role: "deduke_admin" } {
  return session?.role === "deduke_admin";
}
