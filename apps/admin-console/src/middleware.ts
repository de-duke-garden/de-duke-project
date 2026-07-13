/**
 * Edge-level redirect for unauthenticated visitors -- a UX convenience only.
 * This is a coarse "is there a session cookie at all" check; it does NOT
 * validate the token or role (that would require calling the backend from
 * the edge on every request). Real authorization happens in getAdminSession()
 * (src/lib/auth.ts, called server-side on every protected page) and, always,
 * on the Backend API Service itself -- this middleware is a nicety, not a
 * security boundary.
 */

import { NextRequest, NextResponse } from "next/server";

import { SESSION_COOKIE_NAME } from "@/lib/auth";

// "/s" is FEAT-020's public Shareable Summary view (screens.md Screen 18,
// route `/s/:token`) -- explicitly "Web (external, unauthenticated)"; a
// non-app-user approver must be able to load it with no session cookie at
// all, so it's allowlisted here alongside the login page itself.
const PUBLIC_PATHS = ["/login", "/api/session", "/s"];

export function middleware(request: NextRequest) {
  const { pathname } = request.nextUrl;

  if (PUBLIC_PATHS.some((path) => pathname.startsWith(path))) {
    return NextResponse.next();
  }

  const hasSessionCookie = request.cookies.has(SESSION_COOKIE_NAME);
  if (!hasSessionCookie) {
    const loginUrl = new URL("/login", request.url);
    return NextResponse.redirect(loginUrl);
  }

  return NextResponse.next();
}

export const config = {
  matcher: ["/((?!_next/static|_next/image|favicon.ico).*)"],
};
