import type { NextConfig } from "next";

// Statically-generated, CDN-served -- output: "export" per architecture.md
// (SSG, zero backend dependency, own deploy target).
const nextConfig: NextConfig = {
  output: "export",
  reactStrictMode: true,
};

export default nextConfig;
