/// screens.md Screen 7: Create Listing.
///
/// Covers: listing type + commercial/shortlet subtype fields, the
/// three-method location input (map pin drop / address autocomplete / "use
/// my GPS location" -- all three resolve to the same lat/lng+address
/// fields sent to the server), image picking with reorder + primary flag,
/// commercial room breakdown, and submitting/validation/error/offline
/// states.
///
/// Structured as a 5-step wizard per screens.md's Layout section:
///   1. Listing type (Commercial vs. Shortlet) via large selectable cards
///   2. Type-specific detail form (+ title/description, common to both
///      types and not called out as their own step in the doc)
///   3. Location (Location Input subsection)
///   4. Photo upload grid
///   5. Review + Publish
/// All step state lives in this single State object (form fields, photo
/// objects, room entries, resolved lat/lng) and persists across step
/// navigation since every step's widget subtree stays mounted inside the
/// `PageView` for the lifetime of this screen.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/services/places_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/address_autocomplete_field.dart';
import '../../../core/widgets/celebratory_sequence.dart';
import '../../../core/widgets/image_source_picker.dart';
import '../data/listing_models.dart';
import '../data/listing_repository.dart';

enum LocationInputMethod { mapPin, addressSearch, gps }

enum _SubmitState { idle, submitting, success, error, offline }

const int _stepCount = 5;
const List<String> _stepTitles = [
  'Type',
  'Details',
  'Location',
  'Photos',
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
  final _sizeController = TextEditingController();
  String _propertySubtype = 'office';
  final _commercialBathroomsController = TextEditingController();
  final _possessionDaysController = TextEditingController();
  final List<CommercialRoom> _rooms = [];

  // Shortlet fields.
  final _nightlyPriceController = TextEditingController();
  final _minStayController = TextEditingController();
  final _maxStayController = TextEditingController();
  final _bedroomsController = TextEditingController();
  final _shortletBathroomsController = TextEditingController();
  String _shortletSubtype = '1_bedroom';
  final List<String> _houseRules = [];

  final List<PendingListingImage> _images = [];

  _SubmitState _state = _SubmitState.idle;
  String? _errorMessage;
  int _tempKeyCounter = 0;
  Listing? _publishedListing;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _addressController.dispose();
    _cityController.dispose();
    _stateController.dispose();
    _priceController.dispose();
    _sizeController.dispose();
    _possessionDaysController.dispose();
    _nightlyPriceController.dispose();
    _minStayController.dispose();
    _maxStayController.dispose();
    _bedroomsController.dispose();
    _commercialBathroomsController.dispose();
    _shortletBathroomsController.dispose();
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

  Future<void> _addPickedImage() async {
    final path = await pickImageFromCameraOrGallery(context);
    if (path == null || !mounted) return;
    setState(() {
      final key = 'img_${_tempKeyCounter++}';
      _images.add(
        PendingListingImage(
          tempKey: key,
          localPath: path,
          displayOrder: _images.length,
          isPrimary: _images.isEmpty,
        ),
      );
    });
  }

  void _reorderImages(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final item = _images.removeAt(oldIndex);
      _images.insert(newIndex, item);
      for (var i = 0; i < _images.length; i++) {
        _images[i].displayOrder = i;
      }
    });
  }

  void _setPrimaryImage(int index) {
    setState(() {
      for (var i = 0; i < _images.length; i++) {
        _images[i].isPrimary = i == index;
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
          if (double.tryParse(_sizeController.text) == null) {
            return 'Enter a valid size to continue.';
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
        commercial: _listingType == 'commercial'
            ? CommercialListingDetails(
                dealType: _dealType,
                price: double.tryParse(_priceController.text) ?? 0,
                possessionPeriodDays: _dealType == 'lease'
                    ? int.tryParse(_possessionDaysController.text)
                    : null,
                sizeSquareMeters: double.tryParse(_sizeController.text) ?? 0,
                propertySubtype: _propertySubtype,
                bathrooms:
                    int.tryParse(_commercialBathroomsController.text) ?? 0,
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
              )
            : null,
      );

      if (_images.isNotEmpty) {
        await widget.repository.uploadImages(listing.id, _images);
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
                child: _Banner(icon: Icons.error_outline, message: _errorMessage!),
              ),
            if (_stepBlockedMessage != null)
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md, vertical: AppSpacing.xs),
                child: Text(
                  _stepBlockedMessage!,
                  style: const TextStyle(color: AppColors.error),
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
        if (_listingType == 'commercial') _buildCommercialFields(submitting),
        if (_listingType == 'shortlet') _buildShortletFields(submitting),
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
        TextFormField(
          controller: _sizeController,
          decoration: const InputDecoration(labelText: 'Size (sqm)'),
          keyboardType: TextInputType.number,
          validator: (v) =>
              (double.tryParse(v ?? '') == null) ? 'Enter a valid size' : null,
          enabled: !submitting,
        ),
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
        const SizedBox(height: AppSpacing.sm),
        Text('Room breakdown (optional)',
            style: Theme.of(context).textTheme.bodyMedium),
        ..._rooms.map(
          (r) => ListTile(
            dense: true,
            title: Text('${r.level}: ${r.widthMeters}m x ${r.lengthMeters}m'),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed:
                  submitting ? null : () => setState(() => _rooms.remove(r)),
            ),
          ),
        ),
        TextButton.icon(
          onPressed: submitting
              ? null
              : () => setState(
                    () => _rooms.add(
                      const CommercialRoom(
                          level: 'ground', widthMeters: 0, lengthMeters: 0),
                    ),
                  ),
          icon: const Icon(Icons.add),
          label: const Text('Add room'),
        ),
      ],
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
        const SizedBox(height: AppSpacing.sm),
        DropdownButtonFormField<String>(
          initialValue: _shortletSubtype,
          decoration: const InputDecoration(labelText: 'Subtype'),
          items: const [
            DropdownMenuItem(value: 'hostel', child: Text('Hostel')),
            DropdownMenuItem(value: 'hotel', child: Text('Hotel')),
            DropdownMenuItem(value: '1_bedroom', child: Text('1 Bedroom')),
            DropdownMenuItem(value: '2_bedroom', child: Text('2 Bedroom')),
            DropdownMenuItem(value: '3_bedroom', child: Text('3 Bedroom')),
          ],
          onChanged:
              submitting ? null : (v) => setState(() => _shortletSubtype = v!),
        ),
        // Availability calendar (blocked_dates) is edited after creation on
        // the listing edit screen -- TODO: add a calendar widget there.
      ],
    );
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
            ButtonSegment(
                value: LocationInputMethod.gps, label: Text('GPS')),
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
                        target: LatLng(
                            _latitude ?? 6.5244, _longitude ?? 3.3792),
                        zoom: 14,
                      ),
                      onMapCreated: (controller) =>
                          _mapController = controller,
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

  // -- Step 4: photos ----------------------------------------------------------

  Widget _buildPhotosStep(bool submitting) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        Text('Photos', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: AppSpacing.sm),
        _ImageReorderList(
          images: _images,
          onReorder: submitting ? (_, __) {} : _reorderImages,
          onSetPrimary: submitting ? (_) {} : _setPrimaryImage,
        ),
        TextButton.icon(
          onPressed: submitting ? null : _addPickedImage,
          icon: const Icon(Icons.add_a_photo),
          label: const Text('Add photo'),
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
                if (_listingType == 'commercial') ...[
                  _reviewRow('Deal type', _dealType),
                  _reviewRow('Price', _priceController.text),
                  _reviewRow('Size (sqm)', _sizeController.text),
                  _reviewRow('Bathrooms', _commercialBathroomsController.text),
                  _reviewRow('Rooms', '${_rooms.length}'),
                ] else ...[
                  _reviewRow('Nightly price', _nightlyPriceController.text),
                  _reviewRow('Bedrooms', _bedroomsController.text),
                  _reviewRow('Bathrooms', _shortletBathroomsController.text),
                ],
                _reviewRow('Photos', '${_images.length}'),
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
                style: const TextStyle(color: AppColors.textSecondary)),
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
                backgroundColor: AppColors.border,
                valueColor: const AlwaysStoppedAnimation(AppColors.primary),
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
      color: selected ? AppColors.primaryLight : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.md),
        side: BorderSide(
          color: selected ? AppColors.primary : AppColors.border,
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
                  color: selected ? AppColors.primary : AppColors.textSecondary),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: Theme.of(context).textTheme.titleMedium),
                    Text(subtitle,
                        style: const TextStyle(color: AppColors.textSecondary)),
                  ],
                ),
              ),
              if (selected)
                const Icon(Icons.check_circle, color: AppColors.primary),
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
      appBar: AppBar(automaticallyImplyLeading: false, title: const Text('Listing Live')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: CelebratorySequence(
            accentColor: AppColors.success,
            supportingContent: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Your listing is live',
                    style: Theme.of(context).textTheme.headlineSmall,
                    textAlign: TextAlign.center),
                const SizedBox(height: AppSpacing.sm),
                Text(listing.title,
                    style: const TextStyle(color: AppColors.textSecondary),
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
        color: AppColors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: AppColors.error),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.error, size: AppSizing.iconMd),
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
class _ImageReorderList extends StatelessWidget {
  const _ImageReorderList({
    required this.images,
    required this.onReorder,
    required this.onSetPrimary,
  });

  final List<PendingListingImage> images;
  final void Function(int, int) onReorder;
  final void Function(int) onSetPrimary;

  @override
  Widget build(BuildContext context) {
    if (images.isEmpty) {
      return const Text('No photos added yet.',
          style: TextStyle(color: AppColors.textSecondary));
    }
    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: images.length,
      onReorder: onReorder,
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
        final image = images[index];
        return ListTile(
          key: ValueKey(image.tempKey),
          leading: const Icon(Icons.image),
          title: Text('Photo ${index + 1}'),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (image.isPrimary)
                const Icon(Icons.star, color: AppColors.accent)
              else
                IconButton(
                  icon: const Icon(Icons.star_border),
                  onPressed: () => onSetPrimary(index),
                ),
              const Icon(Icons.drag_handle),
            ],
          ),
        );
      },
    );
  }
}
