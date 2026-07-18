/// Data models for the Listing feature (FEAT-004 Commercial, FEAT-005
/// Shortlet), mirroring apps/backend/app/schemas/listing.py.
library;

/// A single photo or short video clip attached to a listing (schema.md's
/// `ListingMedia` entity, generalized from the photo-only `ListingImage` --
/// FEAT-004/FEAT-005 video support, product-shaped via product-shaper).
/// Photos and videos share one `displayOrder` sequence so they can be
/// interleaved in the gallery -- see listing_detail_screen.dart's
/// `_ListingMediaCarousel`.
class ListingMedia {
  const ListingMedia({
    required this.id,
    required this.mediaType,
    required this.mediaUrl,
    this.posterUrl,
    this.durationSeconds,
    this.processingStatus,
    required this.displayOrder,
    required this.isPrimary,
  });

  final String id;
  // image | video
  final String mediaType;
  final String mediaUrl;
  // Video-only -- server-generated poster/thumbnail frame. Always null for
  // an image.
  final String? posterUrl;
  final double? durationSeconds;
  // pending | ready | failed | null (null for image rows, which have no
  // processing step -- see the backend ListingMedia model's docstring).
  final String? processingStatus;
  final int displayOrder;
  // Restricted to media_type == 'image' server-side -- a video is never
  // the listing's primary/cover.
  final bool isPrimary;

  bool get isVideo => mediaType == 'video';
  bool get isPosterReady => posterUrl != null && processingStatus != 'pending';

  factory ListingMedia.fromJson(Map<String, dynamic> json) => ListingMedia(
        id: json['id'] as String,
        mediaType: json['media_type'] as String? ?? 'image',
        mediaUrl: json['media_url'] as String,
        posterUrl: json['poster_url'] as String?,
        durationSeconds: (json['duration_seconds'] as num?)?.toDouble(),
        processingStatus: json['processing_status'] as String?,
        displayOrder: json['display_order'] as int,
        isPrimary: json['is_primary'] as bool? ?? false,
      );
}

/// A locally-picked photo or video awaiting upload, tracked by a
/// client-generated `tempKey` per the structured multi-file upload
/// contract (architecture.md): submitted as `media_meta` JSON + a
/// `file_<tempKey>` multipart field.
class PendingListingMedia {
  PendingListingMedia({
    required this.tempKey,
    required this.localPath,
    required this.mediaType,
    required this.displayOrder,
    this.isPrimary = false,
  });

  final String tempKey;
  final String localPath;
  // image | video
  final String mediaType;
  int displayOrder;
  bool isPrimary;

  bool get isVideo => mediaType == 'video';

  Map<String, dynamic> toMetaJson() => {
        'temp_key': tempKey,
        'display_order': displayOrder,
        'is_primary': isPrimary,
        'media_type': mediaType,
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
    required this.bathrooms,
    this.legalDocuments = const [],
    this.rooms = const [],
  });

  String dealType; // sale | lease
  double price;
  int? possessionPeriodDays;
  double sizeSquareMeters;
  String propertySubtype; // office | shop | home | land
  int bathrooms;
  List<String> legalDocuments;
  List<CommercialRoom> rooms;

  Map<String, dynamic> toJson() => {
        'deal_type': dealType,
        'price': price,
        'possession_period_days': possessionPeriodDays,
        'size_square_meters': sizeSquareMeters,
        'property_subtype': propertySubtype,
        'bathrooms': bathrooms,
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
        bathrooms: json['bathrooms'] as int? ?? 0,
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
    required this.bathrooms,
    required this.subtype,
    this.houseRules = const [],
    this.blockedDates = const [],
  });

  double nightlyPrice;
  int minimumStayNights;
  int? maximumStayNights;
  int bedrooms;
  int bathrooms;
  // hostel | hotel -- schema.md's ShortletListing.propertySubtype (product
  // decision). Previously also accepted 1_bedroom/2_bedroom/3_bedroom,
  // duplicating `bedrooms` above as a string enum instead of a count.
  String subtype;
  List<String> houseRules;
  List<String> blockedDates;

  Map<String, dynamic> toJson() => {
        'nightly_price': nightlyPrice,
        'minimum_stay_nights': minimumStayNights,
        'maximum_stay_nights': maximumStayNights,
        'bedrooms': bedrooms,
        'bathrooms': bathrooms,
        'subtype': subtype,
        'house_rules': houseRules,
        'blocked_dates': blockedDates,
      };

  factory ShortletListingDetails.fromJson(Map<String, dynamic> json) =>
      ShortletListingDetails(
        nightlyPrice: (json['nightly_price'] as num).toDouble(),
        minimumStayNights: json['minimum_stay_nights'] as int,
        maximumStayNights: json['maximum_stay_nights'] as int?,
        bedrooms: json['bedrooms'] as int,
        bathrooms: json['bathrooms'] as int? ?? 0,
        subtype: json['subtype'] as String? ?? 'hotel',
        houseRules: (json['house_rules'] as List? ?? [])
            .map((e) => e as String)
            .toList(),
        blockedDates: (json['blocked_dates'] as List? ?? [])
            .map((e) => e as String)
            .toList(),
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
    this.ownerClientName,
    this.media = const [],
    this.commercial,
    this.shortlet,
    this.hostBio,
    this.hostPhotoUrl,
    this.hostType,
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
  // FEAT-018 AC "originating client/owner" tagging -- an agency-entered
  // free-text label (e.g. a landlord's name), not a platform account. Null
  // for the vast majority of (non-agency) listings.
  final String? ownerClientName;
  final List<ListingMedia> media;
  final CommercialListingDetails? commercial;
  final ShortletListingDetails? shortlet;
  // FEAT-042: Host Profile card fields -- null only if the host account
  // row is somehow missing (defensive; shouldn't occur for a live
  // listing, since a HostAccount is required to create one at all).
  final String? hostBio;
  final String? hostPhotoUrl;
  final String? hostType;

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
        ownerClientName: json['owner_client_name'] as String?,
        media: (json['media'] as List? ?? [])
            .map((e) => ListingMedia.fromJson(e as Map<String, dynamic>))
            .toList(),
        commercial: json['commercial'] != null
            ? CommercialListingDetails.fromJson(
                json['commercial'] as Map<String, dynamic>)
            : null,
        shortlet: json['shortlet'] != null
            ? ShortletListingDetails.fromJson(
                json['shortlet'] as Map<String, dynamic>)
            : null,
        hostBio: json['host_bio'] as String?,
        hostPhotoUrl: json['host_photo_url'] as String?,
        hostType: json['host_type'] as String?,
      );
}
