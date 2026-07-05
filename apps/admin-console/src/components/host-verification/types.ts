export interface HostAccountQueueItem {
  id: string;
  user_id: string;
  host_type: string;
  status: string;
  created_at: string;
}

/** GET /v1/host-accounts/admin/:id -- every possible type-specific field is
 * optional; only the ones relevant to `host_type` will be non-null. */
export interface HostAccountDetail {
  id: string;
  user_id: string;
  host_type: string;
  status: string;
  status_reason: string | null;
  host_photo_url: string;
  bio: string;
  created_at: string;

  cac_cert_doc_url: string | null;
  industry_license_url: string | null;
  proof_of_address_url: string | null;
  rep_id_url: string | null;
  cac_reg_doc_url: string | null;
  nba_enrol_no: string | null;
  valid_practicing_cert_url: string | null;
  govt_issued_id_url: string | null;
  arcon_reg_no: string | null;
  practice_license_url: string | null;
  surcon_reg_no: string | null;
  ref_phone_no: string | null;
}

export type ReviewDecision = "verified" | "rejected";
