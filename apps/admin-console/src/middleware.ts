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

// Public paths that never require a session cookie. FEAT-020's Shareable
// Summary view (Screen 18) moved to the MARKETING site (de-duke.com/s/:token)
// -- it no longer lives in this console, so it is no longer allowlisted here.
const PUBLIC_PATHS = ["/login", "/api/session", "/accept-invite"];

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
  // Run middleware on everything EXCEPT framework internals and static
  // public/ assets. Without the public exclusion, a request for e.g.
  // /logo.png (an image, not a page) would be treated like a page: no
  // session cookie -> 307 redirect to /login -> the browser follows and
  // gets the app HTML shell, rendering the image broken. Static assets
  // must never go through the auth redirect.
  matcher: [
    "/((?!_next/static|_next/image|favicon.ico|logo.png|.*\\.(?:png|jpg|jpeg|svg|webp|ico|css|js)$).*)",
  ],
};
