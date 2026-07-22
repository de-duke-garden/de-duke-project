// FEAT-043 (Admin-Only Escrow Release) -- shapes mirror
// app/schemas/wallet.py's ReleasableTransactionOut/ReleaseFundsResponse.

export interface ReleasableTransaction {
  transaction_id: string;
  listing_id: string;
  payer_id: string;
  payee_id: string;
  transaction_type: string;
  gross_amount: number;
  commission_amount: number;
  net_payout_amount: number;
  paid_at: string | null;
  status: string;
  released_at: string | null;
  released_by_admin_id: string | null;
  // FEAT-043/FEAT-026 coupling -- true if a dispute against this
  // transaction is still open/under_review. The backend hard-blocks
  // release in this case (wallet_service.release_transaction) regardless
  // of what this screen does with the flag; here it's used to warn and
  // disable the Release action before even attempting a call that would
  // fail, without re-implementing the Disputes screen's own UI.
  has_open_dispute: boolean;
}

// Mirrors wallet_service.RELEASE_QUEUE_FILTERS. 'pending' is the to-do
// queue (still-escrowed); 'released' is a persisted log of completed
// releases (a row never disappears from the screen once acted on --
// it just moves filters); 'all' shows both together.
export type ReleaseQueueFilter = "pending" | "released" | "all";

export const RELEASE_QUEUE_FILTERS: {
  value: ReleaseQueueFilter;
  label: string;
}[] = [
  { value: "pending", label: "Pending release" },
  { value: "released", label: "Released" },
  { value: "all", label: "All" },
];

export interface ReleaseFundsResponse {
  transaction_id: string;
  status: string;
  released_at: string | null;
  released_by_admin_id: string | null;
  net_payout_amount: number;
}

export const TRANSACTION_TYPE_LABELS: Record<string, string> = {
  shortlet_booking: "Shortlet Booking",
  lease_deposit: "Lease Deposit",
  sale_reservation: "Sale Reservation",
};
