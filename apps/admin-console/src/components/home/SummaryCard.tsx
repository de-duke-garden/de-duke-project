"use client";

import { StatusBadge } from "@/components/ui/StatusBadge";

/**
 * One module's summary card on the Admin Home / Overview screen
 * (screens.md Screen 22). Renders independently of every other card's
 * load state -- a `value` of `"error"` shows an inline "Couldn't load" +
 * retry rather than failing the whole grid (Partial Load state); a
 * `value` of `0` shows the calm `allClearLabel` rather than a bare "0"
 * (Empty/All Clear state).
 */
export function SummaryCard({
  title,
  href,
  value,
  allClearLabel,
  countLabel,
  index,
  onRetry,
}: {
  title: string;
  href: string;
  value: number | "error" | null;
  allClearLabel: string;
  countLabel: (count: number) => string;
  index: number;
  onRetry?: () => void;
}) {
  const staggerStyle = { animationDelay: `${index * 25}ms` };

  if (value === "error") {
    return (
      <div
        className="animate-stagger-in rounded-md border border-border p-md dark:border-border-dark"
        style={staggerStyle}
      >
        <p className="text-sm text-text-secondary">{title}</p>
        <div className="mt-xs flex items-center gap-sm">
          <p className="text-sm text-error">Couldn&apos;t load</p>
          {onRetry && (
            <button
              type="button"
              onClick={onRetry}
              aria-label={`Retry loading ${title}`}
              className="text-sm text-primary underline"
            >
              Retry
            </button>
          )}
        </div>
      </div>
    );
  }

  const isAllClear = value === 0;

  return (
    <a
      href={href}
      className="animate-stagger-in block rounded-md border border-border p-md transition-colors duration-150 ease-out-smooth hover:bg-surface-secondary dark:border-border-dark dark:hover:bg-surface-secondary-dark"
      style={staggerStyle}
    >
      <p className="text-sm text-text-secondary">{title}</p>
      <div className="mt-xs">
        {isAllClear ? (
          <StatusBadge value="all-clear" label={allClearLabel} tone="success" />
        ) : (
          <p className="text-2xl font-semibold">{value ?? "–"}</p>
        )}
      </div>
      {!isAllClear && value !== null && (
        <p className="mt-xs text-xs text-text-secondary">{countLabel(value)}</p>
      )}
    </a>
  );
}
