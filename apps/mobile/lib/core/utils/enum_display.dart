/// Normalizes raw backend enum-like strings (e.g. `'1_bedroom'`,
/// `'property_subtype'`, `'home'`) into a human-readable label
/// (`'1 Bedroom'`, `'Property Subtype'`, `'Home'`).
///
/// Several listing fields (`propertySubtype`, `subtype`, `dealType`, ...)
/// arrive from the backend as raw snake_case strings rather than typed
/// enums (see listing_models.dart) and were previously rendered as-is,
/// showing the wire value (`'1_bedroom'`) straight to the user instead of
/// a normalized one (`'1 Bedroom'`). Any screen that displays one of these
/// raw values should route it through this helper rather than
/// interpolating the raw string directly.
String humanizeEnumValue(String raw) {
  if (raw.isEmpty) return raw;
  return raw.split('_').where((word) => word.isNotEmpty).map((word) {
    // Leave purely numeric segments ('1', '2', ...) untouched --
    // only title-case alphabetic words.
    if (RegExp(r'^[0-9]+$').hasMatch(word)) return word;
    // return word[0].toUpperCase() + word.substring(1).toLowerCase();
    return word.toLowerCase();
  }).join(' ');
}
