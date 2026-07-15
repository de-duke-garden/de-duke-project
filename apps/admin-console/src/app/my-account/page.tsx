import { MyAccountClient } from "@/components/my-account/MyAccountClient";

/** Screen 31b: Admin -- My Account (FEAT-041). Self-service only -- edit
 * your own name, change your own password. Reachable from AdminNav's
 * account-footer area (not a Sidebar module link), available to both
 * Staff and Admin equally. */
export default function Page() {
  return (
    <main className="p-lg">
      <h1 className="font-heading text-xl font-semibold">My Account</h1>
      <p className="text-text-secondary">
        Manage your own profile and password. To manage other Staff/Admin accounts, see Staff
        Management.
      </p>
      <MyAccountClient />
    </main>
  );
}
