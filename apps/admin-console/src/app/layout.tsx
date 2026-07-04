import type { Metadata } from "next";
import "../styles/globals.css";

export const metadata: Metadata = {
  title: "De-Duke Admin Console",
  description: "Staff and Admin operational tool for De-Duke.",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body className="font-body bg-surface text-text-primary dark:bg-surface-dark dark:text-text-primary-dark">
        {children}
      </body>
    </html>
  );
}
