import { getAdminSession, requireAdminRole } from "@/lib/auth";
import { HomeDashboardClient } from "@/components/home/HomeDashboardClient";

/**
 * screens.md Screen 22: Admin -- Home / Overview. The Admin Web Console's
 * root landing screen, shown immediately post-login for both Staff and
 * Admin account levels (RootLayout renders the shared Sidebar/AdminNav
 * around whatever this route returns once a session exists -- middleware
 * already redirects unauthenticated visitors to /login before this page
 * is ever reached).
 */
export default async function HomePage() {
  const session = await getAdminSession();
  const isAdmin = requireAdminRole(session);

  return (
    <main className="p-lg">
      <h1 className="font-heading text-xl font-semibold">Home</h1>
      <p className="text-text-secondary">
        {session?.role === "deduke_admin" ? "Admin" : "Staff"} overview -- what needs attention
        right now.
      </p>

      <div className="mt-lg">
        <HomeDashboardClient isAdmin={isAdmin} />
      </div>
    </main>
  );
}
