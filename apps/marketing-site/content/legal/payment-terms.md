# Payment Terms

<!--
  FEAT-037: Full draft, generated from README.md, features.md, architecture.md,
  monetization.md, and risk_log.md so it accurately reflects the current
  product. This is a COMPLETE DRAFT, not placeholder text -- but per FEAT-037
  it still requires review and sign-off by qualified legal counsel before
  first publication, and before any product change that would make it
  inaccurate.
-->

**Effective Date:** 2026-07-24

**Version:** 1

These Payment Terms form part of, and should be read together with, our Terms of Service. They
apply to every payment, commission deduction, escrow hold, wallet balance, and withdrawal on the
De-Duke Platform.

## 1. Payment Processor

All payments on De-Duke — Guest checkout, Host/Agency withdrawals — are processed through
**Paystack**, a licensed third-party payment processor. De-Duke does not store your full card
number, card PIN, or online banking credentials; those are handled directly and securely by
Paystack. Currency is **Nigerian Naira (NGN)**.

## 2. Fixed Pricing

Every listing has a single, fixed, non-negotiable price. There is no in-app offer or negotiation
mechanism. The price you see when you confirm a booking hold is the price used for that
transaction's checkout.

## 3. Booking Holds and Checkout

Confirming a booking creates a time-limited hold (default 15 minutes) on the listing for the
selected dates. You must complete checkout within that window; if the hold expires before payment
succeeds, it is released automatically, no charge occurs, and you will need to start again. A
payment is only recognized as successful once De-Duke receives a verified, signed confirmation from
Paystack — De-Duke does not rely on your device's own report of payment success.

## 4. Commission

De-Duke charges commission on every completed transaction (Commercial sale/lease or Shortlet
booking), split into two independently set rates:

- **Buyer Fee** — added on top of the listing price, paid by the Guest. This is included in the
  total amount charged at checkout and is shown to you before you confirm your booking hold.
- **Owner Commission** — deducted from the listing price, borne by the Host/Agency, reflected in
  the net amount credited to the Host/Agency's wallet upon release.

Both rates are set and may be changed by De-Duke from time to time. A rate change applies only to
transactions initiated after the change takes effect and never retroactively changes the rate that
applied to a transaction already underway. Current rates are disclosed in-app before you commit to
a transaction.

## 5. Escrow

Funds you pay at checkout are held by De-Duke in escrow — they are not immediately paid out to the
Host/Agency. Escrow funds are released to the Host/Agency's De-Duke wallet only after a De-Duke
Admin manually reviews and approves the release. This manual checkpoint applies to every
transaction, with no automatic or time-based release. De-Duke may pause release of funds pending
resolution of a dispute raised through the support chat or support channels.

## 6. Wallet

Once released, funds appear as a balance in the Host/Agency's De-Duke wallet, together with a full,
chronological transaction ledger. For an Agency account, the wallet is a single shared balance
visible to team members with wallet-view access, not split per individual agent.

## 7. Withdrawals

A verified Host/Agency may add their bank account details (used to create a payout recipient with
Paystack) and request a withdrawal from their wallet balance at any time. Once requested,
withdrawal is processed automatically via Paystack's Transfer API — there is no further De-Duke
approval step at this stage, since the funds already passed the manual escrow-release checkpoint in
Section 5. If a transfer fails on Paystack's side, the withdrawn amount is automatically restored to
your wallet balance so that a failed transfer never leaves your wallet balance incorrectly reduced.

## 8. Refunds

- **Guest refunds:** Handled manually by De-Duke support on a case-by-case basis, for situations
  such as a cancelled booking, a transaction dispute, or a Host/Agency failing to honor a
  transaction. Approved refunds are processed back through Paystack to your original payment
  method. Contact support through the in-app three-way chat or **support@de-duke.com** to request a
  refund review.
- **Funds already released to a Host/Agency's wallet or withdrawn** are handled through De-Duke's
  dispute-resolution process rather than an automatic reversal, given they have already left
  escrow.

## 9. Off-Platform Payment

Arranging payment for a De-Duke-sourced transaction outside the Platform — for example, after
connecting with a Host/Agency through De-Duke's chat — is discouraged, falls outside De-Duke's
escrow and dispute-resolution protections, and may violate our Terms of Service.

## 10. Agency Subscription Billing (if applicable)

Agencies who opt into the paid Agency subscription tier are billed monthly (or annually, at a
discount) via Paystack, separately from transaction commission — subscribing does not reduce or
replace commission owed on completed transactions. Failed subscription payments are retried up to 3
times over 5 days; after final failure, the account is downgraded to the Free tier (existing
listings and history are retained). A 14-day free trial is available to new Agency sign-ups; if no
payment method is added by the end of the trial, the account reverts automatically to the Free
tier with no data loss. Subscription cancellations retain Agency-tier access until the end of the
current paid billing period.

## 11. Taxes

Applicable transaction fees and tax handling are processed via Paystack's built-in mechanisms where
relevant. You are responsible for your own tax obligations arising from transactions conducted on
De-Duke.

## 12. Changes to These Payment Terms

We may update these Payment Terms from time to time — for example, if commission rates or the
withdrawal mechanism change materially. We will provide at least 30 days' advance notice via
in-app notification and/or email before a material change takes effect.

## 13. Contact Us

**De-Duke**
Email: support@de-duke.com

---
*This document is a complete working draft prepared for legal counsel review prior to publication,
per FEAT-037. It must not be treated as final, App Store/Play Store–submittable copy until counsel
has reviewed and approved it and the Effective Date/Version above reflect that approval.*
