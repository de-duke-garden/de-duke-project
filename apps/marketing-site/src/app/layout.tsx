import type { Metadata } from "next";
import "../styles/globals.css";

export const metadata: Metadata = {
  title: "De-Duke",
  description: "Verified property. Real conversations. Deals that close.",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
