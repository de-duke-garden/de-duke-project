import { AnchorHTMLAttributes } from "react";
import styles from "./Button.module.css";

type Variant = "primary" | "secondary" | "outline";

/** Shared CTA button per branding.md Component Tokens > Buttons. Rendered
 * as an anchor (every marketing CTA either scrolls, links internally, or
 * routes to a store) rather than a form-submit `<button>`. */
export function Button({
  variant = "primary",
  className = "",
  ...rest
}: { variant?: Variant } & AnchorHTMLAttributes<HTMLAnchorElement>) {
  return <a className={`${styles.button} ${styles[variant]} ${className}`} {...rest} />;
}
