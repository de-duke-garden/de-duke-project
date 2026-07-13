"use client";

import { useEffect, useRef, useState } from "react";

type Tone = "primary" | "success" | "warning" | "error" | "info" | "neutral";

const TONE_CLASSES: Record<Tone, string> = {
  primary: "bg-primary-light text-primary dark:bg-primary-light-dark dark:text-primary-dark",
  success: "bg-success/15 text-success",
  warning: "bg-warning/15 text-warning",
  error: "bg-error/15 text-error",
  info: "bg-info/15 text-info",
  neutral: "bg-surface-secondary text-text-secondary dark:bg-surface-secondary-dark",
};

/**
 * `status-badge-pop` (branding.md Admin Web Console motion table): a
 * status badge/pill briefly highlights with a flash-then-settle when its
 * `value` changes, drawing the eye to what changed in a dense table
 * without needing a toast for every field. Single, minimal settle only --
 * no spring/overshoot on this surface.
 */
export function StatusBadge({
  value,
  label,
  tone = "neutral",
}: {
  value: string;
  label: string;
  tone?: Tone;
}) {
  const previousValue = useRef(value);
  const [popping, setPopping] = useState(false);

  useEffect(() => {
    if (previousValue.current !== value) {
      previousValue.current = value;
      setPopping(true);
      const timeout = setTimeout(() => setPopping(false), 260);
      return () => clearTimeout(timeout);
    }
  }, [value]);

  return (
    <span
      className={`inline-flex items-center rounded-full px-sm py-1 text-xs font-medium capitalize ${TONE_CLASSES[tone]} ${
        popping ? "animate-badge-pop" : ""
      }`}
    >
      {label}
    </span>
  );
}
