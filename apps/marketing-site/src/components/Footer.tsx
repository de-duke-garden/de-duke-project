import Link from "next/link";
import styles from "./Footer.module.css";

/**
 * Screen 32 section 9 -- "Footer — Legal & Contact". Links to Legal &
 * Policy pages (FEAT-037), About/Product Information (FEAT-038), and
 * contact channels, per FEAT-036's acceptance criteria. Static, no motion
 * beyond standard link hover states, per website-design-patterns.md.
 */
export function Footer() {
  return (
    <footer className={styles.footer}>
      <div className={styles.columns}>
        <div className={styles.column}>
          <span className={styles.columnTitle}>Product</span>
          <Link href="/">Home</Link>
          <Link href="/about">About De-Duke</Link>
        </div>
        <div className={styles.column}>
          <span className={styles.columnTitle}>Legal</span>
          <Link href="/legal/privacy-policy">Privacy Policy</Link>
          <Link href="/legal/terms-of-service">Terms of Service</Link>
          <Link href="/legal/payment-terms">Payment Terms</Link>
        </div>
        <div className={styles.column}>
          <span className={styles.columnTitle}>Contact</span>
          <a href="mailto:hello@de-duke.com">hello@de-duke.com</a>
        </div>
      </div>
      <p className={styles.legal}>© {new Date().getFullYear()} De-Duke. All rights reserved.</p>
    </footer>
  );
}
