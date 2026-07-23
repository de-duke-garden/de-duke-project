/// Shared Naira amount formatting -- every money value shown to the user
/// (wallet balances, transaction amounts, listing prices) must render with
/// thousands separators (e.g. `1,000` not `1000`), matching how Nigerian
/// users expect currency to read and consistent with the admin console's
/// `toLocaleString()`-based formatting on the same figures.
///
/// Backed by `package:intl`'s `NumberFormat.currency`, already a mobile
/// dependency (see `pubspec.yaml`). Centralized here instead of
/// constructing a `NumberFormat.currency(...)` at each call site so every
/// screen agrees on locale/decimal-digit conventions.
library;

import 'package:intl/intl.dart';

/// `en_NG` locale, `₦` symbol, no decimal digits -- Naira amounts are
/// conventionally shown as whole numbers in this app's UI (see the
/// pre-existing `booking_confirmation_screen.dart`/`listing_result_card.dart`
/// formatters this consolidates).
final NumberFormat _nairaWhole =
    NumberFormat.currency(locale: 'en_NG', symbol: '₦', decimalDigits: 0);

/// Same as [_nairaWhole] but keeps 2 decimal places, for the few screens
/// (checkout/transaction breakdowns) that previously showed kobo-precision
/// amounts via `toStringAsFixed(2)`.
final NumberFormat _nairaDecimal =
    NumberFormat.currency(locale: 'en_NG', symbol: '₦', decimalDigits: 2);

/// Formats [amount] as `₦1,234` (no decimals). Use for prices, balances,
/// and totals that were previously rendered as `'₦${amount.toStringAsFixed(0)}'`.
String formatNaira(num amount) => _nairaWhole.format(amount);

/// Formats [amount] as `₦1,234.56` (2 decimals). Use for anywhere that
/// previously rendered `'₦${amount.toStringAsFixed(2)}'`.
String formatNairaDecimal(num amount) => _nairaDecimal.format(amount);

/// Formats a plain numeric [amount] with thousands separators and no
/// currency symbol (e.g. an amount already following a `₦` prefix or
/// `Amount (₦)` field). Use in place of `amount.toStringAsFixed(0)` where a
/// symbol is added separately by the surrounding text.
String formatAmount(num amount) =>
    NumberFormat.decimalPattern('en_NG').format(amount);
