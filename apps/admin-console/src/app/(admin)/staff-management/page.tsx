import { StaffAccountsClient } from "@/components/staff-management/StaffAccountsClient";

export default function Page() {
  return (
    <main className="p-lg">
      <h1 className="font-heading text-xl font-semibold">Staff Management</h1>
      <p className="text-text-secondary">
        Invite, deactivate, promote, or demote Staff and Admin accounts. Admin-only.
      </p>
      <StaffAccountsClient />
    </main>
  );
}
