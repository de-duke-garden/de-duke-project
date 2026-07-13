"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { useLayoutEffect, useRef, useState } from "react";

import type { AdminSession } from "@/lib/auth";

import { LogoutButton } from "./LogoutButton";

const STAFF_LINKS = [
  { href: "/", label: "Home" },
  { href: "/moderation-queue", label: "Moderation Queue" },
  { href: "/disputes", label: "Disputes" },
  { href: "/host-verification", label: "Host Verification" },
  { href: "/conversations", label: "Conversations" },
  { href: "/support", label: "Support" },
  { href: "/analytics/operations", label: "Operations" },
];

const ADMIN_ONLY_LINKS = [
  { href: "/commission-config", label: "Commission Config" },
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
 */
export function AdminNav({ session }: { session: AdminSession }) {
  const links =
    session.role === "deduke_admin" ? [...STAFF_LINKS, ...ADMIN_ONLY_LINKS] : STAFF_LINKS;
  const pathname = usePathname();

  const navRef = useRef<HTMLElement>(null);
  const [indicator, setIndicator] = useState<{ top: number; height: number } | null>(null);

  useLayoutEffect(() => {
    const activeEl = navRef.current?.querySelector<HTMLElement>('[data-active="true"]');
    if (activeEl) {
      setIndicator({ top: activeEl.offsetTop, height: activeEl.offsetHeight });
    }
  }, [pathname, links.length]);

  return (
    <aside className="flex w-64 shrink-0 flex-col border-r border-border bg-surface dark:border-border-dark dark:bg-surface-dark">
      <div className="p-md">
        <span className="font-heading text-lg font-bold text-primary dark:text-primary-dark">
          De-Duke
        </span>
        <p className="mt-xs text-xs text-text-secondary dark:text-text-secondary-dark">
          Admin Console
        </p>
      </div>

      <nav ref={navRef} className="relative flex-1 space-y-xs overflow-y-auto px-sm">
        {indicator && (
          <span
            aria-hidden
            className="absolute left-0 w-[3px] rounded-full bg-primary transition-[top,height] duration-[180ms] ease-out-smooth dark:bg-primary-dark"
            style={{ top: indicator.top, height: indicator.height }}
          />
        )}
        {links.map((link) => {
          const isActive = link.href === "/" ? pathname === "/" : pathname.startsWith(link.href);
          return (
            <Link
              key={link.href}
              href={link.href}
              data-active={isActive}
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

      <div className="border-t border-border p-md dark:border-border-dark">
        <p className="truncate text-sm text-text-secondary dark:text-text-secondary-dark">
          {session.fullName}
        </p>
        <p className="mb-sm text-xs text-text-secondary dark:text-text-secondary-dark">
          {session.role === "deduke_admin" ? "Admin" : "Staff"}
        </p>
        <LogoutButton />
      </div>
    </aside>
  );
}
