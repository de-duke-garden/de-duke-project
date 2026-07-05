/**
 * Server-side proxy for every Backend API Service call made by client
 * components in this console.
 *
 * Why this exists: the session token lives in an httpOnly cookie (never
 * readable by client-side JS, by design -- see src/lib/auth.ts), but the
 * Backend API Service authenticates via `Authorization: Bearer <token>`
 * (HTTPBearer), not cookies, and it lives on a different origin anyway, so
 * a browser `fetch(..., { credentials: "include" })` from a client
 * component was never going to attach anything the backend would accept.
 * This route runs server-side, reads the httpOnly cookie, and forwards the
 * request to the real backend with the correct header -- client components
 * call `/api/backend/v1/...` (same-origin) instead of the backend directly.
 */

import { NextRequest, NextResponse } from "next/server";
import { cookies } from "next/headers";

import { SESSION_COOKIE_NAME } from "@/lib/auth";

const BACKEND_API_URL = process.env.BACKEND_API_URL ?? "http://localhost:8000";

async function proxy(request: NextRequest, path: string[]): Promise<NextResponse> {
  const cookieStore = await cookies();
  const token = cookieStore.get(SESSION_COOKIE_NAME)?.value;
  if (!token) {
    return NextResponse.json({ detail: "Not authenticated." }, { status: 401 });
  }

  const targetUrl = BACKEND_API_URL + "/" + path.join("/") + request.nextUrl.search;

  const hasBody = request.method !== "GET" && request.method !== "HEAD";
  const init: RequestInit = {
    method: request.method,
    headers: {
      Authorization: "Bearer " + token,
      ...(hasBody ? { "Content-Type": "application/json" } : {}),
    },
    body: hasBody ? await request.text() : undefined,
  };

  let backendResponse: Response;
  try {
    backendResponse = await fetch(targetUrl, init);
  } catch {
    return NextResponse.json({ detail: "Could not reach the De-Duke backend." }, { status: 503 });
  }

  const responseBody = await backendResponse.text();
  return new NextResponse(responseBody, {
    status: backendResponse.status,
    headers: { "Content-Type": backendResponse.headers.get("Content-Type") ?? "application/json" },
  });
}

export async function GET(request: NextRequest, { params }: { params: Promise<{ path: string[] }> }) {
  return proxy(request, (await params).path);
}

export async function POST(request: NextRequest, { params }: { params: Promise<{ path: string[] }> }) {
  return proxy(request, (await params).path);
}

export async function PATCH(request: NextRequest, { params }: { params: Promise<{ path: string[] }> }) {
  return proxy(request, (await params).path);
}

export async function DELETE(request: NextRequest, { params }: { params: Promise<{ path: string[] }> }) {
  return proxy(request, (await params).path);
}
