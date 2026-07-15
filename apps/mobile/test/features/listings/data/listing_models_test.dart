import 'package:flutter_test/flutter_test.dart';

import 'package:de_duke_mobile/features/listings/data/listing_models.dart';

void main() {
  group('CommercialListingDetails', () {
    test('toJson includes bathrooms and legal_documents (FEAT-007 fields)', () {
      final details = CommercialListingDetails(
        dealType: 'lease',
        price: 1500000,
        possessionPeriodDays: 365,
        sizeSquareMeters: 120,
        propertySubtype: 'office',
        bathrooms: 2,
        legalDocuments: const ['certificate_of_occupancy'],
      );

      final json = details.toJson();
      expect(json['deal_type'], 'lease');
      expect(json['bathrooms'], 2);
      expect(json['legal_documents'], ['certificate_of_occupancy']);
    });

    test('fromJson defaults bathrooms to 0 when absent from an older payload',
        () {
      final details = CommercialListingDetails.fromJson({
        'deal_type': 'sale',
        'price': 5000000,
        'size_square_meters': 200,
        'property_subtype': 'land',
      });
      expect(details.bathrooms, 0);
      expect(details.legalDocuments, isEmpty);
    });
  });

  group('ShortletListingDetails', () {
    test('toJson includes subtype and bathrooms', () {
      final details = ShortletListingDetails(
        nightlyPrice: 45000,
        minimumStayNights: 2,
        bedrooms: 2,
        bathrooms: 1,
        subtype: 'hostel',
      );

      final json = details.toJson();
      expect(json['subtype'], 'hostel');
      expect(json['bathrooms'], 1);
      expect(json['bedrooms'], 2);
    });

    // schema.md's ShortletListing.propertySubtype is scoped to hotel|hostel
    // only (product decision) -- previously also had 1/2/3-bedroom values
    // duplicating `bedrooms` as a string enum instead of a count.
    test('fromJson defaults subtype to hotel when absent', () {
      final details = ShortletListingDetails.fromJson({
        'nightly_price': 30000,
        'minimum_stay_nights': 1,
        'bedrooms': 1,
      });
      expect(details.subtype, 'hotel');
      expect(details.bathrooms, 0);
    });
  });

  group('Listing.fromJson', () {
    test('parses a commercial listing with nested details', () {
      final listing = Listing.fromJson({
        'id': 'listing-1',
        'host_account_id': 'ha-1',
        'listing_type': 'commercial',
        'title': 'Office space',
        'description': 'Open plan office',
        'location_latitude': 6.5244,
        'location_longitude': 3.3792,
        'location_address_line': '1 Admiralty Way',
        'location_city': 'Lagos',
        'location_state': 'Lagos',
        'amenities': ['parking'],
        'status': 'active',
        'view_count': 10,
        'commercial': {
          'deal_type': 'lease',
          'price': 1500000,
          'size_square_meters': 120,
          'property_subtype': 'office',
          'bathrooms': 2,
        },
      });

      expect(listing.isVerifiedActive, isTrue);
      expect(listing.commercial, isNotNull);
      expect(listing.commercial!.propertySubtype, 'office');
      expect(listing.shortlet, isNull);
    });

    test('parses host bio/photo/type when present (FEAT-042)', () {
      final listing = Listing.fromJson({
        'id': 'listing-1',
        'host_account_id': 'ha-1',
        'listing_type': 'commercial',
        'title': 'Office space',
        'description': 'Open plan office',
        'location_latitude': 6.5244,
        'location_longitude': 3.3792,
        'location_address_line': '1 Admiralty Way',
        'location_city': 'Lagos',
        'location_state': 'Lagos',
        'amenities': <String>[],
        'status': 'active',
        'view_count': 10,
        'host_bio': 'A friendly, verified host.',
        'host_photo_url': 'https://example.com/host.jpg',
        'host_type': 'owner',
      });

      expect(listing.hostBio, 'A friendly, verified host.');
      expect(listing.hostPhotoUrl, 'https://example.com/host.jpg');
      expect(listing.hostType, 'owner');
    });

    test('defaults host fields to null when absent from an older payload', () {
      final listing = Listing.fromJson({
        'id': 'listing-1',
        'host_account_id': 'ha-1',
        'listing_type': 'commercial',
        'title': 'Office space',
        'description': 'Open plan office',
        'location_latitude': 6.5244,
        'location_longitude': 3.3792,
        'location_address_line': '1 Admiralty Way',
        'location_city': 'Lagos',
        'location_state': 'Lagos',
        'amenities': <String>[],
        'status': 'active',
        'view_count': 10,
      });

      expect(listing.hostBio, isNull);
      expect(listing.hostPhotoUrl, isNull);
      expect(listing.hostType, isNull);
    });
  });
}
