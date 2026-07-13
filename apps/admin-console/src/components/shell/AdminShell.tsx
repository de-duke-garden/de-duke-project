"use client";

import { useState } from "react";

import type { AdminSession } from "@/lib/auth";

import { AdminNav } from "./AdminNav";

/**
 * Owns the mobile nav-drawer open/closed state and composes the fixed
 * sidebar + scrollable main content area. Split out from layout.tsx (a
 * server component, since it fetches the session) because that state has
 * to be shared between the sidebar itself and the mobile top bar's
 * hamburger toggle -- a client-only concern.
 *
 * Layout shape: `h-screen overflow-hidden` on the outer flex row is the
 * actual fix for "the whole page scrolls instead of just the content" --
 * `min-h-screen` (the previous approach) has no upper bound, so once
 * `main`'s content got tall the flex row itself grew past the viewport
 * and the browser scrolled the whole `<body>` (dragging the sidebar along
 * with it, since it's just a normal in-flow flex sibling). Bounding the
 * row to exactly the viewport height means only `main`'s own
 * `overflow-y-auto` ever has room to activate -- the sidebar (and its own
 * internal nav-link list, independently scrollable for short viewports)
 * stays fixed in place regardless of how tall the page content gets.
 */
export function AdminShell({
  session,
  children,
}: {
  session: AdminSession;
  children: React.ReactNode;
}) {
  const [mobileNavOpen, setMobileNavOpen] = useState(false);

  return (
    <div className="flex h-screen overflow-hidden">
      <AdminNav
        session={session}
        mobileOpen={mobileNavOpen}
        onCloseMobile={() => setMobileNavOpen(false)}
      />

      <div className="flex min-w-0 flex-1 flex-col">
        {/* Mobile-only top bar -- the sidebar is an off-canvas drawer below
            the `md` breakpoint (see AdminNav), so this is the only way to
            reopen it once closed. */}
        <div className="flex items-center gap-sm border-b border-border p-sm md:hidden dark:border-border-dark">
          <button
            type="button"
            onClick={() => setMobileNavOpen(true)}
            aria-label="Open navigation"
            className="flex h-12 w-12 items-center justify-center rounded-md text-text-primary hover:bg-surface-secondary dark:text-text-primary-dark dark:hover:bg-surface-secondary-dark"
          >
            <svg
              width="20"
              height="20"
              viewBox="0 0 20 20"
              fill="none"
              stroke="currentColor"
              strokeWidth="2"
              strokeLinecap="round"
              aria-hidden
            >
              <path d="M2 5h16M2 10h16M2 15h16" />
            </svg>
          </button>
          <span className="font-heading text-base font-semibold text-primary dark:text-primary-dark">
            De-Duke Admin
          </span>
        </div>

        <main className="min-w-0 flex-1 overflow-y-auto p-md sm:p-lg">
          {children}
        </main>
      </div>
    </div>
  );
}
