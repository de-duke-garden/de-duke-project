/// Data models for the Search & Discovery feature (FEAT-006/FEAT-007/FEAT-031).
/// Mirrors apps/backend/app/schemas/search.py -- keep field names/enums in
/// sync with that file if either side changes.
library;

enum ListingTypeFilter { commercial, shortlet }

enum DealTypeFilter { sale, lease }

enum CommercialSubtype { office, shop, home, land }

/// NOTE: backend schema-gap (see search_service.py) -- "hostel"/"hotel"
/// values are accepted by the API but are currently a documented no-op
/// filter until ShortletListing gains a subtype column. 1/2/3 bedroom values
/// map onto the existing `bedrooms` column and do work today.
enum ShortletSubtype { hostel, hotel, oneBedroom, twoBedroom, threeBedroom }

enum SortField { price, distance, newest }

enum SortDirection { asc, desc }

extension SortDirectionX on SortDirection {
  String get apiValue => name;
}

extension ListingTypeFilterX on ListingTypeFilter {
  String get apiValue => name;
}

extension DealTypeFilterX on DealTypeFilter {
  String get apiValue => name;
}

extension CommercialSubtypeX on CommercialSubtype {
  String get apiValue => name;
  String get label => switch (this) {
        CommercialSubtype.office => 'Office',
        CommercialSubtype.shop => 'Shop',
        CommercialSubtype.home => 'Home',
        CommercialSubtype.land => 'Land',
      };
}

extension ShortletSubtypeX on ShortletSubtype {
  String get apiValue => switch (this) {
        ShortletSubtype.hostel => 'hostel',
        ShortletSubtype.hotel => 'hotel',
        ShortletSubtype.oneBedroom => '1_bedroom',
        ShortletSubtype.twoBedroom => '2_bedroom',
        ShortletSubtype.threeBedroom => '3_bedroom',
      };

  String get label => switch (this) {
        ShortletSubtype.hostel => 'Hostel',
        ShortletSubtype.hotel => 'Hotel',
        ShortletSubtype.oneBedroom => '1 Bedroom',
        ShortletSubtype.twoBedroom => '2 Bedroom',
        ShortletSubtype.threeBedroom => '3 Bedroom',
      };
}

extension SortFieldX on SortField {
  String get apiValue => name;
  String get label => switch (this) {
        SortField.price => 'Price',
        SortField.distance => 'Distance',
        SortField.newest => 'Newest',
      };
}

/// Filter/sort/location state for one search session. Immutable -- every
/// change produces a new instance via [copyWith], which SearchNotifier holds
/// so it survives navigating to Listing Detail and back (FEAT-007
/// acceptance criteria: "Filter state persists when navigating back from a
/// listing detail screen").
class SearchQueryState {
  const SearchQueryState({
    this.latitude,
    this.longitude,
    this.radiusKm = 10.0,
    this.query,
    this.listingType,
    this.dealType,
    this.commercialSubtype,
    this.shortletSubtype,
    this.minPrice,
    this.maxPrice,
    this.minSizeSqm,
    this.maxSizeSqm,
    this.bathrooms,
    this.amenities = const [],
    this.legalDocuments = const [],
    this.verifiedOnly = false,
    this.sortBy = SortField.newest,
    this.sortDirection = SortDirection.desc,
  });

  final double? latitude;
  final double? longitude;
  final double radiusKm;
  final String? query;
  final ListingTypeFilter? listingType;
  final DealTypeFilter? dealType;
  final CommercialSubtype? commercialSubtype;
  final ShortletSubtype? shortletSubtype;
  final double? minPrice;
  final double? maxPrice;
  final double? minSizeSqm;
  final double? maxSizeSqm;
  final int? bathrooms;
  final List<String> amenities;
  final List<String> legalDocuments;
  final bool verifiedOnly;
  final SortField sortBy;
  final SortDirection sortDirection;

  int get activeFilterCount {
    var count = 0;
    if (listingType != null) count++;
    if (dealType != null) count++;
    if (commercialSubtype != null) count++;
    if (shortletSubtype != null) count++;
    if (minPrice != null || maxPrice != null) count++;
    if (minSizeSqm != null || maxSizeSqm != null) count++;
    if (bathrooms != null) count++;
    if (amenities.isNotEmpty) count++;
    if (legalDocuments.isNotEmpty) count++;
    if (verifiedOnly) count++;
    return count;
  }

  SearchQueryState copyWith({
    double? latitude,
    double? longitude,
    double? radiusKm,
    String? query,
    bool clearQuery = false,
    ListingTypeFilter? listingType,
    bool clearListingType = false,
    DealTypeFilter? dealType,
    bool clearDealType = false,
    CommercialSubtype? commercialSubtype,
    bool clearCommercialSubtype = false,
    ShortletSubtype? shortletSubtype,
    bool clearShortletSubtype = false,
    double? minPrice,
    bool clearMinPrice = false,
    double? maxPrice,
    bool clearMaxPrice = false,
    double? minSizeSqm,
    bool clearMinSizeSqm = false,
    double? maxSizeSqm,
    bool clearMaxSizeSqm = false,
    int? bathrooms,
    bool clearBathrooms = false,
    List<String>? amenities,
    List<String>? legalDocuments,
    bool? verifiedOnly,
    SortField? sortBy,
    SortDirection? sortDirection,
  }) {
    return SearchQueryState(
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      radiusKm: radiusKm ?? this.radiusKm,
      query: clearQuery ? null : (query ?? this.query),
      listingType: clearListingType ? null : (listingType ?? this.listingType),
      dealType: clearDealType ? null : (dealType ?? this.dealType),
      commercialSubtype: clearCommercialSubtype
          ? null
          : (commercialSubtype ?? this.commercialSubtype),
      shortletSubtype: clearShortletSubtype
          ? null
          : (shortletSubtype ?? this.shortletSubtype),
      minPrice: clearMinPrice ? null : (minPrice ?? this.minPrice),
      maxPrice: clearMaxPrice ? null : (maxPrice ?? this.maxPrice),
      minSizeSqm: clearMinSizeSqm ? null : (minSizeSqm ?? this.minSizeSqm),
      maxSizeSqm: clearMaxSizeSqm ? null : (maxSizeSqm ?? this.maxSizeSqm),
      bathrooms: clearBathrooms ? null : (bathrooms ?? this.bathrooms),
      amenities: amenities ?? this.amenities,
      legalDocuments: legalDocuments ?? this.legalDocuments,
      verifiedOnly: verifiedOnly ?? this.verifiedOnly,
      sortBy: sortBy ?? this.sortBy,
      sortDirection: sortDirection ?? this.sortDirection,
    );
  }

  SearchQueryState clearAllFilters() => SearchQueryState(
        latitude: latitude,
        longitude: longitude,
        radiusKm: radiusKm,
        query: query,
      );

  Map<String, dynamic> toQueryParameters() {
    return {
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      'radius_km': radiusKm,
      if (query != null && query!.isNotEmpty) 'query': query,
      if (listingType != null) 'listing_type': listingType!.apiValue,
      if (dealType != null) 'deal_type': dealType!.apiValue,
      if (commercialSubtype != null)
        'commercial_subtype': commercialSubtype!.apiValue,
      if (shortletSubtype != null)
        'shortlet_subtype': shortletSubtype!.apiValue,
      if (minPrice != null) 'min_price': minPrice,
      if (maxPrice != null) 'max_price': maxPrice,
      if (minSizeSqm != null) 'min_size_sqm': minSizeSqm,
      if (maxSizeSqm != null) 'max_size_sqm': maxSizeSqm,
      if (bathrooms != null) 'bathrooms': bathrooms,
      if (amenities.isNotEmpty) 'amenities': amenities,
      if (legalDocuments.isNotEmpty) 'legal_documents': legalDocuments,
      'verified_only': verifiedOnly,
      'sort_by': sortBy.apiValue,
      'sort_direction': sortDirection.apiValue,
    };
  }
}

class ListingSearchResult {
  const ListingSearchResult({
    required this.id,
    required this.listingType,
    required this.title,
    required this.locationCity,
    required this.locationState,
    required this.locationAddressLine,
    required this.latitude,
    required this.longitude,
    required this.createdAt,
    this.distanceKm,
    this.dealType,
    this.price,
    this.commercialSubtype,
    this.sizeSquareMeters,
    this.legalDocuments,
    this.nightlyPrice,
    this.bedrooms,
    this.bathrooms,
    this.amenities = const [],
    this.isVerifiedHost = false,
    this.primaryImageUrl,
  });

  factory ListingSearchResult.fromJson(Map<String, dynamic> json) {
    return ListingSearchResult(
      id: json['id'] as String,
      listingType: json['listing_type'] == 'shortlet'
          ? ListingTypeFilter.shortlet
          : ListingTypeFilter.commercial,
      title: json['title'] as String,
      locationCity: json['location_city'] as String,
      locationState: json['location_state'] as String,
      locationAddressLine: json['location_address_line'] as String,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      createdAt: json['created_at'] as String,
      distanceKm: (json['distance_km'] as num?)?.toDouble(),
      dealType: json['deal_type'] as String?,
      price: (json['price'] as num?)?.toDouble(),
      commercialSubtype: json['commercial_subtype'] as String?,
      sizeSquareMeters: (json['size_square_meters'] as num?)?.toDouble(),
      legalDocuments: (json['legal_documents'] as List?)?.cast<String>(),
      nightlyPrice: (json['nightly_price'] as num?)?.toDouble(),
      bedrooms: json['bedrooms'] as int?,
      bathrooms: json['bathrooms'] as int?,
      amenities: (json['amenities'] as List?)?.cast<String>() ?? const [],
      isVerifiedHost: json['is_verified_host'] as bool? ?? false,
      primaryImageUrl: json['primary_image_url'] as String?,
    );
  }

  final String id;
  final ListingTypeFilter listingType;
  final String title;
  final String locationCity;
  final String locationState;
  final String locationAddressLine;
  final double latitude;
  final double longitude;
  final String createdAt;
  final double? distanceKm;
  final String? dealType;
  final double? price;
  final String? commercialSubtype;
  final double? sizeSquareMeters;
  final List<String>? legalDocuments;
  final double? nightlyPrice;
  final int? bedrooms;
  final int? bathrooms;
  final List<String> amenities;
  final bool isVerifiedHost;
  final String? primaryImageUrl;

  double? get displayPrice => price ?? nightlyPrice;
}

class SearchResultsPage {
  const SearchResultsPage(
      {required this.results, required this.nextCursor, required this.hasMore});

  factory SearchResultsPage.fromJson(Map<String, dynamic> json) {
    return SearchResultsPage(
      results: (json['results'] as List)
          .map((e) => ListingSearchResult.fromJson(e as Map<String, dynamic>))
          .toList(),
      nextCursor: json['next_cursor'] as String?,
      hasMore: json['has_more'] as bool? ?? false,
    );
  }

  final List<ListingSearchResult> results;
  final String? nextCursor;
  final bool hasMore;
}
