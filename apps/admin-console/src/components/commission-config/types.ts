// Mirrors apps/backend/app/schemas/transaction.py's Commission* shapes.

// Two-sided commission model (product decision): `buyer_fee` is a
// surcharge ADDED to the listing price (what the guest pays on top);
// `owner_commission` is a percentage DEDUCTED from the listing price
// (what the payee's net payout is reduced by). Independent,
// independently-configurable rates -- not one rate split two ways.
export type FeeType = "buyer_fee" | "owner_commission";

export const FEE_TYPES: FeeType[] = ["buyer_fee", "owner_commission"];

export const FEE_TYPE_LABELS: Record<FeeType, string> = {
  buyer_fee: "Buyer fee (added to price)",
  owner_commission: "Owner commission (deducted from payout)",
};

export interface CommissionRateResponse {
  id: string;
  transaction_type: string;
  fee_type: FeeType;
  rate_percentage: number;
  set_by_id: string;
  effective_from: string;
  created_at: string;
}

export interface CommissionRateHistoryResponse {
  transaction_type: string;
  fee_type: FeeType;
  current: CommissionRateResponse | null;
  history: CommissionRateResponse[];
}

export const TRANSACTION_TYPES = ["shortlet_booking", "lease_deposit", "sale_reservation"] as const;

export const TRANSACTION_TYPE_LABELS: Record<string, string> = {
  shortlet_booking: "Shortlet Booking",
  lease_deposit: "Lease Deposit",
  sale_reservation: "Sale Reservation",
};
