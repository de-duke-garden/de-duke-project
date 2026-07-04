/// Data models for the Listing feature (FEAT-004 Commercial, FEAT-005
/// Shortlet), mirroring apps/backend/app/schemas/listing.py.
library;

class ListingImage {
  const ListingImage({
    required this.id,
    required this.imageUrl,
    required this.displayOrder,
    required this.isPrimary,
  });

  final String id;
  final String imageUrl;
  final int displayOrder;
  final bool isPrimary;

  factory ListingImage.fromJson(Map<String, dynamic> json) => ListingImage(
        id: json['id'] as String,
        imageUrl: json['image_url'] as String,
        displayOrder: json['display_order'] as int,
        isPrimary: json['is_primary'] as bool? ?? false,
      );
}

/// A locally-picked image awaiting upload, tracked by a client-generated
/// `tempKey` per the structured multi-file upload contract
/// (architecture.md): submitted as `images_meta` JSON + a `file_<tempKey>`
/// multipart field.
class PendingListingImage {
  PendingListingImage({
    required this.tempKey,
    required this.localPath,
    required this.displayOrder,
    this.isPrimary = false,
  });

  final String tempKey;
  final String localPath;
  int displayOrder;
  bool isPrimary;

  Map<String, dynamic> toMetaJson() => {
        'temp_key': tempKey,
        'display_order': displayOrder,
        'is_primary': isPrimary,
      };
}

class CommercialRoom {
  const CommercialRoom({
    required this.level,
    required this.widthMeters,
    required this.lengthMeters,
  });

  final String level; // ground | basement | first | second | third
  final double widthMeters;
  final double lengthMeters;

  Map<String, dynamic> toJson() => {
        'level': level,
        'width_meters': widthMeters,
        'length_meters': lengthMeters,
      };
}

class CommercialListingDetails {
  CommercialListingDetails({
    required this.dealType,
    required this.price,
    this.possessionPeriodDays,
    required this.sizeSquareMeters,
    required this.propertySubtype,
    this.legalDocuments = const [],
    this.rooms = const [],
  });

  String dealType; // sale | lease
  double price;
  int? possessionPeriodDays;
  double sizeSquareMeters;
  String propertySubtype; // office | shop | home | land
  List<String> legalDocuments;
  List<CommercialRoom> rooms;

  Map<String, dynamic> toJson() => {
        'deal_type': dealType,
        'price': price,
        'possession_period_days': possessionPeriodDays,
        'size_square_meters': sizeSquareMeters,
        'property_subtype': propertySubtype,
        'legal_documents': legalDocuments,
        'rooms': rooms.map((r) => r.toJson()).toList(),
      };

  factory CommercialListingDetails.fromJson(Map<String, dynamic> json) =>
      CommercialListingDetails(
        dealType: json['deal_type'] as String,
        price: (json['price'] as num).toDouble(),
        possessionPeriodDays: json['possession_period_days'] as int?,
        sizeSquareMeters: (json['size_square_meters'] as num).toDouble(),
        propertySubtype: json['property_subtype'] as String,
        legalDocuments: (json['legal_documents'] as List? ?? [])
            .map((e) => e as String)
            .toList(),
      );
}

class ShortletListingDetails {
  ShortletListingDetails({
    required this.nightlyPrice,
    required this.minimumStayNights,
    this.maximumStayNights,
    required this.bedrooms,
    this.houseRules = const [],
    this.blockedDates = const [],
  });

  double nightlyPrice;
  int minimumStayNights;
  int? maximumStayNights;
  int bedrooms;
  List<String> houseRules;
  List<String> blockedDates;

  Map<String, dynamic> toJson() => {
        'nightly_price': nightlyPrice,
        'minimum_stay_nights': minimumStayNights,
        'maximum_stay_nights': maximumStayNights,
        'bedrooms': bedrooms,
        'house_rules': houseRules,
        'blocked_dates': blockedDates,
      };

  factory ShortletListingDetails.fromJson(Map<String, dynamic> json) =>
      ShortletListingDetails(
        nightlyPrice: (json['nightly_price'] as num).toDouble(),
        minimumStayNights: json['minimum_stay_nights'] as int,
        maximumStayNights: json['maximum_stay_nights'] as int?,
        bedrooms: json['bedrooms'] as int,
        houseRules:
            (json['house_rules'] as List? ?? []).map((e) => e as String).toList(),
        blockedDates:
            (json['blocked_dates'] as List? ?? []).map((e) => e as String).toList(),
      );
}

class Listing {
  Listing({
    required this.id,
    required this.hostAccountId,
    required this.listingType,
    required this.title,
    required this.description,
    required this.latitude,
    required this.longitude,
    required this.addressLine,
    required this.city,
    required this.state,
    required this.amenities,
    required this.status,
    this.statusReason,
    required this.viewCount,
    this.images = const [],
    this.commercial,
    this.shortlet,
  });

  final String id;
  final String hostAccountId;
  final String listingType; // commercial | shortlet
  final String title;
  final String description;
  final double latitude;
  final double longitude;
  final String addressLine;
  final String city;
  final String state;
  final List<String> amenities;
  // active | under_review | banned | unpublished | closed
  final String status;
  final String? statusReason;
  final int viewCount;
  final List<ListingImage> images;
  final CommercialListingDetails? commercial;
  final ShortletListingDetails? shortlet;

  bool get isVerifiedActive => status == 'active';

  factory Listing.fromJson(Map<String, dynamic> json) => Listing(
        id: json['id'] as String,
        hostAccountId: json['host_account_id'] as String,
        listingType: json['listing_type'] as String,
        title: json['title'] as String,
        description: json['description'] as String,
        latitude: (json['location_latitude'] as num).toDouble(),
        longitude: (json['location_longitude'] as num).toDouble(),
        addressLine: json['location_address_line'] as String,
        city: json['location_city'] as String,
        state: json['location_state'] as String,
        amenities:
            (json['amenities'] as List? ?? []).map((e) => e as String).toList(),
        status: json['status'] as String,
        statusReason: json['status_reason'] as String?,
        viewCount: json['view_count'] as int? ?? 0,
        images: (json['images'] as List? ?? [])
            .map((e) => ListingImage.fromJson(e as Map<String, dynamic>))
            .toList(),
        commercial: json['commercial'] != null
            ? CommercialListingDetails.fromJson(
                json['commercial'] as Map<String, dynamic>)
            : null,
        shortlet: json['shortlet'] != null
            ? ShortletListingDetails.fromJson(
                json['shortlet'] as Map<String, dynamic>)
            : null,
      );
}
