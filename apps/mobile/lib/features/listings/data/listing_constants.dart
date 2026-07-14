/// Fixed vocabularies for listing fields that schema.md defines as
/// free-form/enum string lists but that Create Listing (screens.md Screen
/// 7 Step 2) never actually exposed any UI for -- confirmed real gaps:
/// `Listing.amenities` and `CommercialListing.legalDocuments` were always
/// silently submitted as empty arrays regardless of what a host might have
/// wanted to declare.
library;

/// One selectable amenity tag -- `value` is the wire string sent as an
/// entry in `Listing.amenities` (schema.md: "e.g., 'parking', 'generator',
/// 'air_conditioning'" -- free-form, no backend-enforced enum, but a fixed
/// checklist here keeps values consistent for search filtering (FEAT-007
/// AC: "filter by ... key amenities") rather than host-typed free text that
/// would never exactly match a filter's own value).
class AmenityOption {
  const AmenityOption(this.value, this.label);
  final String value;
  final String label;
}

const List<AmenityOption> kAmenityOptions = [
  AmenityOption('parking', 'Parking'),
  AmenityOption('generator', 'Generator'),
  AmenityOption('air_conditioning', 'Air Conditioning'),
  AmenityOption('water_supply', 'Water Supply'),
  AmenityOption('borehole', 'Borehole'),
  AmenityOption('security', '24/7 Security'),
  AmenityOption('cctv', 'CCTV'),
  AmenityOption('elevator', 'Elevator'),
  AmenityOption('wifi', 'Wi-Fi'),
  AmenityOption('furnished', 'Furnished'),
  AmenityOption('swimming_pool', 'Swimming Pool'),
  AmenityOption('gym', 'Gym'),
];

/// CommercialListing.legalDocuments' exact enum, schema.md: "Certificate of
/// Occupancy, Deed of Assignment, Power of Attorney, Survey Plan,
/// Governor's Consent" -- a closed set (unlike amenities above), so this is
/// a multi-select checklist, not an add-your-own-tag input.
class LegalDocumentOption {
  const LegalDocumentOption(this.value, this.label);
  final String value;
  final String label;
}

const List<LegalDocumentOption> kLegalDocumentOptions = [
  LegalDocumentOption('certificate_of_occupancy', 'Certificate of Occupancy'),
  LegalDocumentOption('deed_of_assignment', 'Deed of Assignment'),
  LegalDocumentOption('power_of_attorney', 'Power of Attorney'),
  LegalDocumentOption('survey_plan', 'Survey Plan'),
  LegalDocumentOption('governors_consent', "Governor's Consent"),
];
