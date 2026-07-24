// Screen 34 -- Marketing: Legal & Policy Pages (FEAT-037).
// Content-authored per screens.md's "Content Format: Markdown (Screens 33 & 34)"
// -- the actual payment terms text lives in `content/legal/payment-terms.md`
// (plain Markdown, no frontmatter), not in this file. See
// src/components/content/LegalDocument.tsx for the shared shell (table of
// contents, standard MDX rendering, typography) all three legal routes use.
import { Metadata } from "next";
import { LegalDocument } from "@/components/content/LegalDocument";
import { getLegalContent } from "@/lib/content";

const doc = getLegalContent("payment-terms");

export const metadata: Metadata = {
  title: `${doc?.title ?? "Payment Terms"} — De-Duke`,
};

export default function PaymentTermsPage() {
  return <LegalDocument slug="payment-terms" />;
}
