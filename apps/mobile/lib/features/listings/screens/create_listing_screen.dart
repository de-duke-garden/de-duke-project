/// screens.md Screen 7: Create Listing.
///
/// Covers: listing type + commercial/shortlet subtype fields, the
/// three-method location input (map pin drop / address autocomplete / "use
/// my GPS location" -- all three resolve to the same lat/lng+address
/// fields sent to the server), image picking with reorder + primary flag,
/// commercial room breakdown, and submitting/validation/error/offline
/// states.
library;

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../data/listing_models.dart';
import '../data/listing_repository.dart';

enum LocationInputMethod { mapPin, addressSearch, gps }

enum _SubmitState { idle, submitting, success, error, offline }

class CreateListingScreen extends StatefulWidget {
  const CreateListingScreen({super.key, required this.repository});

  final ListingRepository repository;

  @override
  State<CreateListingScreen> createState() => _CreateListingScreenState();
}

class _CreateListingScreenState extends State<CreateListingScreen> {
  final _formKey = GlobalKey<FormState>();

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

  // Commercial fields.
  String _dealType = 'sale';
  final _priceController = TextEditingController();
  final _sizeController = TextEditingController();
  String _propertySubtype = 'office';
  final _possessionDaysController = TextEditingController();
  final List<CommercialRoom> _rooms = [];

  // Shortlet fields.
  final _nightlyPriceController = TextEditingController();
  final _minStayController = TextEditingController();
  final _maxStayController = TextEditingController();
  final _bedroomsController = TextEditingController();
  final List<String> _houseRules = [];

  final List<PendingListingImage> _images = [];

  _SubmitState _state = _SubmitState.idle;
  String? _errorMessage;
  int _tempKeyCounter = 0;

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
    super.dispose();
  }

  Future<void> _useGpsLocation() async {
    // TODO: wire to a location plugin (e.g. geolocator) to read the
    // device's actual coordinates. Left as a clear stub -- no fabricated
    // GPS reading here.
    setState(() => _locationMethod = LocationInputMethod.gps);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('GPS lookup not wired up yet -- enter address manually.'),
      ),
    );
  }

  void _addPickedImagePlaceholder() {
    // TODO: wire to image_picker to select a real file from camera/gallery.
    // We synthesize a temp_key here so the reorder/primary-flag UI and the
    // upload contract are fully exercised even before the picker lands.
    setState(() {
      final key = 'img_${_tempKeyCounter++}';
      _images.add(
        PendingListingImage(
          tempKey: key,
          localPath: '', // populated once image_picker is wired up
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
                rooms: _rooms,
              )
            : null,
        shortlet: _listingType == 'shortlet'
            ? ShortletListingDetails(
                nightlyPrice: double.tryParse(_nightlyPriceController.text) ?? 0,
                minimumStayNights: int.tryParse(_minStayController.text) ?? 1,
                maximumStayNights: int.tryParse(_maxStayController.text),
                bedrooms: int.tryParse(_bedroomsController.text) ?? 0,
                houseRules: _houseRules,
              )
            : null,
      );

      if (_images.isNotEmpty) {
        await widget.repository.uploadImages(listing.id, _images);
      }

      if (!mounted) return;
      setState(() => _state = _SubmitState.success);
      Navigator.of(context).pop(listing);
    } on Exception catch (e) {
      final message = e.toString();
      setState(() {
        _state = message.contains('SocketException') || message.contains('connection')
            ? _SubmitState.offline
            : _SubmitState.error;
        _errorMessage = message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final submitting = _state == _SubmitState.submitting;
    return Scaffold(
      appBar: AppBar(title: const Text('Create Listing')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            if (_state == _SubmitState.offline)
              const _Banner(
                icon: Icons.wifi_off,
                message: "You're offline. We'll need a connection to publish this listing.",
              ),
            if (_state == _SubmitState.error && _errorMessage != null)
              _Banner(icon: Icons.error_outline, message: _errorMessage!),
            DropdownButtonFormField<String>(
              initialValue: _listingType,
              decoration: const InputDecoration(labelText: 'Listing type'),
              items: const [
                DropdownMenuItem(value: 'commercial', child: Text('Commercial (sale/lease)')),
                DropdownMenuItem(value: 'shortlet', child: Text('Shortlet')),
              ],
              onChanged: submitting ? null : (v) => setState(() => _listingType = v!),
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _titleController,
              decoration: const InputDecoration(labelText: 'Title'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Title is required' : null,
              enabled: !submitting,
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _descriptionController,
              decoration: const InputDecoration(labelText: 'Description'),
              maxLines: 4,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Description is required' : null,
              enabled: !submitting,
            ),
            const SizedBox(height: AppSpacing.lg),
            Text('Location', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            SegmentedButton<LocationInputMethod>(
              segments: const [
                ButtonSegment(value: LocationInputMethod.mapPin, label: Text('Map pin')),
                ButtonSegment(value: LocationInputMethod.addressSearch, label: Text('Address')),
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
              // TODO: embed an interactive Google Map for pin-drop; stubbed
              // with manual lat/lng entry so the rest of the flow works.
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      decoration: const InputDecoration(labelText: 'Latitude'),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      enabled: !submitting,
                      onChanged: (v) => _latitude = double.tryParse(v),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: TextFormField(
                      decoration: const InputDecoration(labelText: 'Longitude'),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      enabled: !submitting,
                      onChanged: (v) => _longitude = double.tryParse(v),
                    ),
                  ),
                ],
              ),
            TextFormField(
              controller: _addressController,
              decoration: const InputDecoration(labelText: 'Address line'),
              enabled: !submitting,
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _cityController,
                    decoration: const InputDecoration(labelText: 'City'),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                    enabled: !submitting,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: TextFormField(
                    controller: _stateController,
                    decoration: const InputDecoration(labelText: 'State'),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                    enabled: !submitting,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            if (_listingType == 'commercial') _buildCommercialFields(submitting),
            if (_listingType == 'shortlet') _buildShortletFields(submitting),
            const SizedBox(height: AppSpacing.lg),
            Text('Photos', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            _ImageReorderList(
              images: _images,
              onReorder: submitting ? (_, __) {} : _reorderImages,
              onSetPrimary: submitting ? (_) {} : _setPrimaryImage,
            ),
            TextButton.icon(
              onPressed: submitting ? null : _addPickedImagePlaceholder,
              icon: const Icon(Icons.add_a_photo),
              label: const Text('Add photo'),
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton(
              onPressed: submitting ? null : _submit,
              child: submitting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Publish listing'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCommercialFields(bool submitting) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Commercial details', style: Theme.of(context).textTheme.titleMedium),
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
          validator: (v) => (double.tryParse(v ?? '') == null) ? 'Enter a valid price' : null,
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
          validator: (v) => (double.tryParse(v ?? '') == null) ? 'Enter a valid size' : null,
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
          onChanged: submitting ? null : (v) => setState(() => _propertySubtype = v!),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text('Room breakdown (optional)', style: Theme.of(context).textTheme.bodyMedium),
        ..._rooms.map(
          (r) => ListTile(
            dense: true,
            title: Text('${r.level}: ${r.widthMeters}m x ${r.lengthMeters}m'),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: submitting ? null : () => setState(() => _rooms.remove(r)),
            ),
          ),
        ),
        TextButton.icon(
          onPressed: submitting
              ? null
              : () => setState(
                    () => _rooms.add(
                      const CommercialRoom(level: 'ground', widthMeters: 0, lengthMeters: 0),
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
        Text('Shortlet details', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: AppSpacing.sm),
        TextFormField(
          controller: _nightlyPriceController,
          decoration: const InputDecoration(labelText: 'Nightly price (NGN)'),
          keyboardType: TextInputType.number,
          validator: (v) => (double.tryParse(v ?? '') == null) ? 'Enter a valid price' : null,
          enabled: !submitting,
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _minStayController,
                decoration: const InputDecoration(labelText: 'Min stay (nights)'),
                keyboardType: TextInputType.number,
                validator: (v) => (int.tryParse(v ?? '') == null) ? 'Required' : null,
                enabled: !submitting,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: TextFormField(
                controller: _maxStayController,
                decoration: const InputDecoration(labelText: 'Max stay (nights, optional)'),
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
          validator: (v) => (int.tryParse(v ?? '') == null) ? 'Enter a valid number' : null,
          enabled: !submitting,
        ),
        // Availability calendar (blocked_dates) is edited after creation on
        // the listing edit screen -- TODO: add a calendar widget there.
      ],
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
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
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
      return const Text('No photos added yet.', style: TextStyle(color: AppColors.textSecondary));
    }
    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: images.length,
      onReorder: onReorder,
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
