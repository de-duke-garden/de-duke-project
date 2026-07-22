"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { useLayoutEffect, useRef, useState } from "react";

import type { AdminSession } from "@/lib/auth";

import { LogoutButton } from "./LogoutButton";

const STAFF_LINKS = [
  { href: "/", label: "Home" },
  { href: "/properties", label: "Properties" },
  { href: "/moderation-queue", label: "Moderation Queue" },
  { href: "/disputes", label: "Disputes" },
  { href: "/host-verification", label: "Host Verification" },
  { href: "/conversations", label: "Conversations" },
  { href: "/support", label: "Support" },
  { href: "/analytics/operations", label: "Operations" },
];

const ADMIN_ONLY_LINKS = [
  { href: "/commission-config", label: "Commission Config" },
  { href: "/release-funds", label: "Release Funds" },
  { href: "/staff-management", label: "Staff Management" },
  { href: "/analytics/business", label: "Business & Revenue" },
];

/**
 * Admin Web Console primary navigation -- branding.md specifies this
 * surface uses its own `Sidebar` component vocabulary (not the mobile
 * app's bottom nav / AppBar), which is also the structural fix for a
 * 10-link nav: a flat horizontal header wraps/overflows once every
 * Staff + Admin-only link is present, whereas a vertical sidebar has
 * room to list all of them legibly regardless of link count or viewport
 * width.
 *
 * `sidebar-active-indicator` (branding.md Admin Web Console motion
 * table, 180ms `ease-out-smooth`): a left-edge bar in `primary` slides
 * to the active route rather than jumping, giving persistent wayfinding
 * continuity as staff move between modules.
 *
 * Layout: `h-full` + `flex flex-col` so this stretches to exactly the
 * shell's viewport-bounded height (see AdminShell.tsx) with the link
 * list (`<nav>`) as the only flexible/scrollable region -- the header and
 * footer stay put, and the link list gets its own scrollbar rather than
 * overflowing the sidebar on a short viewport (e.g. a laptop in a
 * half-height window) once Staff + Admin-only links are all present.
 *
 * Responsive: below the `md` breakpoint this becomes an off-canvas drawer
 * (fixed position, slid off-screen via `-translate-x-full` until
 * `mobileOpen`), toggled by AdminShell's mobile top-bar hamburger button.
 * At `md` and above it reverts to `md:static md:translate-x-0` -- always
 * visible, part of the normal flex layout, exactly as before.
 */
export function AdminNav({
  session,
  mobileOpen,
  onCloseMobile,
}: {
  session: AdminSession;
  mobileOpen: boolean;
  onCloseMobile: () => void;
}) {
  const links =
    session.role === "deduke_admin"
      ? [...STAFF_LINKS, ...ADMIN_ONLY_LINKS]
      : STAFF_LINKS;
  const pathname = usePathname();

  const navRef = useRef<HTMLElement>(null);
  const [indicator, setIndicator] = useState<{
    top: number;
    height: number;
  } | null>(null);

  useLayoutEffect(() => {
    const activeEl = navRef.current?.querySelector<HTMLElement>(
      '[data-active="true"]',
    );
    if (activeEl) {
      setIndicator({ top: activeEl.offsetTop, height: activeEl.offsetHeight });
    }
  }, [pathname, links.length]);

  return (
    <>
      {/* Backdrop -- mobile drawer only, dismisses on tap outside. */}
      {mobileOpen && (
        <div
          aria-hidden
          onClick={onCloseMobile}
          className="fixed inset-0 z-30 animate-backdrop-enter bg-black/40 md:hidden"
        />
      )}

      <aside
        className={`fixed inset-y-0 left-0 z-40 flex h-full w-64 shrink-0 flex-col border-r border-border bg-surface transition-transform duration-200 ease-out-smooth md:static md:translate-x-0 dark:border-border-dark dark:bg-surface-dark ${
          mobileOpen ? "translate-x-0" : "-translate-x-full"
        }`}
      >
        <div className="flex items-start justify-between p-md">
          <div className="flex items-center gap-sm">
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img src="/logo.png" alt="" className="h-8 w-8" />
            <div>
              <span className="font-heading text-lg font-bold text-primary dark:text-primary-dark">
                De-Duke
              </span>
              <p className="mt-xs text-xs text-text-secondary dark:text-text-secondary-dark">
                Admin Console
              </p>
            </div>
          </div>
          <button
            type="button"
            onClick={onCloseMobile}
            aria-label="Close navigation"
            className="flex h-12 w-12 shrink-0 items-center justify-center rounded-md text-text-secondary hover:bg-surface-secondary hover:text-text-primary md:hidden dark:text-text-secondary-dark dark:hover:bg-surface-secondary-dark dark:hover:text-text-primary-dark"
          >
            <svg
              width="16"
              height="16"
              viewBox="0 0 16 16"
              fill="none"
              stroke="currentColor"
              strokeWidth="2"
              strokeLinecap="round"
              aria-hidden
            >
              <path d="M2 2l12 12M14 2L2 14" />
            </svg>
          </button>
        </div>

        <nav
          ref={navRef}
          className="relative min-h-0 flex-1 space-y-xs overflow-y-auto px-sm"
        >
          {indicator && (
            <span
              aria-hidden
              className="absolute left-0 w-[3px] rounded-full bg-primary transition-[top,height] duration-[180ms] ease-out-smooth dark:bg-primary-dark"
              style={{ top: indicator.top, height: indicator.height }}
            />
          )}
          {links.map((link) => {
            const isActive =
              link.href === "/"
                ? pathname === "/"
                : pathname.startsWith(link.href);
            return (
              <Link
                key={link.href}
                href={link.href}
                data-active={isActive}
                onClick={onCloseMobile}
                className={`block rounded-md px-sm py-sm text-sm font-medium transition-colors duration-150 ease-out-smooth ${
                  isActive
                    ? "bg-primary-light text-primary dark:bg-primary-light-dark dark:text-primary-dark"
                    : "text-text-secondary hover:bg-surface-secondary hover:text-text-primary dark:text-text-secondary-dark dark:hover:bg-surface-secondary-dark dark:hover:text-text-primary-dark"
                }`}
              >
                {link.label}
              </Link>
            );
          })}
        </nav>

        <div className="shrink-0 border-t border-border p-md dark:border-border-dark">
          <p className="truncate text-sm text-text-secondary dark:text-text-secondary-dark">
            {session.fullName}
          </p>
          <p className="mb-sm text-xs text-text-secondary dark:text-text-secondary-dark">
            {session.role === "deduke_admin" ? "Admin" : "Staff"}
          </p>
          {/* Screen 31b (FEAT-041): self-service account management --
              deliberately here in the account-footer area, not the main
              module link list above, since it's an account-level concern
              (own profile/password) rather than an operational module.
              There is no separate Navbar component in this console yet
              (see AdminNav's own docstring), so this footer is the
              closest structural equivalent to "reachable from the Navbar,
              not the Sidebar" from screens.md. */}
          <Link
            href="/my-account"
            data-active={pathname === "/my-account"}
            onClick={onCloseMobile}
            className={`mb-sm block rounded-md px-sm py-xs text-sm font-medium transition-colors duration-150 ease-out-smooth ${
              pathname === "/my-account"
                ? "bg-primary-light text-primary dark:bg-primary-light-dark dark:text-primary-dark"
                : "text-text-secondary hover:bg-surface-secondary hover:text-text-primary dark:text-text-secondary-dark dark:hover:bg-surface-secondary-dark dark:hover:text-text-primary-dark"
            }`}
          >
            My Account
          </Link>
          <LogoutButton />
        </div>
      </aside>
    </>
  );
}
