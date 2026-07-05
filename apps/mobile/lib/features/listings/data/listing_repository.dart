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
