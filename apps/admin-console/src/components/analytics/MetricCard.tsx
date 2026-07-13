"use client";

import { Children, cloneElement, isValidElement, useState } from "react";
import type { ReactElement, ReactNode } from "react";

/** Reusable metric card for both dashboards (screens.md Screens 29/30's
 * "Grid of metric Cards"). `href`, when given, makes the whole card a
 * drill-through link into the relevant underlying queue/screen.
 *
 * `index`, when given, drives the dashboard-grid stagger (branding.md
 * Admin Web Console motion table's "Dashboard-specific" note): cards
 * fade + slide up in a cascading stagger (~200ms per card, 25ms offset)
 * via `animate-stagger-in` + an inline `animationDelay`. Callers should
 * key the surrounding grid on the selected range so this re-triggers on
 * date-range change. */
export function MetricCard({
  label,
  value,
  sublabel,
  href,
  index,
}: {
  label: string;
  value: ReactNode;
  sublabel?: string;
  href?: string;
  index?: number;
}) {
  const [leaving, setLeaving] = useState(false);
  const style = index !== undefined ? { animationDelay: `${index * 25}ms` } : undefined;
  const staggerClass = index !== undefined ? "animate-stagger-in" : "";

  const content = (
    <div className={`rounded-md border border-border p-md dark:border-border-dark ${staggerClass}`} style={style}>
      <p className="text-sm text-text-secondary">{label}</p>
      <p className="mt-xs text-2xl font-semibold">{value}</p>
      {sublabel && <p className="mt-xs text-xs text-text-secondary">{sublabel}</p>}
    </div>
  );

  if (!href) return content;

  // `drill-through-transition` (branding.md): a 200ms ease-in-out-smooth
  // crossfade before navigating into the underlying queue, so the
  // transition reads as a content swap rather than a hard route change.
  return (
    <a
      href={href}
      className={`block transition-opacity duration-200 ease-in-out-smooth hover:opacity-80 ${
        leaving ? "opacity-0" : "opacity-100"
      }`}
      onClick={(event) => {
        if (leaving) return;
        event.preventDefault();
        setLeaving(true);
        window.setTimeout(() => {
          window.location.href = href;
        }, 200);
      }}
    >
      {content}
    </a>
  );
}

export function CardSection({
  title,
  children,
  startIndex = 0,
}: {
  title: string;
  children: ReactNode;
  /** Base offset into the page-wide stagger sequence, so later sections
   * continue the cascade rather than each restarting at card 0. */
  startIndex?: number;
}) {
  const items = Children.toArray(children);
  return (
    <section className="mt-lg">
      <h2 className="font-heading text-sm font-semibold uppercase tracking-wide text-text-secondary">
        {title}
      </h2>
      <div className="mt-sm grid grid-cols-1 gap-md sm:grid-cols-2 lg:grid-cols-3">
        {items.map((child, i) =>
          isValidElement(child)
            ? cloneElement(child as ReactElement<{ index?: number }>, { index: startIndex + i })
            : child,
        )}
      </div>
    </section>
  );
}
