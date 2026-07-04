"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";

export function LogoutButton() {
  const router = useRouter();
  const [loading, setLoading] = useState(false);

  async function handleLogout() {
    setLoading(true);
    await fetch("/api/session", { method: "DELETE" });
    router.replace("/login");
    router.refresh();
  }

  return (
    <button
      onClick={handleLogout}
      disabled={loading}
      className="rounded-md px-sm py-xs text-sm text-text-secondary hover:text-text-primary disabled:opacity-60 dark:text-text-secondary-dark dark:hover:text-text-primary-dark"
    >
      {loading ? "Signing out..." : "Sign out"}
    </button>
  );
}
