import type { Metadata } from "next";
import "../styles/globals.css";

import { getAdminSession } from "@/lib/auth";
import { AdminNav } from "@/components/shell/AdminNav";

export const metadata: Metadata = {
  title: "De-Duke Admin Console",
  description: "Staff and Admin operational tool for De-Duke.",
};

export default async function RootLayout({ children }: { children: React.ReactNode }) {
  const session = await getAdminSession();

  return (
    <html lang="en">
      <body className="font-body bg-surface text-text-primary dark:bg-surface-dark dark:text-text-primary-dark">
        {session ? (
          <div className="flex min-h-screen">
            <AdminNav session={session} />
            <main className="min-w-0 flex-1 overflow-y-auto p-lg">{children}</main>
          </div>
        ) : (
          children
        )}
      </body>
    </html>
  );
}
