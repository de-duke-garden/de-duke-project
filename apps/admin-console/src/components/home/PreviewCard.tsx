"use client";

import type { ReactNode } from "react";

interface Metric {
  label: string;
  value: ReactNode;
}

/**
 * Operations / Business & Revenue preview card on the Admin Home /
 * Overview screen (screens.md Screen 22) -- a 1-2 headline metric compact
 * preview of the full analytics dashboard it links to.
 */
export function PreviewCard<T>({
  title,
  href,
  state,
  renderMetrics,
  index,
}: {
  title: string;
  href: string;
  state: T | "error" | null;
  renderMetrics: (data: T) => Metric[];
  index: number;
}) {
  const staggerStyle = { animationDelay: `${index * 25}ms` };

  if (state === "error") {
    return (
      <div
        className="animate-stagger-in rounded-md border border-border p-md dark:border-border-dark"
        style={staggerStyle}
      >
        <p className="text-sm text-text-secondary">{title}</p>
        <p className="mt-xs text-sm text-error">Couldn&apos;t load</p>
      </div>
    );
  }

  const metrics = state === null ? [] : renderMetrics(state);

  return (
    <a
      href={href}
      className="animate-stagger-in block rounded-md border border-border p-md transition-colors duration-150 ease-out-smooth hover:bg-surface-secondary dark:border-border-dark dark:hover:bg-surface-secondary-dark"
      style={staggerStyle}
    >
      <p className="text-sm text-text-secondary">{title}</p>
      <div className="mt-xs space-y-xs">
        {metrics.map((metric) => (
          <div key={metric.label} className="flex items-baseline justify-between gap-sm">
            <span className="text-xs text-text-secondary">{metric.label}</span>
            <span className="text-lg font-semibold">{metric.value}</span>
          </div>
        ))}
      </div>
    </a>
  );
}
