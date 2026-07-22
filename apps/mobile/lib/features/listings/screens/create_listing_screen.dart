/// screens.md Screen 7: Create Listing.
///
/// Covers: listing type + commercial/shortlet subtype fields, the
/// three-method location input (map pin drop / address autocomplete / "use
/// my GPS location" -- all three resolve to the same lat/lng+address
/// fields sent to the server), a combined photo/video media picker with
/// reorder + primary flag (FEAT-004/FEAT-005 video support, product-shaped
/// via product-shaper -- a video can never be primary, see
/// PendingListingMedia's docstring), commercial room breakdown, and
/// submitting/validation/error/offline states.
///
/// Structured as a 5-step wizard per screens.md's Layout section:
///   1. Listing type (Commercial vs. Shortlet) via large selectable cards
///   2. Type-specific detail form (+ title/description, common to both
///      types and not called out as their own step in the doc)
///   3. Location (Location Input subsection)
///   4. Media (photo + video) upload grid
///   5. Review + Publish
/// All step state lives in this single State object (form fields, media
/// objects, room entries, resolved lat/lng) and persists across step
/// navigation since every step's widget subtree stays mounted inside the
/// `PageView` for the lifetime of this screen.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/services/places_service.dart';
import '../../../core/theme/app_semantic_colors.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/enum_display.dart';
import '../../../core/widgets/address_autocomplete_field.dart';
import '../../../core/widgets/celebratory_sequence.dart';
import '../../../core/widgets/image_source_picker.dart'
    show pickImageFromCameraOrGallery, pickVideoFromCameraOrGallery;
import '../data/listing_constants.dart';
import '../data/listing_models.dart';
import '../data/listing_repository.dart';

enum LocationInputMethod { mapPin, addressSearch, gps }

enum _SubmitState { idle, submitting, success, error, offline }

const int _stepCount = 5;
const List<String> _stepTitles = [
  'Type',
  'Details',
  'Location',
  'Media',
  'Review',
];

class CreateListingScreen extends StatefulWidget {
  const CreateListingScreen({super.key, required this.repository});

  final ListingRepository repository;

  @override
  State<CreateListingScreen> createState() => _CreateListingScreenState();
}

class _CreateListingScreenState extends State<CreateListingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _pageController = PageController();

  int _currentStep = 0;
  // Set only when a "Next" tap is blocked, so the current step can render
  // an inline hint per screens.md's Validation Error / Location Not Set
  // states, without disturbing the shared Form's own field-level errors.
  String? _stepBlockedMessage;

  String _listingType = 'commercial';
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();

  // Location (all three input methods write into these same fields).
  LocationInputMethod _locationMethod = LocationInputMethod.mapPin;
  double? _latitude;
  double? _longitude;
  final _addressController = TextEditingController();
  final _cityController = TextEditingController();
  final _stateController = TextEditingController();
  GoogleMapController? _mapController;

  // Commercial fields.
  String _dealType = 'sale';
  final _priceController = TextEditingController();
  // Confirmed real gap: "Size" was a single free-typed sqm field with no
  // way to express it as actual room dimensions. Split into Length x
  // Width -- schema.md/the backend still only stores a single
  // size_square_meters value, so the product of these two is what's sent
  // (see _buildReviewStep/_submit), matching how a host actually measures
  // a room in practice. Named "Width" (not "Breadth") to match
  // CommercialListingRoom.widthMeters' naming in schema.md exactly.
  final _lengthController = TextEditingController();
  final _widthController = TextEditingController();
  String _propertySubtype = 'office';
  final _commercialBathroomsController = TextEditingController();
  final _possessionDaysController = TextEditingController();
  final List<CommercialRoom> _rooms = [];
  // Confirmed real gap: schema.md's CommercialListing.legalDocuments is a
  // required field (schema.md: shown to guests "as a trust signal,
  // particularly for Sale listings") but this form never rendered any UI
  // for it -- every listing silently submitted an empty list regardless of
  // what documents the host actually has.
  final Set<String> _legalDocuments = {};

  // Shortlet fields.
  final _nightlyPriceController = TextEditingController();
  final _minStayController = TextEditingController();
  final _maxStayController = TextEditingController();
  final _bedroomsController = TextEditingController();
  final _shortletBathroomsController = TextEditingController();
  // hostel | hotel -- schema.md's ShortletListing.propertySubtype (product
  // decision: docs/De-Duke/schema.md). Previously defaulted to '1_bedroom',
  // a value that duplicated `_bedroomsController` as a string enum instead
  // of a count and is no longer accepted by the backend.
  String _shortletSubtype = 'hotel';
  final List<String> _houseRules = [];
  final _houseRuleController = TextEditingController();
  // ISO date strings (YYYY-MM-DD) -- schema.md's
  // ShortletListing.blockedDates. Confirmed real gap: declared on the
  // model since the start (see the pre-existing `_houseRules` field right
  // above) but never had any UI to actually populate it, same as
  // `_houseRules` did before this change.
  final List<String> _blockedDates = [];

  // Shared -- schema.md's base Listing.amenities (free-form tag list, "e.g.,
  // 'parking', 'generator', 'air_conditioning'"). Confirmed real gap: no UI
  // existed anywhere in this form; every listing silently submitted an
  // empty amenities array regardless of what the host actually offers.
  final Set<String> _amenities = {};

  final List<PendingListingMedia> _media = [];

  // FEAT-004/FEAT-005 AC -- server-enforced cap (listing_service.
  // MAX_VIDEOS_PER_LISTING), mirrored client-side so "Add video" disables
  // itself with a clear reason rather than letting the user pick a 6th
  // clip only to have the upload rejected after the fact.
  static const int _maxVideos = 5;
  static const int _maxVideoBytes = 100 * 1024 * 1024;

  int get _videoCount => _media.where((m) => m.isVideo).length;

  _SubmitState _state = _SubmitState.idle;
  String? _errorMessage;
  int _tempKeyCounter = 0;
  Listing? _publishedListing;

  /// Backend/schema.md still only stores a single `size_square_meters`
  /// value (see CommercialListingDetails) -- this is the product of the
  /// Length x Width fields a host actually fills in, computed once here
  /// rather than duplicated at every call site.
  double get _computedSizeSquareMeters {
    final length = double.tryParse(_lengthController.text) ?? 0;
    final width = double.tryParse(_widthController.text) ?? 0;
    return length * width;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _addressController.dispose();
    _cityController.dispose();
    _stateController.dispose();
    _priceController.dispose();
    _lengthController.dispose();
    _widthController.dispose();
    _possessionDaysController.dispose();
    _nightlyPriceController.dispose();
    _minStayController.dispose();
    _maxStayController.dispose();
    _bedroomsController.dispose();
    _commercialBathroomsController.dispose();
    _shortletBathroomsController.dispose();
    _houseRuleController.dispose();
    _mapController?.dispose();
    _pageController.dispose();
    super.dispose();
  }

  /// Shared by the map's onTap and the marker's onDragEnd -- both resolve to
  /// "the user placed the pin here", just via different gestures. Also
  /// kicks off reverse geocoding so the address/city/state fields fill in
  /// automatically -- the pin is the source of truth for location, so
  /// whatever address Google resolves for it overwrites any address text
  /// already there (including one the user typed by hand and didn't pick a
  /// suggestion for, which never had a coordinate attached anyway).
  void _setMapPin(LatLng position) {
    setState(() {
      _latitude = position.latitude;
      _longitude = position.longitude;
    });
    _fillAddressFromCoordinates(position.latitude, position.longitude);
  }

  /// Reverse-geocodes [latitude]/[longitude] and writes the result into the
  /// address/city/state fields. No-ops quietly (leaves whatever's already
  /// in those fields) if geocoding is unconfigured or the lookup fails --
  /// this is a convenience autofill, not a required step, per
  /// `places_service.dart`'s degradation contract.
  Future<void> _fillAddressFromCoordinates(
      double latitude, double longitude) async {
    final result = await reverseGeocode(latitude, longitude);
    if (!mounted || result == null) return;
    setState(() {
      if (result.formattedAddress.isNotEmpty) {
        _addressController.text = result.formattedAddress;
      }
      if (result.city.isNotEmpty) _cityController.text = result.city;
      if (result.state.isNotEmpty) _stateController.text = result.state;
    });
  }

  /// Handles a Places Autocomplete selection from the address field --
  /// the address half of the bidirectional sync. A selected suggestion is
  /// the only way the address field is allowed to set a coordinate (plain
  /// typed text never does), which is what keeps a listing's address from
  /// being an untraceable free-text string: it always resolves through a
  /// real Google-verified place, a map pin, or a device GPS reading.
  /// Switches to the Map pin tab and re-centers/animates the map so the
  /// dropped pin is immediately visible, confirming what was picked.
  void _applyPlaceSelection(PlaceDetails details) {
    setState(() {
      _latitude = details.latitude;
      _longitude = details.longitude;
      if (details.city.isNotEmpty) _cityController.text = details.city;
      if (details.state.isNotEmpty) _stateController.text = details.state;
      _locationMethod = LocationInputMethod.mapPin;
    });
    _mapController?.animateCamera(
      CameraUpdate.newLatLngZoom(
          LatLng(details.latitude, details.longitude), 16),
    );
  }

  /// Reads the device's actual coordinates via geolocator. Switches the
  /// segmented control to GPS regardless of outcome (screens.md's three
  /// input methods are always mutually exclusive selections), but only
  /// populates _latitude/_longitude on success -- `_locationValidationError`
  /// already treats a null lat/lng as "no location set yet" and blocks
  /// submission with a clear message, so a failed GPS read degrades to the
  /// same validation path a user would hit by not picking a method at all.
  Future<void> _useGpsLocation() async {
    setState(() => _locationMethod = LocationInputMethod.gps);

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _showLocationMessage(
          'Location services are turned off. Enable them in system settings.');
      return;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      _showLocationMessage('Location permission denied.');
      return;
    }
    if (permission == LocationPermission.deniedForever) {
      _showLocationMessage(
          'Location permission permanently denied. Enable it from app settings.');
      return;
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      if (!mounted) return;
      setState(() {
        _latitude = position.latitude;
        _longitude = position.longitude;
      });
      _fillAddressFromCoordinates(position.latitude, position.longitude);
    } on TimeoutException {
      _showLocationMessage('Timed out getting your location. Try again.');
    } catch (_) {
      _showLocationMessage('Could not get your location. Try again.');
    }
  }

  void _showLocationMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _addPickedPhoto() async {
    final path = await pickImageFromCameraOrGallery(context);
    if (path == null || !mounted) return;

    final key = 'img_${_tempKeyCounter++}';
    // Confirmed real bug: every photo showed the same thumbnail. image_picker
    // (particularly camera capture on Android) can hand back the SAME cache
    // file path across separate picks -- and Flutter's Image.file/FileImage
    // decode cache is keyed only by (path, scale), never by file content or
    // modification time (a documented Flutter caveat), so a repeated path
    // serves the first photo's already-cached bytes for every later pick
    // that reuses it. Copying to a filename unique to this PendingListingMedia
    // guarantees no two entries ever share a cache key, regardless of what
    // path image_picker happens to reuse internally.
    final original = File(path);
    final uniquePath =
        '${original.parent.path}/listing_photo_$key${_extensionOf(path)}';
    final localFile = await original.copy(uniquePath);

    if (!mounted) return;
    setState(() {
      _media.add(
        PendingListingMedia(
          tempKey: key,
          localPath: localFile.path,
          mediaType: 'image',
          displayOrder: _media.length,
          // Only the very first media item overall defaults to primary --
          // matches the pre-video behavior (first PHOTO was primary) since
          // a video can never be primary anyway (isEmpty check below would
          // otherwise wrongly default a photo added after some videos to
          // non-primary even when it's the listing's first photo).
          isPrimary: _media.every((m) => !m.isVideo) && _media.isEmpty,
        ),
      );
    });
  }

  /// FEAT-004/FEAT-005 video support -- same picked-media flow as
  /// `_addPickedPhoto`, but for a video clip. Client-side checks (count
  /// cap, file size) fail fast with a clear message rather than letting an
  /// obviously-oversized upload reach the server only to be rejected there
  /// (listing_service.MAX_VIDEO_BYTES/MAX_VIDEOS_PER_LISTING remain the
  /// authoritative check either way).
  Future<void> _addPickedVideo() async {
    if (_videoCount >= _maxVideos) {
      _showLocationMessage('A listing can have at most $_maxVideos videos.');
      return;
    }

    final path = await pickVideoFromCameraOrGallery(context);
    if (path == null || !mounted) return;

    final original = File(path);
    final sizeBytes = await original.length();
    if (sizeBytes > _maxVideoBytes) {
      if (!mounted) return;
      _showLocationMessage(
          'That video is larger than ${_maxVideoBytes ~/ (1024 * 1024)}MB -- pick a shorter/lower-resolution clip.');
      return;
    }

    final key = 'vid_${_tempKeyCounter++}';
    final uniquePath =
        '${original.parent.path}/listing_video_$key${_extensionOf(path)}';
    final localFile = await original.copy(uniquePath);

    if (!mounted) return;
    setState(() {
      _media.add(
        PendingListingMedia(
          tempKey: key,
          localPath: localFile.path,
          mediaType: 'video',
          displayOrder: _media.length,
          isPrimary: false, // a video can never be primary
        ),
      );
    });
  }

  String _extensionOf(String path) {
    final dotIndex = path.lastIndexOf('.');
    return dotIndex == -1 ? '' : path.substring(dotIndex);
  }

  void _reorderMedia(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final item = _media.removeAt(oldIndex);
      _media.insert(newIndex, item);
      for (var i = 0; i < _media.length; i++) {
        _media[i].displayOrder = i;
      }
    });
  }

  /// A video can never be primary (schema.md's documented invariant, same
  /// restriction MediaMetaIn enforces server-side) -- callers only ever
  /// reach this from a photo tile's star button, but guarded here too
  /// defensively.
  void _setPrimaryMedia(int index) {
    if (_media[index].isVideo) return;
    setState(() {
      for (var i = 0; i < _media.length; i++) {
        _media[i].isPrimary = i == index;
      }
    });
  }

  /// Confirmed real gap: there was no way to remove a picked photo once
  /// added -- only reorder and set-primary existed. Re-numbers
  /// displayOrder and, if the removed item was primary, promotes the new
  /// first PHOTO (never a video) so a listing is never left with zero
  /// primary images while it still has at least one photo.
  void _removeMedia(int index) {
    setState(() {
      final wasPrimary = _media[index].isPrimary;
      _media.removeAt(index);
      for (var i = 0; i < _media.length; i++) {
        _media[i].displayOrder = i;
      }
      if (wasPrimary) {
        final firstPhotoIndex = _media.indexWhere((m) => !m.isVideo);
        if (firstPhotoIndex != -1) _media[firstPhotoIndex].isPrimary = true;
      }
    });
  }

  String? _locationValidationError() {
    if (_latitude == null || _longitude == null) {
      if (_locationMethod == LocationInputMethod.addressSearch &&
          _addressController.text.trim().isNotEmpty) {
        return null; // address-only path resolves server-side/geocoding TODO
      }
      return 'Set a location using the map, address search, or GPS.';
    }
    return null;
  }

  /// Per-step gating for the "Next" button, matching screens.md's
  /// In Progress/Validation Error/Location Not Set states: each step must
  /// resolve its own required fields before the wizard advances. Full,
  /// authoritative validation (including every `TextFormField`'s
  /// validator) still runs at final Publish via `_formKey`, since every
  /// step's fields remain mounted for the life of this screen.
  String? _blockingMessageForStep(int step) {
    switch (step) {
      case 0:
        return null; // a listing type is always selected by default
      case 1:
        if (_titleController.text.trim().isEmpty) {
          return 'Enter a title to continue.';
        }
        if (_descriptionController.text.trim().isEmpty) {
          return 'Enter a description to continue.';
        }
        if (_listingType == 'commercial') {
          if (double.tryParse(_priceController.text) == null) {
            return 'Enter a valid price to continue.';
          }
          if (double.tryParse(_lengthController.text) == null ||
              double.tryParse(_widthController.text) == null) {
            return 'Enter a valid length and width to continue.';
          }
          if (int.tryParse(_commercialBathroomsController.text) == null) {
            return 'Enter a valid bathroom count to continue.';
          }
        } else {
          if (double.tryParse(_nightlyPriceController.text) == null) {
            return 'Enter a valid nightly price to continue.';
          }
          if (int.tryParse(_minStayController.text) == null) {
            return 'Enter a valid minimum stay to continue.';
          }
          if (int.tryParse(_bedroomsController.text) == null) {
            return 'Enter a valid bedroom count to continue.';
          }
          if (int.tryParse(_shortletBathroomsController.text) == null) {
            return 'Enter a valid bathroom count to continue.';
          }
        }
        return null;
      case 2:
        // screens.md "Location Not Set" state.
        return _locationValidationError() == null
            ? null
            : 'Set the property location to continue';
      case 3:
        return null; // photos are optional, per screens.md's data flow
      default:
        return null;
    }
  }

  Future<void> _goNext() async {
    if (_currentStep == _stepCount - 1) {
      await _submit();
      return;
    }
    final blocked = _blockingMessageForStep(_currentStep);
    if (blocked != null) {
      setState(() => _stepBlockedMessage = blocked);
      return;
    }
    setState(() {
      _stepBlockedMessage = null;
      _currentStep += 1;
    });
    _pageController.animateToPage(
      _currentStep,
      duration: AppDurations.pageTransition,
      curve: AppCurves.easeOutSmooth,
    );
  }

  void _goBack() {
    if (_currentStep == 0) return;
    setState(() {
      _stepBlockedMessage = null;
      _currentStep -= 1;
    });
    _pageController.animateToPage(
      _currentStep,
      duration: AppDurations.pageTransition,
      curve: AppCurves.easeOutSmooth,
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final locationError = _locationValidationError();
    if (locationError != null) {
      setState(() {
        _state = _SubmitState.error;
        _errorMessage = locationError;
      });
      return;
    }

    setState(() {
      _state = _SubmitState.submitting;
      _errorMessage = null;
    });

    try {
      final listing = await widget.repository.createListing(
        listingType: _listingType,
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        latitude: _latitude ?? 0,
        longitude: _longitude ?? 0,
        addressLine: _addressController.text.trim(),
        city: _cityController.text.trim(),
        state: _stateController.text.trim(),
        amenities: _amenities.toList(),
        commercial: _listingType == 'commercial'
            ? CommercialListingDetails(
                dealType: _dealType,
                price: double.tryParse(_priceController.text) ?? 0,
                possessionPeriodDays: _dealType == 'lease'
                    ? int.tryParse(_possessionDaysController.text)
                    : null,
                sizeSquareMeters: _computedSizeSquareMeters,
                propertySubtype: _propertySubtype,
                bathrooms:
                    int.tryParse(_commercialBathroomsController.text) ?? 0,
                legalDocuments: _legalDocuments.toList(),
                rooms: _rooms,
              )
            : null,
        shortlet: _listingType == 'shortlet'
            ? ShortletListingDetails(
                nightlyPrice:
                    double.tryParse(_nightlyPriceController.text) ?? 0,
                minimumStayNights: int.tryParse(_minStayController.text) ?? 1,
                maximumStayNights: int.tryParse(_maxStayController.text),
                bedrooms: int.tryParse(_bedroomsController.text) ?? 0,
                bathrooms: int.tryParse(_shortletBathroomsController.text) ?? 0,
                subtype: _shortletSubtype,
                houseRules: _houseRules,
                blockedDates: _blockedDates,
              )
            : null,
      );

      if (_media.isNotEmpty) {
        await widget.repository.uploadMedia(listing.id, _media);
      }

      if (!mounted) return;
      // screens.md Success state: "Confirmation screen: 'Your listing is
      // live' with a link to view it" -- shown here (celebratory-sequence,
      // per Modernization Notes) rather than popping immediately; the pop
      // happens once the host dismisses the confirmation below.
      setState(() {
        _state = _SubmitState.success;
        _publishedListing = listing;
      });
    } on Exception catch (e) {
      final message = e.toString();
      setState(() {
        _state = message.contains('SocketException') ||
                message.contains('connection')
            ? _SubmitState.offline
            : _SubmitState.error;
        _errorMessage = message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_state == _SubmitState.success && _publishedListing != null) {
      return _ListingLiveScreen(
        listing: _publishedListing!,
        onDone: () => Navigator.of(context).pop(_publishedListing),
      );
    }
    final submitting = _state == _SubmitState.submitting;
    return Scaffold(
      appBar: AppBar(
        title: const Text('New Listing'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(40),
          child: _StepIndicator(currentStep: _currentStep),
        ),
      ),
      body: Form(
        key: _formKey,
        child: Column(
          children: [
            if (_state == _SubmitState.offline)
              Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: const _Banner(
                  icon: Icons.wifi_off,
                  message:
                      "You're offline. We'll need a connection to publish this listing.",
                ),
              ),
            if (_state == _SubmitState.error && _errorMessage != null)
              Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child:
                    _Banner(icon: Icons.error_outline, message: _errorMessage!),
              ),
            if (_stepBlockedMessage != null)
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md, vertical: AppSpacing.xs),
                child: Text(
                  _stepBlockedMessage!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            Expanded(
              // NeverScrollableScrollPhysics: step navigation is entirely
              // driven by the Back/Next buttons below (screens.md's Bottom
              // navigation between steps), not by swiping, so a step can
              // gate advancement (Location Not Set, Validation Error).
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _buildTypeStep(submitting),
                  _buildDetailsStep(submitting),
                  _buildLocationStep(submitting),
                  _buildPhotosStep(submitting),
                  _buildReviewStep(submitting),
                ],
              ),
            ),
            _buildBottomNav(submitting),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomNav(bool submitting) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            TextButton(
              onPressed: (_currentStep == 0 || submitting) ? null : _goBack,
              child: const Text('Back'),
            ),
            const Spacer(),
            ElevatedButton(
              // Confirmed real bug: the app-wide ElevatedButton theme
              // (app_theme.dart) sets minimumSize: Size.fromHeight(48),
              // i.e. Size(double.infinity, 48) -- fine for a button that's
              // the sole/full-width child of a Column, but here the button
              // sits in a Row next to the Back TextButton (via Spacer),
              // and Row imposes no upper bound on a non-flex child's
              // width. Infinity minWidth + Row's unbounded max-width
              // constraint crashes RenderConstrainedBox with "BoxConstraints
              // forces an infinite width." Overriding minimumSize's width
              // to 0 here keeps the fixed height while letting the button
              // size to its content, as any Row-embedded button must.
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(0, AppSizing.buttonHeight),
              ),
              onPressed: submitting ? null : _goNext,
              child: submitting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(_currentStep == _stepCount - 1 ? 'Publish' : 'Next'),
            ),
          ],
        ),
      ),
    );
  }

  // -- Step 1: listing type -------------------------------------------------

  Widget _buildTypeStep(bool submitting) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        Text('What are you listing?',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: AppSpacing.md),
        _TypeSelectorCard(
          title: 'Commercial',
          subtitle: 'Sale or lease -- office, shop, home, or land',
          icon: Icons.apartment,
          selected: _listingType == 'commercial',
          onTap: submitting
              ? null
              : () => setState(() => _listingType = 'commercial'),
        ),
        const SizedBox(height: AppSpacing.sm),
        _TypeSelectorCard(
          title: 'Shortlet',
          subtitle: 'Nightly-priced stay -- hostel, hotel, or apartment',
          icon: Icons.hotel,
          selected: _listingType == 'shortlet',
          onTap: submitting
              ? null
              : () => setState(() => _listingType = 'shortlet'),
        ),
      ],
    );
  }

  // -- Step 2: type-specific details -----------------------------------------

  Widget _buildDetailsStep(bool submitting) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        TextFormField(
          controller: _titleController,
          decoration: const InputDecoration(labelText: 'Title'),
          validator: (v) =>
              (v == null || v.trim().isEmpty) ? 'Title is required' : null,
          enabled: !submitting,
        ),
        const SizedBox(height: AppSpacing.md),
        TextFormField(
          controller: _descriptionController,
          decoration: const InputDecoration(labelText: 'Description'),
          maxLines: 4,
          validator: (v) => (v == null || v.trim().isEmpty)
              ? 'Description is required'
              : null,
          enabled: !submitting,
        ),
        const SizedBox(height: AppSpacing.lg),
        _buildAmenitiesField(submitting),
        const SizedBox(height: AppSpacing.lg),
        if (_listingType == 'commercial') _buildCommercialFields(submitting),
        if (_listingType == 'shortlet') _buildShortletFields(submitting),
      ],
    );
  }

  /// schema.md base Listing.amenities -- shared by both listing types, so
  /// it lives above the type-specific sections rather than duplicated into
  /// both `_buildCommercialFields`/`_buildShortletFields`.
  Widget _buildAmenitiesField(bool submitting) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Amenities', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: kAmenityOptions.map((option) {
            final selected = _amenities.contains(option.value);
            return FilterChip(
              label: Text(option.label),
              selected: selected,
              onSelected: submitting
                  ? null
                  : (value) => setState(() {
                        if (value) {
                          _amenities.add(option.value);
                        } else {
                          _amenities.remove(option.value);
                        }
                      }),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildCommercialFields(bool submitting) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Commercial details',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: AppSpacing.sm),
        DropdownButtonFormField<String>(
          initialValue: _dealType,
          decoration: const InputDecoration(labelText: 'Deal type'),
          items: const [
            DropdownMenuItem(value: 'sale', child: Text('Sale')),
            DropdownMenuItem(value: 'lease', child: Text('Lease')),
          ],
          onChanged: submitting ? null : (v) => setState(() => _dealType = v!),
        ),
        const SizedBox(height: AppSpacing.sm),
        TextFormField(
          controller: _priceController,
          decoration: const InputDecoration(labelText: 'Price (NGN)'),
          keyboardType: TextInputType.number,
          validator: (v) =>
              (double.tryParse(v ?? '') == null) ? 'Enter a valid price' : null,
          enabled: !submitting,
        ),
        if (_dealType == 'lease') ...[
          const SizedBox(height: AppSpacing.sm),
          TextFormField(
            controller: _possessionDaysController,
            decoration: const InputDecoration(
              labelText: 'Possession period (days, default 365)',
            ),
            keyboardType: TextInputType.number,
            enabled: !submitting,
          ),
        ],
        const SizedBox(height: AppSpacing.sm),
        // Confirmed real gap: "Size" used to be a single free-typed sqm
        // field -- split into Length x Width, the way a host actually
        // measures a room, with the sqm total computed and shown live.
        // "Width" (not "Breadth") to match schema.md's
        // CommercialListingRoom.widthMeters naming exactly.
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextFormField(
                controller: _lengthController,
                decoration: const InputDecoration(labelText: 'Length (m)'),
                keyboardType: TextInputType.number,
                validator: (v) => (double.tryParse(v ?? '') == null)
                    ? 'Enter a valid length'
                    : null,
                enabled: !submitting,
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: TextFormField(
                controller: _widthController,
                decoration: const InputDecoration(labelText: 'Width (m)'),
                keyboardType: TextInputType.number,
                validator: (v) => (double.tryParse(v ?? '') == null)
                    ? 'Enter a valid width'
                    : null,
                enabled: !submitting,
                onChanged: (_) => setState(() {}),
              ),
            ),
          ],
        ),
        if (_lengthController.text.isNotEmpty &&
            _widthController.text.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Size: ${_computedSizeSquareMeters.toStringAsFixed(1)} sqm',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ],
        const SizedBox(height: AppSpacing.sm),
        DropdownButtonFormField<String>(
          initialValue: _propertySubtype,
          decoration: const InputDecoration(labelText: 'Property subtype'),
          items: const [
            DropdownMenuItem(value: 'office', child: Text('Office')),
            DropdownMenuItem(value: 'shop', child: Text('Shop')),
            DropdownMenuItem(value: 'home', child: Text('Home')),
            DropdownMenuItem(value: 'land', child: Text('Land')),
          ],
          onChanged:
              submitting ? null : (v) => setState(() => _propertySubtype = v!),
        ),
        const SizedBox(height: AppSpacing.sm),
        TextFormField(
          controller: _commercialBathroomsController,
          decoration: const InputDecoration(labelText: 'Bathrooms'),
          keyboardType: TextInputType.number,
          validator: (v) =>
              (int.tryParse(v ?? '') == null) ? 'Enter a valid number' : null,
          enabled: !submitting,
        ),
        const SizedBox(height: AppSpacing.md),
        // schema.md's CommercialListing.legalDocuments -- see
        // `_legalDocuments`'s field docstring for why this section exists
        // now where it previously didn't.
        Text('Legal documents available',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Shown to guests as a trust signal, especially for Sale listings.',
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: kLegalDocumentOptions.map((option) {
            final selected = _legalDocuments.contains(option.value);
            return FilterChip(
              label: Text(option.label),
              selected: selected,
              onSelected: submitting
                  ? null
                  : (value) => setState(() {
                        if (value) {
                          _legalDocuments.add(option.value);
                        } else {
                          _legalDocuments.remove(option.value);
                        }
                      }),
            );
          }).toList(),
        ),
        const SizedBox(height: AppSpacing.md),
        Text('Room breakdown (optional)',
            style: Theme.of(context).textTheme.bodyMedium),
        // Confirmed real gap: rooms used to be added with a hardcoded
        // level: 'ground', widthMeters: 0, lengthMeters: 0 and no way to
        // ever change those values -- every room silently stayed
        // "ground, 0.0m x 0.0m". Tapping a row now reopens the same
        // dialog "Add room" uses, pre-filled, so floor/dimensions are
        // always editable after the fact too.
        ..._rooms.asMap().entries.map(
              (entry) => ListTile(
                dense: true,
                title: Text(
                  '${_floorLabel(entry.value.level)}: ${entry.value.lengthMeters}m x ${entry.value.widthMeters}m',
                ),
                onTap: submitting
                    ? null
                    : () => _showRoomDialog(
                          editIndex: entry.key,
                          existing: entry.value,
                        ),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: submitting
                      ? null
                      : () => setState(() => _rooms.removeAt(entry.key)),
                ),
              ),
            ),
        TextButton.icon(
          onPressed: submitting ? null : () => _showRoomDialog(),
          icon: const Icon(Icons.add),
          label: const Text('Add room'),
        ),
      ],
    );
  }

  static const List<String> _roomLevels = [
    'basement',
    'ground',
    'first',
    'second',
    'third',
  ];

  String _floorLabel(String level) => switch (level) {
        'basement' => 'Basement',
        'ground' => 'Ground floor',
        'first' => '1st floor',
        'second' => '2nd floor',
        'third' => '3rd floor',
        _ => level,
      };

  /// Add/edit-room dialog -- collects the floor (level) and actual
  /// length/width dimensions a host measures, rather than silently
  /// defaulting to ground/0.0m x 0.0m with no way to change them.
  Future<void> _showRoomDialog({int? editIndex, CommercialRoom? existing}) {
    var level = existing?.level ?? 'ground';
    final lengthController = TextEditingController(
      text: existing != null ? existing.lengthMeters.toString() : '',
    );
    final widthController = TextEditingController(
      text: existing != null ? existing.widthMeters.toString() : '',
    );
    final dialogFormKey = GlobalKey<FormState>();

    return showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(existing == null ? 'Add room' : 'Edit room'),
          content: Form(
            key: dialogFormKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: level,
                  decoration: const InputDecoration(labelText: 'Floor'),
                  items: _roomLevels
                      .map((l) => DropdownMenuItem(
                          value: l, child: Text(_floorLabel(l))))
                      .toList(),
                  onChanged: (v) => setDialogState(() => level = v!),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextFormField(
                  controller: lengthController,
                  decoration: const InputDecoration(labelText: 'Length (m)'),
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    final parsed = double.tryParse(v ?? '');
                    return (parsed == null || parsed <= 0)
                        ? 'Enter a valid length'
                        : null;
                  },
                ),
                const SizedBox(height: AppSpacing.sm),
                TextFormField(
                  controller: widthController,
                  decoration: const InputDecoration(labelText: 'Width (m)'),
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    final parsed = double.tryParse(v ?? '');
                    return (parsed == null || parsed <= 0)
                        ? 'Enter a valid width'
                        : null;
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(0, AppSizing.buttonHeight),
              ),
              onPressed: () {
                if (!dialogFormKey.currentState!.validate()) return;
                final room = CommercialRoom(
                  level: level,
                  lengthMeters: double.parse(lengthController.text),
                  widthMeters: double.parse(widthController.text),
                );
                setState(() {
                  if (editIndex != null) {
                    _rooms[editIndex] = room;
                  } else {
                    _rooms.add(room);
                  }
                });
                Navigator.of(dialogContext).pop();
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShortletFields(bool submitting) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Shortlet details',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: AppSpacing.sm),
        TextFormField(
          controller: _nightlyPriceController,
          decoration: const InputDecoration(labelText: 'Nightly price (NGN)'),
          keyboardType: TextInputType.number,
          validator: (v) =>
              (double.tryParse(v ?? '') == null) ? 'Enter a valid price' : null,
          enabled: !submitting,
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _minStayController,
                decoration:
                    const InputDecoration(labelText: 'Min stay (nights)'),
                keyboardType: TextInputType.number,
                validator: (v) =>
                    (int.tryParse(v ?? '') == null) ? 'Required' : null,
                enabled: !submitting,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: TextFormField(
                controller: _maxStayController,
                decoration: const InputDecoration(
                    labelText: 'Max stay (nights, optional)'),
                keyboardType: TextInputType.number,
                enabled: !submitting,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        DropdownButtonFormField<String>(
          initialValue: _shortletSubtype,
          decoration: const InputDecoration(labelText: 'Property subtype'),
          // hostel | hotel -- schema.md's ShortletListing.propertySubtype
          // (docs/De-Duke/schema.md, product decision). Was hostel/hotel/
          // 1-3 bedroom -- the bedroom-count items duplicated the
          // "Bedrooms" field below as a string enum and are no longer
          // accepted by the backend. Ordered ahead of Bedrooms/Bathrooms:
          // the property subtype is the higher-level classification, with
          // the room counts as its detail fields underneath.
          items: const [
            DropdownMenuItem(value: 'hostel', child: Text('Hostel')),
            DropdownMenuItem(value: 'hotel', child: Text('Hotel')),
          ],
          onChanged:
              submitting ? null : (v) => setState(() => _shortletSubtype = v!),
        ),
        const SizedBox(height: AppSpacing.sm),
        TextFormField(
          controller: _bedroomsController,
          decoration: const InputDecoration(labelText: 'Bedrooms'),
          keyboardType: TextInputType.number,
          validator: (v) =>
              (int.tryParse(v ?? '') == null) ? 'Enter a valid number' : null,
          enabled: !submitting,
        ),
        const SizedBox(height: AppSpacing.sm),
        TextFormField(
          controller: _shortletBathroomsController,
          decoration: const InputDecoration(labelText: 'Bathrooms'),
          keyboardType: TextInputType.number,
          validator: (v) =>
              (int.tryParse(v ?? '') == null) ? 'Enter a valid number' : null,
          enabled: !submitting,
        ),
        const SizedBox(height: AppSpacing.md),
        // schema.md's ShortletListing.houseRules -- confirmed real gap:
        // `_houseRules` was declared and passed straight through to
        // `_submit()` already, but nothing in this form ever added an
        // entry to it, so every shortlet listing silently published with
        // an empty house rules list regardless of what the host typed
        // here (there was nowhere to type it).
        Text('House rules', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: AppSpacing.sm),
        if (_houseRules.isNotEmpty)
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: _houseRules
                .map((rule) => Chip(
                      label: Text(rule),
                      onDeleted: submitting
                          ? null
                          : () => setState(() => _houseRules.remove(rule)),
                    ))
                .toList(),
          ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _houseRuleController,
                decoration: const InputDecoration(
                    hintText: 'e.g. No smoking, No pets'),
                enabled: !submitting,
                onFieldSubmitted: (_) => _addHouseRule(),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            IconButton(
              onPressed: submitting ? null : _addHouseRule,
              icon: const Icon(Icons.add_circle_outline),
              tooltip: 'Add house rule',
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        // schema.md's ShortletListing.blockedDates -- same confirmed real
        // gap as houseRules above: the field existed on the model with no
        // UI anywhere to populate it.
        Text('Blocked dates', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Dates already unavailable for booking (e.g. for maintenance or personal use).',
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: AppSpacing.sm),
        if (_blockedDates.isNotEmpty)
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: _blockedDates
                .map((date) => Chip(
                      label: Text(date),
                      onDeleted: submitting
                          ? null
                          : () => setState(() => _blockedDates.remove(date)),
                    ))
                .toList(),
          ),
        const SizedBox(height: AppSpacing.sm),
        TextButton.icon(
          onPressed: submitting ? null : _pickBlockedDate,
          icon: const Icon(Icons.event_busy_outlined),
          label: const Text('Block a date'),
        ),
      ],
    );
  }

  void _addHouseRule() {
    final rule = _houseRuleController.text.trim();
    if (rule.isEmpty) return;
    setState(() {
      _houseRules.add(rule);
      _houseRuleController.clear();
    });
  }

  Future<void> _pickBlockedDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      firstDate: now,
      lastDate: now.add(const Duration(days: 730)),
    );
    if (picked == null || !mounted) return;
    // ISO date string (YYYY-MM-DD) -- matches schema.md's
    // ShortletListing.blockedDates format exactly.
    final iso =
        '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
    if (_blockedDates.contains(iso)) return;
    setState(() => _blockedDates.add(iso));
  }

  // -- Step 3: location -------------------------------------------------------

  Widget _buildLocationStep(bool submitting) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        Text('Location', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: AppSpacing.sm),
        SegmentedButton<LocationInputMethod>(
          segments: const [
            ButtonSegment(
                value: LocationInputMethod.mapPin, label: Text('Map pin')),
            ButtonSegment(
                value: LocationInputMethod.addressSearch,
                label: Text('Address')),
            ButtonSegment(value: LocationInputMethod.gps, label: Text('GPS')),
          ],
          selected: {_locationMethod},
          onSelectionChanged: submitting
              ? null
              : (selection) {
                  final method = selection.first;
                  if (method == LocationInputMethod.gps) {
                    _useGpsLocation();
                  } else {
                    setState(() => _locationMethod = method);
                  }
                },
        ),
        const SizedBox(height: AppSpacing.sm),
        if (_locationMethod == LocationInputMethod.mapPin)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    height: 220,
                    child: GoogleMap(
                      initialCameraPosition: CameraPosition(
                        // Falls back to Lagos, Nigeria -- consistent
                        // with SearchMapView's default center -- when
                        // no coordinate has been picked by any method
                        // yet (a user could switch to Map pin after
                        // already using GPS/Address, in which case this
                        // centers on whatever was already captured).
                        target:
                            LatLng(_latitude ?? 6.5244, _longitude ?? 3.3792),
                        zoom: 14,
                      ),
                      onMapCreated: (controller) => _mapController = controller,
                      onTap: submitting ? null : _setMapPin,
                      markers: _latitude != null && _longitude != null
                          ? {
                              Marker(
                                markerId: const MarkerId('listing-location'),
                                position: LatLng(_latitude!, _longitude!),
                                draggable: !submitting,
                                onDragEnd: _setMapPin,
                              ),
                            }
                          : const {},
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  _latitude != null && _longitude != null
                      ? 'Pinned: ${_latitude!.toStringAsFixed(5)}, ${_longitude!.toStringAsFixed(5)}'
                      : 'Tap the map to drop a pin, or drag it to adjust.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        if (_locationMethod == LocationInputMethod.gps)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Row(
              children: [
                Icon(
                  _latitude != null && _longitude != null
                      ? Icons.gps_fixed
                      : Icons.gps_not_fixed,
                  size: 18,
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    _latitude != null && _longitude != null
                        ? 'Captured: ${_latitude!.toStringAsFixed(5)}, ${_longitude!.toStringAsFixed(5)}'
                        : 'Getting your location...',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                TextButton(
                  onPressed: submitting ? null : _useGpsLocation,
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        AddressAutocompleteField(
          controller: _addressController,
          enabled: !submitting,
          onPlaceSelected: _applyPlaceSelection,
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _cityController,
                decoration: const InputDecoration(labelText: 'City'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
                enabled: !submitting,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: TextFormField(
                controller: _stateController,
                decoration: const InputDecoration(labelText: 'State'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
                enabled: !submitting,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // -- Step 4: media (photos + videos) -----------------------------------------

  Widget _buildPhotosStep(bool submitting) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        Text('Photos & Videos', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Up to $_maxVideos videos (5 min / 100MB each), any number of photos.',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
        ),
        const SizedBox(height: AppSpacing.sm),
        _MediaReorderList(
          media: _media,
          onReorder: submitting ? (_, __) {} : _reorderMedia,
          onSetPrimary: submitting ? (_) {} : _setPrimaryMedia,
          onRemove: submitting ? (_) {} : _removeMedia,
        ),
        Row(
          children: [
            TextButton.icon(
              onPressed: submitting ? null : _addPickedPhoto,
              icon: const Icon(Icons.add_a_photo),
              label: const Text('Add photo'),
            ),
            const SizedBox(width: AppSpacing.sm),
            TextButton.icon(
              onPressed:
                  submitting || _videoCount >= _maxVideos ? null : _addPickedVideo,
              icon: const Icon(Icons.videocam_outlined),
              label: Text('Add video ($_videoCount/$_maxVideos)'),
            ),
          ],
        ),
      ],
    );
  }

  // -- Step 5: review ----------------------------------------------------------

  Widget _buildReviewStep(bool submitting) {
    final locationSummary = [
      _addressController.text.trim(),
      _cityController.text.trim(),
      _stateController.text.trim(),
    ].where((s) => s.isNotEmpty).join(', ');
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        Text('Review', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: AppSpacing.sm),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _reviewRow('Type',
                    _listingType == 'commercial' ? 'Commercial' : 'Shortlet'),
                _reviewRow('Title', _titleController.text),
                _reviewRow('Description', _descriptionController.text),
                _reviewRow(
                  'Amenities',
                  _amenities.isEmpty ? 'None selected' : '${_amenities.length} selected',
                ),
                if (_listingType == 'commercial') ...[
                  _reviewRow('Deal type', humanizeEnumValue(_dealType)),
                  _reviewRow('Price', _priceController.text),
                  _reviewRow('Length x Width',
                      '${_lengthController.text}m x ${_widthController.text}m'),
                  _reviewRow('Size (sqm)',
                      _computedSizeSquareMeters.toStringAsFixed(1)),
                  _reviewRow('Bathrooms', _commercialBathroomsController.text),
                  _reviewRow(
                    'Legal documents',
                    _legalDocuments.isEmpty
                        ? 'None confirmed'
                        : '${_legalDocuments.length} confirmed',
                  ),
                  _reviewRow('Rooms', '${_rooms.length}'),
                ] else ...[
                  _reviewRow('Nightly price', _nightlyPriceController.text),
                  _reviewRow('Bedrooms', _bedroomsController.text),
                  _reviewRow('Bathrooms', _shortletBathroomsController.text),
                  _reviewRow('House rules',
                      _houseRules.isEmpty ? 'None' : '${_houseRules.length} added'),
                  _reviewRow(
                    'Blocked dates',
                    _blockedDates.isEmpty ? 'None' : '${_blockedDates.length} blocked',
                  ),
                ],
                _reviewRow('Photos', '${_media.where((m) => !m.isVideo).length}'),
                _reviewRow('Videos', '$_videoCount'),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text('Location', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: AppSpacing.sm),
        if (_latitude != null && _longitude != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              height: 160,
              child: IgnorePointer(
                child: GoogleMap(
                  initialCameraPosition: CameraPosition(
                    target: LatLng(_latitude!, _longitude!),
                    zoom: 14,
                  ),
                  markers: {
                    Marker(
                      markerId: const MarkerId('review-location'),
                      position: LatLng(_latitude!, _longitude!),
                    ),
                  },
                ),
              ),
            ),
          ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          locationSummary.isEmpty ? 'No address set.' : locationSummary,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _reviewRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label,
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
          Expanded(child: Text(value.isEmpty ? '--' : value)),
        ],
      ),
    );
  }
}

/// screens.md Screen 7 Layout: "step indicator (multi-step form)" in the
/// `AppBar` -- animates its progress fill alongside step transitions
/// (Modernization Notes) at `page-transition` speed.
class _StepIndicator extends StatelessWidget {
  const _StepIndicator({required this.currentStep});

  final int currentStep;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadii.sm),
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(
                begin: currentStep / _stepCount,
                end: (currentStep + 1) / _stepCount,
              ),
              duration: AppDurations.pageTransition,
              curve: AppCurves.easeOutSmooth,
              builder: (context, value, _) => LinearProgressIndicator(
                value: value,
                minHeight: 4,
                backgroundColor: Theme.of(context).colorScheme.outline,
                valueColor: AlwaysStoppedAnimation(Theme.of(context).colorScheme.primary),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Step ${currentStep + 1} of $_stepCount -- ${_stepTitles[currentStep]}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _TypeSelectorCard extends StatelessWidget {
  const _TypeSelectorCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: selected ? Theme.of(context).colorScheme.primaryContainer : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.md),
        side: BorderSide(
          color: selected ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.outline,
          width: selected ? 2 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.md),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              Icon(icon,
                  size: AppSizing.iconMd,
                  color:
                      selected ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    Text(subtitle,
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
              if (selected)
                Icon(Icons.check_circle, color: Theme.of(context).colorScheme.primary),
            ],
          ),
        ),
      ),
    );
  }
}

/// screens.md Screen 7 Success state + Modernization Notes: "The 'Listing
/// Live' success screen ... uses the full celebratory-sequence -- this is a
/// genuine milestone for the host ... pairs the confirmation illustration
/// with the same expressive treatment as Payment Confirmation."
class _ListingLiveScreen extends StatelessWidget {
  const _ListingLiveScreen({required this.listing, required this.onDone});

  final Listing listing;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          automaticallyImplyLeading: false, title: const Text('Listing Live')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: CelebratorySequence(
            accentColor: Theme.of(context).extension<AppSemanticColors>()!.success,
            supportingContent: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Your listing is live',
                    style: Theme.of(context).textTheme.headlineSmall,
                    textAlign: TextAlign.center),
                const SizedBox(height: AppSpacing.sm),
                Text(listing.title,
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                    textAlign: TextAlign.center),
                const SizedBox(height: AppSpacing.lg),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: onDone,
                    child: const Text('View listing'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: Theme.of(context).colorScheme.error),
      ),
      child: Row(
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.error, size: AppSizing.iconMd),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(message)),
        ],
      ),
    );
  }
}

/// screens.md Modernization Notes: "photo grid thumbnails reorder with a
/// smooth spring-based reflow rather than an instant jump" -- each row is
/// wrapped so reorders animate their position change with an
/// `easeSpringSoft` curve instead of `ReorderableListView`'s default snap.
///
/// FEAT-004/FEAT-005 video support: a single combined list (per the product
/// decision to match the interleaved Listing Detail gallery 1:1) -- a video
/// row shows a video-camera thumbnail instead of a decoded frame (no local
/// poster exists yet client-side, unlike the server-generated one shown
/// once persisted) and never gets a star/primary button, since a video can
/// never be the listing's cover.
class _MediaReorderList extends StatelessWidget {
  const _MediaReorderList({
    required this.media,
    required this.onReorder,
    required this.onSetPrimary,
    required this.onRemove,
  });

  final List<PendingListingMedia> media;
  final void Function(int, int) onReorder;
  final void Function(int) onSetPrimary;
  final void Function(int) onRemove;

  @override
  Widget build(BuildContext context) {
    if (media.isEmpty) {
      return Text('No photos or videos added yet.',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant));
    }
    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: media.length,
      onReorder: onReorder,
      // Confirmed real bug: with the default drag handles, the WHOLE tile
      // (including the star/remove IconButtons on top of it) was a
      // long-press drag target -- pressing and holding anywhere on a row,
      // including directly on a button, raced ReorderableListView's own
      // long-press-drag gesture recognizer against those buttons' tap
      // recognizers in the same gesture arena, throwing on drag start.
      // Disabling the default handles and giving the drag_handle icon its
      // own explicit ReorderableDragStartListener confines the drag
      // gesture to just that icon, leaving every other control free of it.
      buildDefaultDragHandles: false,
      proxyDecorator: (child, index, animation) => AnimatedBuilder(
        animation: animation,
        builder: (context, _) {
          final t = AppCurves.easeSpringSoft.transform(animation.value);
          return Transform.scale(
            scale: 1 + (0.03 * t),
            child: child,
          );
        },
        child: child,
      ),
      itemBuilder: (context, index) {
        final item = media[index];
        // Confirmed real bug: ReorderableListView's drag proxy re-parents
        // the dragged item's render tree into the root Overlay (via
        // proxyDecorator/_RenderTheater), which sits above the page's own
        // Scaffold in the tree -- so a ListTile/IconButton here (both
        // require a Material ancestor) throws "No Material widget found"
        // the moment a drag starts, since the Overlay itself provides
        // none. Wrapping the whole row in its own Material carries that
        // ancestor along wherever the row is rendered, drag or not. The
        // key ReorderableListView needs must stay on this outermost
        // widget, not the ListTile inside it.
        return Material(
          key: ValueKey(item.tempKey),
          type: MaterialType.transparency,
          child: ListTile(
            // Confirmed real gap: this used to be a generic Icons.image
            // placeholder, never the actual picked photo.
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadii.sm),
              child: item.isVideo
                  // No local poster exists yet client-side (that's a
                  // server-side step, see listing_service.
                  // process_uploaded_video) -- a plain video-camera tile
                  // is enough for the picker list; the real poster shows
                  // up once the listing reloads post-publish.
                  ? Container(
                      width: 48,
                      height: 48,
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      child: Icon(Icons.videocam,
                          color: Theme.of(context).colorScheme.onSurfaceVariant),
                    )
                  : Image.file(
                      File(item.localPath),
                      width: 48,
                      height: 48,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => Container(
                        width: 48,
                        height: 48,
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        child: Icon(Icons.broken_image_outlined,
                            color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                    ),
            ),
            title: Text(item.isVideo ? 'Video' : 'Photo'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!item.isVideo)
                  if (item.isPrimary)
                    Icon(Icons.star, color: Theme.of(context).colorScheme.tertiary)
                  else
                    IconButton(
                      icon: const Icon(Icons.star_border),
                      tooltip: 'Set as primary photo',
                      onPressed: () => onSetPrimary(index),
                    ),
                // Confirmed real gap: there was previously no way at all
                // to remove a picked photo.
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: item.isVideo ? 'Remove video' : 'Remove photo',
                  onPressed: () => onRemove(index),
                ),
                ReorderableDragStartListener(
                  index: index,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                    child: Icon(Icons.drag_handle),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
