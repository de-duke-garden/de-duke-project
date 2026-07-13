// screens.md Screen 22: Admin -- Home / Overview.

/** One summary card's resolved state. Each card resolves independently --
 * a slow/failed query on one module must never block the others
 * (screens.md Screen 22 Data Flow step 2 / Partial Load state). */
export type SummaryCardState =
  | { status: "loading" }
  | { status: "loaded"; count: number }
  | { status: "error" };

export interface SummaryCardSpec {
  /** Stable key, also used as the React list key. */
  key: string;
  title: string;
  href: string;
  /** Copy shown when count === 0 (screens.md "Empty (All Clear)" state) --
   * a calm affirmation instead of a bare "0". */
  allClearLabel: string;
  /** Singular/plural label builder for a non-zero count. */
  countLabel: (count: number) => string;
}
