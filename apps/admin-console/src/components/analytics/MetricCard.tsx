import type { ReactNode } from "react";

/** Reusable metric card for both dashboards (screens.md Screens 29/30's
 * "Grid of metric Cards"). `href`, when given, makes the whole card a
 * drill-through link into the relevant underlying queue/screen. */
export function MetricCard({
  label,
  value,
  sublabel,
  href,
}: {
  label: string;
  value: ReactNode;
  sublabel?: string;
  href?: string;
}) {
  const content = (
    <div className="rounded-md border border-border p-md dark:border-border-dark">
      <p className="text-sm text-text-secondary">{label}</p>
      <p className="mt-xs text-2xl font-semibold">{value}</p>
      {sublabel && <p className="mt-xs text-xs text-text-secondary">{sublabel}</p>}
    </div>
  );

  if (!href) return content;

  return (
    <a href={href} className="block transition hover:opacity-80">
      {content}
    </a>
  );
}

export function CardSection({ title, children }: { title: string; children: ReactNode }) {
  return (
    <section className="mt-lg">
      <h2 className="font-heading text-sm font-semibold uppercase tracking-wide text-text-secondary">
        {title}
      </h2>
      <div className="mt-sm grid grid-cols-1 gap-md sm:grid-cols-2 lg:grid-cols-3">{children}</div>
    </section>
  );
}
