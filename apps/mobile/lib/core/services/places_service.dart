/// Google Maps Platform Places/Geocoding REST APIs -- backs Create
/// Listing's bidirectional address/map-pin sync:
///   - `reverseGeocode`: dropping/dragging a map pin (or a GPS fix) resolves
///     to a human-readable address, auto-filling the address/city/state
///     fields.
///   - `autocompleteAddress` + `placeDetails`: typing in the address field
///     shows real, selectable suggestions; selecting one resolves to a
///     coordinate that drops/moves the map pin. This is also what keeps a
///     listing's address from being an untraceable free-text string -- the
///     coordinate is only ever set from a real Google-resolved place or a
///     device-read GPS/pin location, never typed by hand.
///
/// Deliberately a plain top-level set of functions on their own `Dio`
/// instance, not routed through `core/api/api_client.dart`'s `ApiClient` --
/// that client is scoped to the De-Duke backend (base URL + bearer auth
/// interceptor), neither of which apply to a direct call to Google's API.
library;

import 'package:dio/dio.dart';

import '../config/env.dart';

final Dio _dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 10)));

/// A resolved reverse-geocoding result. Any field may be empty if Google's
/// response didn't include that address component for the given point.
class ReverseGeocodeResult {
  const ReverseGeocodeResult({
    required this.formattedAddress,
    required this.city,
    required this.state,
  });

  final String formattedAddress;
  final String city;
  final String state;
}

/// One Places Autocomplete suggestion -- `placeId` is opaque, only used to
/// look up full details (including the coordinate) via [placeDetails].
class PlaceSuggestion {
  const PlaceSuggestion({required this.placeId, required this.description});

  final String placeId;
  final String description;
}

/// A resolved place: coordinate + the address Google considers canonical
/// for it (may differ slightly in formatting from the suggestion's
/// description).
class PlaceDetails {
  const PlaceDetails({
    required this.latitude,
    required this.longitude,
    required this.formattedAddress,
    required this.city,
    required this.state,
  });

  final double latitude;
  final double longitude;
  final String formattedAddress;
  final String city;
  final String state;
}

String _componentFor(List<dynamic> components, String type) {
  for (final c in components) {
    final map = c as Map<String, dynamic>;
    final types = (map['types'] as List<dynamic>?) ?? [];
    if (types.contains(type)) return map['long_name'] as String? ?? '';
  }
  return '';
}

/// 'locality' is Google's city-equivalent; falls back to
/// 'administrative_area_level_2' (LGA in Nigerian addresses) since
/// 'locality' is sometimes absent for less built-up areas.
String _cityFrom(List<dynamic> components) {
  final locality = _componentFor(components, 'locality');
  return locality.isNotEmpty
      ? locality
      : _componentFor(components, 'administrative_area_level_2');
}

/// Looks up the address for [latitude]/[longitude]. Returns null if
/// `GOOGLE_MAPS_API_KEY` isn't configured, the request fails, or Google
/// returns no results -- callers should treat null as "leave the address
/// fields for the user to fill in manually", not as an error to surface,
/// since reverse geocoding is a convenience, not a required step.
Future<ReverseGeocodeResult?> reverseGeocode(
    double latitude, double longitude) async {
  if (AppConfig.googleMapsApiKey.isEmpty) return null;

  try {
    final response = await _dio.get<Map<String, dynamic>>(
      'https://maps.googleapis.com/maps/api/geocode/json',
      queryParameters: {
        'latlng': '$latitude,$longitude',
        'key': AppConfig.googleMapsApiKey,
      },
    );

    final data = response.data;
    if (data == null || data['status'] != 'OK') return null;
    final results = data['results'] as List<dynamic>?;
    if (results == null || results.isEmpty) return null;

    final first = results.first as Map<String, dynamic>;
    final components = (first['address_components'] as List<dynamic>?) ?? [];

    return ReverseGeocodeResult(
      formattedAddress: first['formatted_address'] as String? ?? '',
      city: _cityFrom(components),
      state: _componentFor(components, 'administrative_area_level_1'),
    );
  } on DioException {
    return null;
  }
}

/// Fetches address suggestions for partial user input, e.g. as they type in
/// the address field. [sessionToken] should be a stable value (a fresh uuid
/// per "typing session") shared with the subsequent [placeDetails] call --
/// Google's Autocomplete + Place Details billing is discounted when both
/// calls in a lookup share one session token. Returns an empty list (never
/// null) so callers can render "no suggestions" without a separate null
/// check -- a truly failed/unconfigured lookup looks the same as "nothing
/// matched" to the UI, which is the right degradation for a convenience
/// feature.
Future<List<PlaceSuggestion>> autocompleteAddress(
  String input, {
  String? sessionToken,
}) async {
  if (AppConfig.googleMapsApiKey.isEmpty || input.trim().length < 3) {
    return const [];
  }

  try {
    final response = await _dio.get<Map<String, dynamic>>(
      'https://maps.googleapis.com/maps/api/place/autocomplete/json',
      queryParameters: {
        'input': input,
        'key': AppConfig.googleMapsApiKey,
        // Biases (does not hard-restrict) results toward Nigeria, matching
        // De-Duke's Nigerian real estate market -- see AGENTS.md.
        'components': 'country:ng',
        if (sessionToken != null) 'sessiontoken': sessionToken,
      },
    );

    final data = response.data;
    if (data == null || data['status'] != 'OK') return const [];
    final predictions = data['predictions'] as List<dynamic>?;
    if (predictions == null) return const [];

    return predictions
        .map((p) {
          final map = p as Map<String, dynamic>;
          return PlaceSuggestion(
            placeId: map['place_id'] as String? ?? '',
            description: map['description'] as String? ?? '',
          );
        })
        .where((s) => s.placeId.isNotEmpty)
        .toList();
  } on DioException {
    return const [];
  }
}

/// Resolves a suggestion's `placeId` (from [autocompleteAddress]) to its
/// coordinate + canonical address. Returns null on failure/no-key, same
/// degradation contract as [reverseGeocode].
Future<PlaceDetails?> placeDetails(
  String placeId, {
  String? sessionToken,
}) async {
  if (AppConfig.googleMapsApiKey.isEmpty) return null;

  try {
    final response = await _dio.get<Map<String, dynamic>>(
      'https://maps.googleapis.com/maps/api/place/details/json',
      queryParameters: {
        'place_id': placeId,
        'fields': 'geometry,formatted_address,address_component',
        'key': AppConfig.googleMapsApiKey,
        if (sessionToken != null) 'sessiontoken': sessionToken,
      },
    );

    final data = response.data;
    if (data == null || data['status'] != 'OK') return null;
    final result = data['result'] as Map<String, dynamic>?;
    if (result == null) return null;

    final geometry = result['geometry'] as Map<String, dynamic>?;
    final location = geometry?['location'] as Map<String, dynamic>?;
    if (location == null) return null;
    final lat = (location['lat'] as num?)?.toDouble();
    final lng = (location['lng'] as num?)?.toDouble();
    if (lat == null || lng == null) return null;

    final components =
        (result['address_components'] as List<dynamic>?) ?? [];

    return PlaceDetails(
      latitude: lat,
      longitude: lng,
      formattedAddress: result['formatted_address'] as String? ?? '',
      city: _cityFrom(components),
      state: _componentFor(components, 'administrative_area_level_1'),
    );
  } on DioException {
    return null;
  }
}
