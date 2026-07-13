"use client";

import { useState } from "react";
import type { ReactNode } from "react";

/**
 * `row-resolve` (branding.md Admin Web Console motion table): a queue row
 * fades + collapses out of the table the moment its action succeeds
 * (Approve/Ban/Verify/Reject/Resolve), rather than a full-table re-fetch
 * flash -- gives staff instant, satisfying per-action confirmation across
 * dozens of actions per shift.
 *
 * Usage: wrap each `<tr>` in `<ResolvingRow resolving={id === resolvingId}>`.
 * Callers should delay removing the item from their list state until
 * `onResolved` fires (260ms later), so the row is still mounted while the
 * exit animation plays.
 */
export function ResolvingRow({
  resolving,
  onResolved,
  children,
  className = "",
}: {
  resolving: boolean;
  onResolved?: () => void;
  children: ReactNode;
  className?: string;
}) {
  const [animating, setAnimating] = useState(false);

  if (resolving && !animating) {
    setAnimating(true);
    setTimeout(() => onResolved?.(), 260);
  }

  return (
    <tr
      className={`${className} ${resolving ? "animate-row-resolve overflow-hidden" : ""}`}
    >
      {children}
    </tr>
  );
}
