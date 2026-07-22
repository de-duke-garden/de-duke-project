"""FEAT-015 -- real PDF receipt generation and storage.

Previously `paystack_webhook_handler.py` created a `Receipt` row with
`pdf_url=""` (a TODO placeholder -- no PDF was ever actually generated) at
the moment a transaction succeeded, and only then. Two confirmed real gaps
this module closes:

1. No PDF was ever generated at all -- `Receipt.pdf_url` stayed an empty
   string forever, so "Download PDF Receipt" could never work even for a
   fully paid transaction (see transaction_detail_screen.dart's matching
   mobile-side fix).
2. A receipt only ever existed for a `succeeded` transaction. A user with
   an active `held`/`pending_payment` booking (FEAT-032's confirm-before-pay
   hold) had nothing downloadable at all -- product decision (this
   conversation) is that a hold should produce its own "Booking Hold
   Confirmation" document immediately, which this module then upgrades in
   place to a full "Payment Receipt" once the same transaction succeeds
   (still exactly one `Receipt` row per `Transaction`, per that table's
   `transaction_id` unique constraint -- never a second row).

Called from three places:
  - `bookings.confirm_booking_endpoint` -- generates the initial
    hold-confirmation document right after `booking_service.confirm_booking`
    creates the held Transaction (best-effort: a PDF-generation failure
    must never block the booking itself from being created). Deliberately
    called from the API route, AFTER its `async with session.begin():`
    block has already committed -- not from inside
    `booking_service.confirm_booking` itself, since `ensure_receipt` does
    its own `session.commit()` and nesting that inside an active
    `session.begin()` block is unsafe/unsupported.
  - `paystack_webhook_handler.handle_paystack_webhook` -- regenerates the
    document as a full payment receipt once `charge.success` lands, called
    after that function's own existing commit for the same reason above.
  - `transactions.get_transaction` -- lazy fallback, so any transaction
    that reached `held`/`succeeded` before this module existed (or via any
    call path that didn't go through the two sites above) still gets a
    receipt generated on next read, rather than staying stuck with none.
"""

from __future__ import annotations

import io
import logging
from datetime import UTC, datetime

from reportlab.lib import colors
from reportlab.lib.pagesizes import A4
from reportlab.lib.units import mm
from reportlab.pdfgen import canvas
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.storage import upload_bytes
from app.models.listing import Listing
from app.models.transaction import Receipt, Transaction
from app.models.user import User

logger = logging.getLogger("app.services.receipt_service")

# branding.md primary green -- the one brand color this single-tone,
# text-first PDF uses, for the De-Duke wordmark and section rules.
_BRAND_GREEN = colors.HexColor("#0D6B2D")
_TEXT_SECONDARY = colors.HexColor("#5F6E68")

# Statuses a receipt/hold-confirmation document is ever generated for --
# every other status (failed, expired, refunded) has nothing meaningful to
# hand the user a PDF about. 'payment_received'/'released_to_wallet' both
# get the full "Payment Receipt" treatment (schema.md's escrow model --
# the payer already paid in full at 'payment_received'; whether a De-Duke
# Admin has since released the payee's funds doesn't change what the payer
# holds as proof of payment).
_RECEIPT_ELIGIBLE_STATUSES = ("held", "pending_payment", "payment_received", "released_to_wallet")
_PAID_STATUSES = ("payment_received", "released_to_wallet")


def _money(amount: float) -> str:
    return f"NGN {amount:,.2f}"


def _draw_kv_rows(pdf: canvas.Canvas, rows: list[tuple[str, str]], *, x: float, y: float) -> float:
    """Draws label/value pairs, label left-aligned, value right-aligned at
    a fixed column -- returns the y position after the last row."""
    for label, value in rows:
        pdf.setFillColor(_TEXT_SECONDARY)
        pdf.setFont("Helvetica", 10)
        pdf.drawString(x, y, label)
        pdf.setFillColor(colors.black)
        pdf.setFont("Helvetica-Bold", 10)
        pdf.drawRightString(x + 160 * mm, y, value)
        y -= 7 * mm
    return y


def _build_pdf_bytes(
    *,
    txn: Transaction,
    receipt_number: str,
    listing_title: str,
    payer: User | None,
    payee: User | None,
) -> bytes:
    """Renders a single-page A4 PDF -- a "Booking Hold Confirmation" for a
    held/pending_payment transaction (no commission breakdown yet, since
    `Transaction.commissionAmount`/`netPayoutAmount` aren't finalized until
    payment actually succeeds -- see commission_service.compute_breakdown,
    only ever called from the webhook handler's success branch), or a full
    "Payment Receipt" (with that breakdown, plus `paidAt`) once paid
    (`payment_received` or `released_to_wallet` -- schema.md's escrow
    model; the receipt reflects what the PAYER paid, unaffected by
    whether a De-Duke Admin has since released funds to the payee).
    """
    is_paid = txn.status in _PAID_STATUSES
    buffer = io.BytesIO()
    pdf = canvas.Canvas(buffer, pagesize=A4)
    width, height = A4
    margin = 20 * mm
    y = height - margin

    pdf.setFillColor(_BRAND_GREEN)
    pdf.setFont("Helvetica-Bold", 18)
    pdf.drawString(margin, y, "De-Duke")
    pdf.setFont("Helvetica", 9)
    pdf.setFillColor(_TEXT_SECONDARY)
    pdf.drawRightString(width - margin, y, receipt_number)
    y -= 6 * mm
    pdf.setStrokeColor(_BRAND_GREEN)
    pdf.setLineWidth(1)
    pdf.line(margin, y, width - margin, y)
    y -= 12 * mm

    pdf.setFillColor(colors.black)
    pdf.setFont("Helvetica-Bold", 14)
    pdf.drawString(margin, y, "Payment Receipt" if is_paid else "Booking Hold Confirmation")
    y -= 10 * mm

    if not is_paid:
        pdf.setFillColor(_TEXT_SECONDARY)
        pdf.setFont("Helvetica-Oblique", 9)
        pdf.drawString(
            margin,
            y,
            "This confirms a held booking, not a completed payment. The commission "
            "breakdown below is finalized only once payment is confirmed.",
        )
        y -= 10 * mm

    header_rows = [
        ("Transaction ID", txn.id),
        ("Listing", listing_title),
        ("Type", txn.transaction_type.replace("_", " ").title()),
        ("Status", txn.status.replace("_", " ").title()),
        ("Created", txn.created_at.strftime("%d %b %Y, %H:%M UTC")),
    ]
    if is_paid and txn.paid_at is not None:
        header_rows.append(("Paid", txn.paid_at.strftime("%d %b %Y, %H:%M UTC")))
    elif txn.hold_expires_at is not None:
        header_rows.append(("Hold expires", txn.hold_expires_at.strftime("%d %b %Y, %H:%M UTC")))
    y = _draw_kv_rows(pdf, header_rows, x=margin, y=y)
    y -= 6 * mm

    pdf.setStrokeColor(colors.HexColor("#E1E6E3"))
    pdf.line(margin, y, width - margin, y)
    y -= 10 * mm

    pdf.setFillColor(colors.black)
    pdf.setFont("Helvetica-Bold", 11)
    pdf.drawString(margin, y, "Parties")
    y -= 8 * mm
    party_rows = [
        ("Payer", payer.full_name if payer else "Unknown"),
        ("Payer email", payer.email or "--" if payer else "--"),
        ("Payee (host)", payee.full_name if payee else "Unknown"),
    ]
    y = _draw_kv_rows(pdf, party_rows, x=margin, y=y)
    y -= 6 * mm

    pdf.setStrokeColor(colors.HexColor("#E1E6E3"))
    pdf.line(margin, y, width - margin, y)
    y -= 10 * mm

    pdf.setFillColor(colors.black)
    pdf.setFont("Helvetica-Bold", 11)
    pdf.drawString(margin, y, "Amount")
    y -= 8 * mm
    amount_rows = [("Gross amount", _money(txn.gross_amount))]
    if is_paid:
        amount_rows += [
            ("Commission", _money(txn.commission_amount)),
            ("Net payout to host", _money(txn.net_payout_amount)),
        ]
    else:
        amount_rows.append(("Amount due at checkout", _money(txn.gross_amount)))
    y = _draw_kv_rows(pdf, amount_rows, x=margin, y=y)

    pdf.setFillColor(_TEXT_SECONDARY)
    pdf.setFont("Helvetica", 8)
    pdf.drawCentredString(
        width / 2,
        margin / 2,
        f"Generated {datetime.now(UTC).strftime('%d %b %Y, %H:%M UTC')} -- De-Duke",
    )

    pdf.showPage()
    pdf.save()
    return buffer.getvalue()


async def ensure_receipt(session: AsyncSession, txn: Transaction) -> Receipt | None:
    """Idempotent -- returns the existing Receipt if it already correctly
    reflects `txn`'s current status, generating/regenerating it only when
    needed:
      - no Receipt row exists yet for this transaction at all, or
      - the transaction has since been paid (`payment_received` or
        `released_to_wallet`) but the stored receipt was generated before
        that (still describes a hold, not a payment).

    Returns None for any status with nothing to generate a document for
    (failed/expired/refunded) -- callers should treat that the same as
    "no receipt available."

    Note: no regeneration is needed for the `payment_received` ->
    `released_to_wallet` transition itself -- `_build_pdf_bytes` renders
    both identically (a paid transaction's receipt reflects what the
    PAYER paid, which release doesn't change); only the hold -> paid
    transition changes what's on the page.

    Caller is responsible for the surrounding transaction/commit
    boundary having already committed `txn`'s own field changes (status/
    paid_at/commission_amount/net_payout_amount) before calling this, so
    the PDF reflects final values, not values about to be rolled back.
    """
    if txn.status not in _RECEIPT_ELIGIBLE_STATUSES:
        return None

    existing = (
        await session.execute(select(Receipt).where(Receipt.transaction_id == txn.id))
    ).scalar_one_or_none()

    already_reflects_current_status = existing is not None and (
        txn.status not in _PAID_STATUSES
        or existing.issued_at >= (txn.paid_at or existing.issued_at)
    )
    if already_reflects_current_status:
        return existing

    listing = await session.get(Listing, txn.listing_id)
    payer = await session.get(User, txn.payer_id)
    payee = await session.get(User, txn.payee_id)
    receipt_number = (
        existing.receipt_number if existing is not None else f"RCPT-{txn.id[:8].upper()}"
    )

    try:
        pdf_bytes = _build_pdf_bytes(
            txn=txn,
            receipt_number=receipt_number,
            listing_title=listing.title if listing is not None else "Listing no longer available",
            payer=payer,
            payee=payee,
        )
        pdf_url = await upload_bytes(
            pdf_bytes,
            prefix=f"receipts/{txn.id}",
            filename=f"{receipt_number}.pdf",
            content_type="application/pdf",
        )
    except Exception:  # noqa: BLE001 -- PDF generation/upload must never block the caller
        # Most callers (create_hold, the webhook handler) are on the
        # critical path for booking/payment itself -- a receipt PDF is a
        # nice-to-have alongside that, never a reason to fail the booking
        # or the payment confirmation. transactions.get_transaction's own
        # lazy-fallback call site will simply retry on the next read.
        logger.warning("receipt_service: PDF generation/upload failed for txn=%s", txn.id, exc_info=True)
        return existing

    if existing is not None:
        existing.pdf_url = pdf_url
        existing.issued_at = datetime.now(UTC)
        session.add(existing)
        await session.commit()
        await session.refresh(existing)
        return existing

    receipt = Receipt(transaction_id=txn.id, receipt_number=receipt_number, pdf_url=pdf_url)
    session.add(receipt)
    await session.commit()
    await session.refresh(receipt)
    return receipt
