export interface StaffAccount {
  id: string;
  full_name: string;
  email: string | null;
  role: "deduke_staff" | "deduke_admin";
  is_active: boolean;
  invited_by_id: string | null;
  created_at: string;
}
