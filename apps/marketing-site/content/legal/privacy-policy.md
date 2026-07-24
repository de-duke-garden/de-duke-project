# Privacy Policy

<!--
  FEAT-037: Full draft, generated from README.md, features.md, architecture.md,
  monetization.md, risk_log.md, and schema.md so it accurately reflects the
  current product (fixed pricing, admin-configurable commission, six host
  verification types, the booking hold mechanism, escrow + wallet + withdrawal,
  the three-way support chat). This is a COMPLETE DRAFT, not placeholder text --
  but per FEAT-037 it still requires review and sign-off by qualified legal
  counsel (including NDPR-specific review) before first publication, and before
  any product change that would make it inaccurate.
-->

**Effective Date:** 2026-07-24

**Version:** 1

## 1. Who We Are

De-Duke ("De-Duke," "we," "us," or "our") operates a mobile marketplace application and companion
marketing website that connect property **guests** with property **hosts** (owners, agents,
companies, and licensed professionals) for two kinds of transactions: **Commercial** property
sales/leases and **Shortlet** short-term bookings, at fixed, non-negotiable prices, in Nigeria.

This Privacy Policy explains what personal data we collect when you use the De-Duke mobile app or
website, why we collect it, how it's used and shared, how long we keep it, and the rights you have
over it. It applies to all users of the platform — Guests, Hosts, Agents/Agencies, and visitors to
our Marketing Website.

If you have questions about this policy or want to exercise any of the rights described below,
contact us at **privacy@de-duke.com**.

## 2. Data We Collect

### 2.1 Account & Identity Data
- **All users:** name, email address, phone number (Nigerian, E.164 format), profile photo, and — for consumer sign-in — whichever authentication method you choose (Google Sign-In, Firebase email/password, or Firebase phone/OTP). We never see or store your Google or Firebase password; that is handled entirely by Firebase Authentication.
- **Hosts (all types):** a profile photo and bio used on your public listings, separate from your personal account photo.
- **Host verification documents**, which vary by the host type you select when you apply to become a host:

| Host Type | Documents Collected (beyond photo + bio) |
|---|---|
| Owner | None |
| Agent | CAC Certificate, Industry License (if applicable), Proof of Address, Representative ID |
| Company | CAC Registration Document, Proof of Address, Director/Representative ID |
| Lawyer | Legal practice credentials, Proof of Address, Representative ID |
| Architect | ARCON registration, Proof of Address, Representative ID |
| Surveyor | SURCON registration, Proof of Address, Representative ID |

These documents are reviewed manually by De-Duke staff to confirm your "Verified Host" status and
are never used for any purpose other than verification, fraud prevention, and (where legally
required) compliance record-keeping.

### 2.2 Listing Data
Property details, photos, pricing, and location you submit as a host when creating a Commercial or
Shortlet listing.

### 2.3 Transaction & Payment Data
- Booking/hold details (listing, dates, price) and transaction status (held, paid, released, expired).
- Commission breakdown (buyer fee, owner commission, gross/net amounts) associated with a transaction.
- Payment processing is handled by our payment processor, **Paystack** — De-Duke does not receive
  or store your full card number, card PIN, or bank login credentials. We receive confirmation of
  payment success/failure and the transaction reference from Paystack.
- **Hosts/Agencies only:** bank account details you provide for payouts (via Payout Settings), used
  solely to create a Paystack Transfer Recipient and process withdrawals from your De-Duke wallet.

### 2.4 Chat Data
Messages you send in De-Duke's real-time three-way support chat (you, the property
management/host, and De-Duke staff), stored in our chat data store (Google Cloud Firestore).
De-Duke staff can view chat conversations for support, verification confirmation, and dispute
mediation purposes.

### 2.5 Location Data
With your permission, your device's approximate or precise location, used to power "near me"
search and to help you find listings close to you. You can decline location access and still use
search by manually entering a location.

### 2.6 Usage & Device Data
App interactions (searches, listing views, chat activity, booking funnel steps), device type, OS
version, and crash/error diagnostics, collected to operate, secure, and improve the platform.

## 3. How We Use Your Data

We use the data above to:
- Create and manage your account and, for hosts, your verification status
- Operate core marketplace features: search, listings, booking holds, checkout, chat, receipts
- Process payments and payouts, calculate commission, and detect/prevent fraud
- Communicate with you — transactional emails and push notifications about bookings, payments,
  verification status, and chat activity
- Maintain platform safety, investigate disputes, and enforce our Terms of Service
- Analyze aggregate usage to improve the product (we do not sell this data — see Section 4)
- Comply with legal obligations (e.g., NDPR, tax, and financial recordkeeping requirements)

We do not use your host verification documents or chat content for advertising or marketing
purposes, and we do not sell your personal data to third parties.

## 4. How We Share Your Data

We share data only as needed to operate the platform:

| Recipient | What's Shared | Why |
|---|---|---|
| Other users (Guest ↔ Host/Agency) | Name, profile photo, host verification badge status, listing details, chat messages within a shared conversation | To enable the marketplace transaction and communication |
| De-Duke Staff/Admin | Account, listing, transaction, and chat data | Support, verification review, dispute mediation, moderation, fraud prevention |
| Paystack (Payment Processor) | Transaction amount, payer/payee identifiers, bank details (for payouts) | To process checkout payments and wallet withdrawals |
| Firebase / Google Cloud (Authentication & Chat) | Account identifiers, chat messages | To provide sign-in and real-time chat functionality |
| Google Maps | Location/address data you provide or your device location (with permission) | To power geocoding, mapping, and location search |
| Amazon SES (Email), Firebase Cloud Messaging (Push) | Contact details, notification content | To deliver transactional emails and push notifications |
| Analytics & error-tracking providers | De-identified or aggregated usage/event data, crash diagnostics | To measure and improve product performance and reliability |
| Regulators, law enforcement, or legal process | Relevant data as legally required | To comply with a valid legal obligation |

We do not share your data with third parties for their own independent marketing purposes.

## 5. Data Retention

We retain personal data only as long as needed for the purposes above, specifically:

- **Account & profile data:** retained while your account is active, and for a limited period after
  closure to comply with legal, tax, and dispute-resolution obligations.
- **Host verification documents:** retained for the duration of your active "Verified Host" status
  plus a defined post-closure period required for compliance and fraud-investigation purposes, then
  deleted or anonymized.
- **Transaction and payment records:** retained for the period required by Nigerian financial
  recordkeeping and tax law.
- **Chat history:** retained for a defined period to support dispute resolution and platform safety,
  then deleted or archived per our internal retention schedule.

Specific retention periods per data category are defined in our internal data governance schedule
(NDPR-aligned) and provided on request.

## 6. Your Rights

Under the Nigeria Data Protection Act/NDPR and applicable law, you have the right to:
- Access the personal data we hold about you
- Request correction of inaccurate data
- Request deletion of your account and associated personal data (subject to our legal retention
  obligations described in Section 5 — e.g., we cannot delete transaction records still required
  for tax/financial compliance)
- Object to or restrict certain processing
- Withdraw consent for optional features (e.g., location access, push notifications) at any time
  via your device settings

To exercise any of these rights, contact **privacy@de-duke.com**. We will respond within the
timeframe required by applicable law.

## 7. Material Changes to This Policy

If we make a material change to this Privacy Policy (for example, a change to what data we collect
or how commission-related data is used), we will provide at least **30 days' advance notice** via
in-app notification and/or email before the change takes effect, consistent with our data
governance commitments.

## 8. Children's Privacy

De-Duke is not directed at, and may not knowingly be used by, individuals under the age of 18.
We do not knowingly collect personal data from minors. If we learn a minor has created an account,
we will take steps to delete it.

## 9. International Data Transfers

De-Duke's infrastructure spans Nigeria-focused hosting on AWS and Google Cloud services located
outside Nigeria (used for chat and authentication). Where personal data is transferred outside
Nigeria, we rely on appropriate safeguards consistent with NDPR requirements.

## 10. Contact Us

**De-Duke**
Email: privacy@de-duke.com

---
*This document is a complete working draft prepared for legal counsel review prior to publication,
per FEAT-037. It must not be treated as final, App Store/Play Store–submittable copy until counsel
has reviewed and approved it and the Effective Date/Version above reflect that approval.*
