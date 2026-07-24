// Screen 33 -- Marketing: Product / About (FEAT-038). Deliberately the
// calmest, least motion-heavy section of the site besides Legal & Policy
// (per website-design-patterns.md): a simple server-rendered content page,
// no client-side motion libraries loaded at all.
//
// Per FEAT-038, this page is hand-authored HTML/CSS -- NOT parsed from
// Markdown at render time (unlike the Legal & Policy pages). Its copy is
// kept in sync by hand with `content/about/about.md` (the human-readable
// source of truth a copywriter edits/reviews), mirroring that file's
// belief-first structure: Belief statement -> Origin/Problem -> Mission ->
// How De-Duke Works (Guest/Host/Agency) -> Trust & Verification ->
// Download CTA. Visual treatment (card panels, icons, full-bleed closing
// CTA) borrows directly from the Home page's component patterns so the two
// pages read as one consistent site.
import { Metadata } from "next";
import { Navbar } from "@/components/Navbar";
import { Footer } from "@/components/Footer";
import { DownloadCTA } from "@/components/content/DownloadCTA";
import { SearchIcon, TagIcon, ListIcon, ShieldCheckIcon } from "@/components/icons";
import styles from "./page.module.css";

export const metadata: Metadata = {
  title: "About — De-Duke",
  description: "Why we built a property marketplace with fixed pricing and verified hosts.",
};

const howItWorks = [
  {
    icon: SearchIcon,
    title: "For Guests",
    body: "Search commercial and shortlet listings near you, see one fixed price with no back-and-forth, and message the host and De-Duke support together in a single three-way chat — before, during, and after your transaction.",
  },
  {
    icon: TagIcon,
    title: "For Hosts",
    body: "List your property as an Owner, Agent, Company, Lawyer, Architect, or Surveyor, each with its own verification path reviewed by De-Duke staff, and get paid securely through the platform once a sale, lease, or booking completes.",
  },
  {
    icon: ListIcon,
    title: "For Agencies",
    body: "Manage a full portfolio of listings, route leads across your team, and give your agency's professional credentials (CAC, NBA, ARCON, SURCON) a place to actually mean something to a guest deciding whether to trust you.",
  },
];

export default function AboutPage() {
  return (
    <>
      <Navbar />
      <main className={styles.main}>
        {/* Belief statement -- the page's visual and emotional lead, ahead
            of any feature description, per the Airbnb "lead-with-belief"
            pattern named in Screen 33's Competitive Pattern Analysis. */}
        <section className={styles.hero}>
          <p className={styles.eyebrow}>About De-Duke</p>
          <blockquote className={styles.belief}>
            Finding a home in Nigeria shouldn&apos;t mean haggling with a stranger and hoping
            they&apos;re real.
          </blockquote>
        </section>

        <div className={styles.container}>
          <section className={styles.origin}>
            <div className={styles.originBlock}>
              <h2 className={styles.sectionTitle}>The Problem</h2>
              <p className={styles.body}>
                Property in Nigeria — whether you&apos;re buying, leasing, or booking a shortlet —
                still runs on negotiation, unverifiable claims, and trust that lives off-platform, in
                a phone call or a WhatsApp thread nobody else can see. Prices move depending on
                who&apos;s asking. Verifying a host or an agent before you send money is mostly
                guesswork. And when something goes wrong mid-transaction, there&apos;s no one else in
                the conversation to turn to.
              </p>
              <p className={styles.body}>
                De-Duke exists to fix that, not with another listings feed, but with a different set
                of rules for how a property transaction happens.
              </p>
            </div>
            <div className={styles.originBlock}>
              <h2 className={styles.sectionTitle}>Our Mission</h2>
              <p className={styles.body}>
                We give every De-Duke listing — commercial or shortlet — one fixed, transparent
                price, and we put De-Duke&apos;s own staff directly into the conversation between
                guest and host, so support and dispute resolution never have to leave the platform.
              </p>
            </div>
          </section>

          <section className={styles.section}>
            <h2 className={styles.centeredTitle}>How De-Duke Works</h2>
            <div className={styles.columns}>
              {howItWorks.map(({ icon: Icon, title, body }) => (
                <div className={styles.panel} key={title}>
                  <Icon className={styles.panelIcon} />
                  <h3 className={styles.panelTitle}>{title}</h3>
                  <p className={styles.panelBody}>{body}</p>
                </div>
              ))}
            </div>
          </section>

          <section className={styles.section}>
            <div className={styles.trustPanel}>
              <ShieldCheckIcon className={styles.trustIcon} />
              <div>
                <h2 className={styles.sectionTitle}>Trust &amp; Verification</h2>
                <p className={styles.body}>
                  Every host on De-Duke is manually reviewed before their first listing goes live —
                  the documents required depend on whether they&apos;re an Owner, Agent, Company,
                  Lawyer, Architect, or Surveyor, so the level of scrutiny matches the level of risk.
                  This is reviewed by De-Duke staff, not an automated rubber stamp.
                </p>
              </div>
            </div>
          </section>
        </div>

        <DownloadCTA />
      </main>
      <Footer />
    </>
  );
}
