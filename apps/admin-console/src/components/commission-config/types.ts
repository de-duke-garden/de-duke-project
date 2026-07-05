export interface CommissionRateResponse {
  id: string;
  transaction_type: string;
  rate_percentage: number;
  set_by_id: string;
  effective_from: string;
  created_at: string;
}

export interface CommissionRateHistoryResponse {
  transaction_type: string;
  current: CommissionRateResponse | null;
  history: CommissionRateResponse[];
}

export const TRANSACTION_TYPES = ["shortlet_booking", "lease_deposit", "sale_reservation"] as const;

export const TRANSACTION_TYPE_LABELS: Record<string, string> = {
  shortlet_booking: "Shortlet Booking",
  lease_deposit: "Lease Deposit",
  sale_reservation: "Sale Reservation",
};
