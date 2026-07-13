/// Data models for Saved Searches & Listing Alerts (FEAT-023). Mirrors
/// apps/backend/app/schemas/saved_search.py -- keep field names in sync
/// with that file if either side changes.
library;

class SavedSearch {
  const SavedSearch({
    required this.id,
    required this.label,
    required this.locationQuery,
    required this.radiusKm,
    required this.verifiedOnly,
    required this.alertsEnabled,
    required this.createdAt,
    this.listingType,
    this.minPrice,
    this.maxPrice,
  });

  factory SavedSearch.fromJson(Map<String, dynamic> json) {
    return SavedSearch(
      id: json['id'] as String,
      label: json['label'] as String,
      locationQuery: json['location_query'] as String,
      radiusKm: (json['radius_km'] as num).toDouble(),
      listingType: json['listing_type'] as String?,
      minPrice: (json['min_price'] as num?)?.toDouble(),
      maxPrice: (json['max_price'] as num?)?.toDouble(),
      verifiedOnly: json['verified_only'] as bool? ?? false,
      alertsEnabled: json['alerts_enabled'] as bool? ?? false,
      createdAt: json['created_at'] as String,
    );
  }

  final String id;
  final String label;
  final String locationQuery;
  final double radiusKm;
  final String? listingType;
  final double? minPrice;
  final double? maxPrice;
  final bool verifiedOnly;
  final bool alertsEnabled;
  final String createdAt;

  /// Screen 20's `ListTile` subtitle -- a compact filter summary, e.g.
  /// "Lekki · within 10km · Shortlet · Verified only".
  String get filterSummary {
    final parts = <String>[
      locationQuery,
      'within ${radiusKm.toStringAsFixed(0)}km',
    ];
    if (listingType != null) {
      parts.add(listingType == 'shortlet' ? 'Shortlet' : 'Commercial');
    }
    if (minPrice != null || maxPrice != null) {
      final min = minPrice?.toStringAsFixed(0) ?? '0';
      final max = maxPrice?.toStringAsFixed(0) ?? '∞';
      parts.add('₦$min–₦$max');
    }
    if (verifiedOnly) parts.add('Verified only');
    return parts.join(' · ');
  }

  SavedSearch copyWith({bool? alertsEnabled}) {
    return SavedSearch(
      id: id,
      label: label,
      locationQuery: locationQuery,
      radiusKm: radiusKm,
      listingType: listingType,
      minPrice: minPrice,
      maxPrice: maxPrice,
      verifiedOnly: verifiedOnly,
      alertsEnabled: alertsEnabled ?? this.alertsEnabled,
      createdAt: createdAt,
    );
  }
}
