import Link from "next/link";
import { MDXRemote } from "next-mdx-remote/rsc";
import rehypeSlug from "rehype-slug";
import remarkGfm from "remark-gfm";
import GithubSlugger from "github-slugger";
import { Navbar } from "@/components/Navbar";
import { Footer } from "@/components/Footer";
import {
  getLegalContent,
  getLegalHistory,
  LEGAL_DOCUMENT_SLUGS,
  type LegalDocumentSlug,
} from "@/lib/content";
import styles from "./LegalDocument.module.css";

/**
 * Standard MDX (unlike plain Markdown) parses `<` as the start of JSX, so
 * the `<!-- ... -->` HTML comments used for internal drafting notes (per
 * the plain-Markdown convention documented in screens.md) fail to compile.
 * Since these comments are explicitly "invisible when rendered" content,
 * stripping them before compilation preserves that intent exactly while
 * still using a standard, unmodified MDX renderer for everything else.
 */
function stripHtmlComments(source: string): string {
  return source.replace(/<!--[\s\S]*?-->/g, "");
}

/** `## Heading` lines from the raw Markdown source, in document order --
 * the source for the sticky table-of-contents (Screen 34's "Table of
 * contents" component: "Generated from document headings"). Slugged the
 * same way `rehype-slug` slugs the rendered headings, so the anchor links
 * line up. */
function extractHeadings(source: string): { text: string; slug: string }[] {
  const slugger = new GithubSlugger();
  const headingLines = source.match(/^## .+$/gm) ?? [];
  return headingLines.map((line) => {
    const text = line.replace(/^## /, "").trim();
    return { text, slug: slugger.slug(text) };
  });
}

/**
 * Screen 34 -- Marketing: Legal & Policy Pages (FEAT-037). Shared shell for
 * all three legal documents (`/legal/privacy-policy`, `/legal/terms-of-service`,
 * `/legal/payment-terms`): sticky in-page table of contents and plain,
 * high-contrast, print-friendly typography -- "Document Mode," the least
 * cinematic screen on the site, per screens.md.
 *
 * Content is authored as plain Markdown -- no frontmatter, no embedded
 * components -- and rendered here with a standard MDX renderer
 * (`next-mdx-remote/rsc` + `remark-gfm` for the documents' tables). The
 * title, effective date, and version conventions (`# Title`,
 * `**Effective Date:** ...`, `**Version:** ...`) render as ordinary
 * Markdown -- there's nothing content-specific for this shell to extract
 * or special-case beyond generating the table of contents.
 */
export function LegalDocument({ slug }: { slug: LegalDocumentSlug }) {
  const doc = getLegalContent(slug);

  // Error state (Screen 34): document fails to load -- rare given static
  // hosting, but the content file could be missing/malformed. Simple
  // message, a link home, and a direct-contact fallback.
  if (!doc) {
    return (
      <>
        <Navbar />
        <main className={styles.errorMain}>
          <h1>We couldn&apos;t load this document</h1>
          <p>
            Something went wrong loading this page. Try again, or reach us directly at{" "}
            <a href="mailto:support@de-duke.com">support@de-duke.com</a>.
          </p>
          <p>
            <Link href="/">Back to De-Duke home</Link>
          </p>
        </main>
        <Footer />
      </>
    );
  }

  const headings = extractHeadings(doc.raw);
  const history = getLegalHistory(slug);
  const otherSlugs = LEGAL_DOCUMENT_SLUGS.filter((s) => s !== slug);

  return (
    <>
      <Navbar />
      <div className={styles.layout}>
        <nav className={styles.toc} aria-label="Table of contents">
          <p className={styles.tocTitle}>On this page</p>
          <ul className={styles.tocList}>
            {headings.map((heading) => (
              <li key={heading.slug}>
                <a href={`#${heading.slug}`}>{heading.text}</a>
              </li>
            ))}
          </ul>
        </nav>
        <main className={styles.document}>
          <p className={styles.eyebrow}>Legal &amp; Policy</p>
          <div className={styles.body}>
            <MDXRemote
              source={stripHtmlComments(doc.raw)}
              options={{ mdxOptions: { remarkPlugins: [remarkGfm], rehypePlugins: [rehypeSlug] } }}
            />
          </div>

          {history.length > 0 && (
            <p className={styles.versionHistory}>
              Version history:{" "}
              {history.map((entry, i) => (
                <span key={entry.version}>
                  {i > 0 && ", "}
                  v{entry.version} ({entry.effectiveDate})
                </span>
              ))}
            </p>
          )}

          <p className={styles.versionHistory}>
            Other legal documents:{" "}
            {otherSlugs.map((s, i) => (
              <span key={s}>
                {i > 0 && " · "}
                <Link href={`/legal/${s}`}>{documentLabel(s)}</Link>
              </span>
            ))}
          </p>
        </main>
      </div>
      <Footer />
    </>
  );
}

function documentLabel(slug: LegalDocumentSlug): string {
  switch (slug) {
    case "privacy-policy":
      return "Privacy Policy";
    case "terms-of-service":
      return "Terms of Service";
    case "payment-terms":
      return "Payment Terms";
  }
}
