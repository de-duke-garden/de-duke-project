import type { NextConfig } from "next";

// Hybrid build: the site's content pages (Home, About, Legal, and the
// payment-complete fallback) remain statically generated and CDN-served --
// but NOT output: "export". FEAT-020's Shareable Summary view
// (/s/[token]) is a dynamic, server-rendered route (it fetches the public
// /v1/share/:token endpoint server-side per product direction), which is
// impossible under output: "export" (that mode forbids dynamic routes with
// unbounded params). Without the export flag, Vercel still pre-renders
// every static page and only runs a server function for the dynamic
// /s/[token] route. This is a deliberate, documented deviation from
// architecture.md's original "statically-generated (SSG export)" wording --
// the site keeps zero backend dependency for its content pages; only the
// share page needs a function.
const nextConfig: NextConfig = {
  reactStrictMode: true,
};

export default nextConfig;
