import { readFileSync, readdirSync } from "node:fs";
import { join } from "node:path";

/**
 * Screens 33 & 34 -- "Content Format: Markdown" (see docs/De-Duke/screens.md).
 * The Legal & Policy pages are content-authored, not layout-authored: their
 * text lives in plain `.md` files under this app's own `content/legal/`
 * directory (copied once from `docs/De-Duke/content/`, the authoring
 * source a copywriter/counsel edits). There is no frontmatter and no
 * embedded components -- title, effective date, and version are expressed
 * as plain-Markdown conventions (a leading `# Title` heading, and
 * `**Effective Date:** ...` / `**Version:** ...` lines), per the current
 * drafted files. This module is the single place that reads those files
 * off disk and pulls out the couple of values the page shell needs
 * (`<title>` metadata, the sticky table of contents) -- the documents
 * themselves are rendered by a standard MDX renderer with no custom
 * components (see LegalDocument.tsx).
 *
 * The About page (Screen 33) is intentionally NOT read through this
 * module -- per FEAT-038 it's a hand-authored HTML/CSS page, not parsed
 * from Markdown at render time.
 */

const CONTENT_ROOT = join(process.cwd(), "content");

/** The three published legal document slugs, per Screen 34's `/legal/:document` route. */
export const LEGAL_DOCUMENT_SLUGS = ["privacy-policy", "terms-of-service", "payment-terms"] as const;
export type LegalDocumentSlug = (typeof LEGAL_DOCUMENT_SLUGS)[number];

export function isLegalDocumentSlug(value: string): value is LegalDocumentSlug {
  return (LEGAL_DOCUMENT_SLUGS as readonly string[]).includes(value);
}

export interface LegalDocument {
  /** The full raw Markdown file contents, passed as-is to the MDX renderer. */
  raw: string;
  title: string;
  effectiveDate: string | null;
  version: string | null;
}

/** Loads and lightly parses `content/legal/<slug>.md` (Screen 34). Returns `null` if missing. */
export function getLegalContent(slug: LegalDocumentSlug): LegalDocument | null {
  const filePath = join(CONTENT_ROOT, "legal", `${slug}.md`);
  let raw: string;
  try {
    raw = readFileSync(filePath, "utf-8");
  } catch {
    return null;
  }

  const titleMatch = raw.match(/^#\s+(.+)$/m);
  const effectiveDateMatch = raw.match(/^\*\*Effective Date:\*\*\s*(.+)$/m);
  const versionMatch = raw.match(/^\*\*Version:\*\*\s*(.+)$/m);

  return {
    raw,
    title: titleMatch?.[1]?.trim() ?? slug,
    effectiveDate: effectiveDateMatch?.[1]?.trim() ?? null,
    version: versionMatch?.[1]?.trim() ?? null,
  };
}

/**
 * Prior versions of a legal document, per Screen 34's "Version History" edge
 * case -- read from `content/legal/history/<slug>/*.md` if that directory
 * exists. Returns an empty array (not an error) when no history has been
 * archived yet, which is the expected state until the first counsel-approved
 * revision.
 */
export function getLegalHistory(slug: LegalDocumentSlug): LegalDocument[] {
  const historyDir = join(CONTENT_ROOT, "legal", "history", slug);
  let files: string[];
  try {
    files = readdirSync(historyDir).filter((f) => f.endsWith(".md"));
  } catch {
    return [];
  }
  return files
    .map((file) => {
      const raw = readFileSync(join(historyDir, file), "utf-8");
      const titleMatch = raw.match(/^#\s+(.+)$/m);
      const effectiveDateMatch = raw.match(/^\*\*Effective Date:\*\*\s*(.+)$/m);
      const versionMatch = raw.match(/^\*\*Version:\*\*\s*(.+)$/m);
      return {
        raw,
        title: titleMatch?.[1]?.trim() ?? slug,
        effectiveDate: effectiveDateMatch?.[1]?.trim() ?? null,
        version: versionMatch?.[1]?.trim() ?? null,
      };
    })
    .sort((a, b) => Number(b.version ?? 0) - Number(a.version ?? 0));
}
