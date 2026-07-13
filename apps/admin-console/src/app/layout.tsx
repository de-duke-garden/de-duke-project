import type { Metadata } from "next";
import "../styles/globals.css";

import { getAdminSession } from "@/lib/auth";
import { AdminShell } from "@/components/shell/AdminShell";

export const metadata: Metadata = {
  title: "De-Duke Admin Console",
  description: "Staff and Admin operational tool for De-Duke.",
};

export default async function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  const session = await getAdminSession();

  return (
    <html lang="en">
      <body className="font-body bg-surface text-text-primary dark:bg-surface-dark dark:text-text-primary-dark">
        {session ? (
          <AdminShell session={session}>{children}</AdminShell>
        ) : (
          children
        )}
      </body>
    </html>
  );
}
