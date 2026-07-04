/**
 * Server-side session/role guard for the Admin Web Console.
 *
 * Enforces role checks the same way the backend does (AGENTS.md: never rely
 * on hiding UI elements client-side). Staff-level accounts get Staff-tier
 * routes; Admin-only routes (commission config, staff management) additionally
 * require the deduke_admin role -- checked here AND re-checked by the
 * Backend API Service on every request.
 */

export type StaffRole = "deduke_staff" | "deduke_admin";

export interface AdminSession {
  userId: string;
  role: StaffRole;
}

/**
 * Placeholder -- Foundation stub. Real implementation (Subagent 6, FEAT-033)
 * validates the session token against the Backend API Service and returns
 * the decoded role, or null if unauthenticated.
 */
export async function getAdminSession(): Promise<AdminSession | null> {
  return null;
}

export function requireAdminRole(session: AdminSession | null): session is AdminSession & { role: "deduke_admin" } {
  return session?.role === "deduke_admin";
}
