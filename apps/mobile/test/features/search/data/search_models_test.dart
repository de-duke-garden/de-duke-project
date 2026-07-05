import 'package:flutter_test/flutter_test.dart';

import 'package:de_duke_mobile/features/search/data/search_models.dart';

void main() {
  group('SortDirection.apiValue', () {
    // Regression test: every filter/sort enum used to have an apiValue
    // extension except SortDirection, which crashed
    // SearchQueryState.toQueryParameters() at runtime the moment a caller
    // read sortDirection.apiValue (caught via `flutter analyze`, fixed by
    // adding the missing SortDirectionX extension).
    test('asc/desc match the backend query parameter values', () {
      expect(SortDirection.asc.apiValue, 'asc');
      expect(SortDirection.desc.apiValue, 'desc');
    });
  });

  group('ShortletSubtypeX.apiValue', () {
    test('bedroom variants map to underscored backend values', () {
      expect(ShortletSubtype.oneBedroom.apiValue, '1_bedroom');
      expect(ShortletSubtype.twoBedroom.apiValue, '2_bedroom');
      expect(ShortletSubtype.threeBedroom.apiValue, '3_bedroom');
      expect(ShortletSubtype.hostel.apiValue, 'hostel');
      expect(ShortletSubtype.hotel.apiValue, 'hotel');
    });
  });

  group('SearchQueryState.toQueryParameters', () {
    test('omits unset optional filters', () {
      const state = SearchQueryState();
      final params = state.toQueryParameters();

      expect(params.containsKey('min_price'), isFalse);
      expect(params.containsKey('bathrooms'), isFalse);
      expect(params['sort_by'], 'newest');
      expect(params['sort_direction'], 'desc');
      expect(params['verified_only'], false);
    });

    test('includes bathrooms and shortlet subtype once set (FEAT-007)', () {
      const state = SearchQueryState(
        bathrooms: 2,
        shortletSubtype: ShortletSubtype.twoBedroom,
      );
      final params = state.toQueryParameters();

      expect(params['bathrooms'], 2);
      expect(params['shortlet_subtype'], '2_bedroom');
    });

    test('activeFilterCount counts each distinct filter group once', () {
      const state = SearchQueryState(
        minPrice: 10000,
        maxPrice: 50000,
        bathrooms: 1,
        verifiedOnly: true,
      );
      // min/maxPrice count as ONE group, bathrooms as another, verifiedOnly
      // as a third -- 3 total, not 4.
      expect(state.activeFilterCount, 3);
    });
  });

  group('SearchQueryState.copyWith', () {
    test('clear flags null out a field independent of other values', () {
      const state = SearchQueryState(bathrooms: 2, minPrice: 10000);
      final cleared = state.copyWith(clearBathrooms: true);

      expect(cleared.bathrooms, isNull);
      expect(cleared.minPrice, 10000);
    });
  });
}
