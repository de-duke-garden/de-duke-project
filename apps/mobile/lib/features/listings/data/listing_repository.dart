/// Repository wrapping the Backend API Service's /v1/listings endpoints.
/// Screens depend on this, never on Dio/ApiClient directly, so error
/// handling and JSON parsing stay in one place per feature.
library;

import 'dart:convert';

import 'package:dio/dio.dart';

import '../../../core/api/api_client.dart';
import 'listing_models.dart';

class ListingRepository {
  ListingRepository(this._apiClient);

  final ApiClient _apiClient;

  Future<Listing> createListing({
    required String listingType,
    required String title,
    required String description,
    required double latitude,
    required double longitude,
    required String addressLine,
    required String city,
    required String state,
    List<String> amenities = const [],
    CommercialListingDetails? commercial,
    ShortletListingDetails? shortlet,
  }) async {
    final body = {
      'listing_type': listingType,
      'title': title,
      'description': description,
      'location': {
        'latitude': latitude,
        'longitude': longitude,
        'address_line': addressLine,
        'city': city,
        'state': state,
      },
      'amenities': amenities,
      if (commercial != null) 'commercial': commercial.toJson(),
      if (shortlet != null) 'shortlet': shortlet.toJson(),
    };
    final response = await _apiClient.dio.post('/v1/listings', data: body);
    return Listing.fromJson(response.data as Map<String, dynamic>);
  }

  Future<Listing> getListing(String listingId) async {
    final response = await _apiClient.dio.get('/v1/listings/$listingId');
    return Listing.fromJson(response.data as Map<String, dynamic>);
  }

  /// FEAT-004 AC "Host can edit the price, location, or other details, or
  /// unpublish an existing listing" -- PATCH /v1/listings/:id. Every
  /// parameter is optional/partial-update (mirrors the backend's
  /// ListingUpdateIn): only the fields actually passed are sent, so a
  /// caller that's only flipping `status` doesn't accidentally overwrite
  /// `commercial`/`shortlet` with nothing.
  ///
  /// `status` is intentionally narrower than the full set of values a
  /// listing can have (`active | under_review | banned | unpublished`) --
  /// a host can only toggle between `active` and `unpublished` themselves;
  /// the backend rejects anything else or any attempt to change status
  /// while under moderation (see app/api/v1/listings.py's
  /// update_listing_endpoint).
  Future<Listing> updateListing(
    String listingId, {
    String? title,
    String? description,
    double? latitude,
    double? longitude,
    String? addressLine,
    String? city,
    String? state,
    List<String>? amenities,
    String? status,
    // FEAT-018 AC "originating client/owner" tagging -- pass '' (not null)
    // to explicitly clear a previously-set tag; omit entirely to leave it
    // untouched, same convention as every other partial-update field here.
    String? ownerClientName,
    CommercialListingDetails? commercial,
    ShortletListingDetails? shortlet,
  }) async {
    final body = {
      if (title != null) 'title': title,
      if (description != null) 'description': description,
      if (ownerClientName != null) 'owner_client_name': ownerClientName,
      if (latitude != null &&
          longitude != null &&
          addressLine != null &&
          city != null &&
          state != null)
        'location': {
          'latitude': latitude,
          'longitude': longitude,
          'address_line': addressLine,
          'city': city,
          'state': state,
        },
      if (amenities != null) 'amenities': amenities,
      if (status != null) 'status': status,
      if (commercial != null) 'commercial': commercial.toJson(),
      if (shortlet != null) 'shortlet': shortlet.toJson(),
    };
    final response =
        await _apiClient.dio.patch('/v1/listings/$listingId', data: body);
    return Listing.fromJson(response.data as Map<String, dynamic>);
  }

  /// Uploads locally-picked images using the structured multi-file contract:
  /// `images_meta` (JSON) + one `file_<tempKey>` multipart field per image.
  Future<void> uploadImages(
    String listingId,
    List<PendingListingImage> images,
  ) async {
    final formMap = <String, dynamic>{
      'images_meta': jsonEncode(images.map((i) => i.toMetaJson()).toList()),
    };
    for (final image in images) {
      formMap['file_${image.tempKey}'] =
          await MultipartFile.fromFile(image.localPath);
    }
    await _apiClient.dio.post(
      '/v1/listings/$listingId/images',
      data: FormData.fromMap(formMap),
    );
  }

  Future<({bool available, List<String> conflictingDates})> checkAvailability(
    String listingId, {
    required DateTime start,
    required DateTime end,
  }) async {
    final response = await _apiClient.dio.get(
      '/v1/listings/$listingId/availability',
      queryParameters: {
        'start_date': start.toIso8601String().split('T').first,
        'end_date': end.toIso8601String().split('T').first,
      },
    );
    final data = response.data as Map<String, dynamic>;
    return (
      available: data['available'] as bool,
      conflictingDates: (data['conflicting_dates'] as List? ?? [])
          .map((e) => e as String)
          .toList(),
    );
  }
}
