import Link from "next/link";

import type { AdminSession } from "@/lib/auth";

import { LogoutButton } from "./LogoutButton";

const STAFF_LINKS = [
  { href: "/", label: "Home" },
  { href: "/moderation-queue", label: "Moderation Queue" },
  { href: "/host-verification", label: "Host Verification" },
  { href: "/conversations", label: "Conversations" },
];

const ADMIN_ONLY_LINKS = [
  { href: "/commission-config", label: "Commission Config" },
  { href: "/staff-management", label: "Staff Management" },
];

export function AdminNav({ session }: { session: AdminSession }) {
  const links =
    session.role === "deduke_admin" ? [...STAFF_LINKS, ...ADMIN_ONLY_LINKS] : STAFF_LINKS;

  return (
    <header className="border-b border-border bg-surface dark:border-border-dark dark:bg-surface-dark">
      <div className="flex items-center justify-between p-md">
        <nav className="flex flex-wrap gap-md">
          {links.map((link) => (
            <Link
              key={link.href}
              href={link.href}
              className="text-sm font-medium text-text-secondary hover:text-primary dark:text-text-secondary-dark"
            >
              {link.label}
            </Link>
          ))}
        </nav>
        <div className="flex items-center gap-sm">
          <span className="text-sm text-text-secondary dark:text-text-secondary-dark">
            {session.fullName} ({session.role === "deduke_admin" ? "Admin" : "Staff"})
          </span>
          <LogoutButton />
        </div>
      </div>
    </header>
  );
}
