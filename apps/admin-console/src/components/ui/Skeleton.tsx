/**
 * `table-skeleton` (branding.md Admin Web Console motion table): every
 * Table/Grid replaces the bare centered spinner on initial load with
 * shimmering skeleton rows/cards matching real row height and column
 * widths, rather than a generic spinner -- reduces perceived latency for
 * staff re-loading dense queues dozens of times per shift.
 */

/** Skeleton rows sized to a `<table>` with the given column count. */
export function TableSkeleton({ rows = 6, columns = 5 }: { rows?: number; columns?: number }) {
  return (
    <table className="w-full border-collapse text-sm">
      <tbody>
        {Array.from({ length: rows }).map((_, rowIndex) => (
          <tr key={rowIndex} className="border-b border-border dark:border-border-dark">
            {Array.from({ length: columns }).map((_, colIndex) => (
              <td key={colIndex} className="py-sm pr-md">
                <div className="skeleton-shimmer animate-shimmer h-4 rounded-sm" style={{ width: `${70 - colIndex * 8}%` }} />
              </td>
            ))}
          </tr>
        ))}
      </tbody>
    </table>
  );
}

/** Skeleton cards sized to a metric-card / rate-card grid. */
export function CardGridSkeleton({ count = 6 }: { count?: number }) {
  return (
    <div className="grid grid-cols-1 gap-md sm:grid-cols-2 lg:grid-cols-3">
      {Array.from({ length: count }).map((_, i) => (
        <div key={i} className="rounded-md border border-border p-md dark:border-border-dark">
          <div className="skeleton-shimmer animate-shimmer h-3 w-1/2 rounded-sm" />
          <div className="skeleton-shimmer animate-shimmer mt-sm h-6 w-1/3 rounded-sm" />
        </div>
      ))}
    </div>
  );
}
