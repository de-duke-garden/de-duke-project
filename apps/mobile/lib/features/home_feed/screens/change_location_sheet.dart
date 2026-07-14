/// Home Feed's "change search location" bottom sheet (screens.md Screen 4
/// Components table: "Location indicator ... Shows/change current search
/// location"). Was a static label with a "not available yet" snackbar --
/// this fills that gap using the same two location-input methods Create
/// Listing already offers (device GPS via geolocator, address search via
/// Google Places Autocomplete) minus the map-pin tab, since Home Feed only
/// needs a coordinate + short label, not a precisely-placed listing pin.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../../core/services/places_service.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/address_autocomplete_field.dart';

/// Result of a successful pick -- [label] is what the AppBar's location
/// indicator shows afterward (city name), distinct from the full
/// coordinate used for the actual search query.
class ChangeLocationResult {
  const ChangeLocationResult({
    required this.latitude,
    required this.longitude,
    required this.label,
  });

  final double latitude;
  final double longitude;
  final String label;
}

/// Shows the sheet and returns the picked location, or `null` if the user
/// dismissed it without picking one.
Future<ChangeLocationResult?> showChangeLocationSheet(BuildContext context) {
  return showModalBottomSheet<ChangeLocationResult>(
    context: context,
    isScrollControlled: true,
    builder: (context) => const _ChangeLocationSheet(),
  );
}

class _ChangeLocationSheet extends StatefulWidget {
  const _ChangeLocationSheet();

  @override
  State<_ChangeLocationSheet> createState() => _ChangeLocationSheetState();
}

class _ChangeLocationSheetState extends State<_ChangeLocationSheet> {
  final _addressController = TextEditingController();
  bool _locatingDevice = false;
  String? _errorMessage;

  @override
  void dispose() {
    _addressController.dispose();
    super.dispose();
  }

  void _showError(String message) {
    if (!mounted) return;
    setState(() => _errorMessage = message);
  }

  /// Same GPS flow as Create Listing's `_useGpsLocation` (geolocator
  /// service/permission checks, then a reverse-geocode for a human-readable
  /// city label) -- duplicated rather than shared because that method also
  /// drives create_listing_screen's own map-pin/segmented-control state,
  /// which doesn't exist here.
  Future<void> _useDeviceLocation() async {
    setState(() {
      _locatingDevice = true;
      _errorMessage = null;
    });

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() => _locatingDevice = false);
      _showError('Location services are turned off. Enable them in system settings.');
      return;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      setState(() => _locatingDevice = false);
      _showError('Location permission denied.');
      return;
    }
    if (permission == LocationPermission.deniedForever) {
      setState(() => _locatingDevice = false);
      _showError('Location permission permanently denied. Enable it from app settings.');
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
      final geocoded = await reverseGeocode(position.latitude, position.longitude);
      if (!mounted) return;
      Navigator.of(context).pop(
        ChangeLocationResult(
          latitude: position.latitude,
          longitude: position.longitude,
          // Falls back to a generic label rather than blocking the pick --
          // geocoding is a label-quality nicety here, the coordinate itself
          // is already good the moment GPS resolves.
          label: (geocoded?.city.isNotEmpty ?? false) ? geocoded!.city : 'Current location',
        ),
      );
    } on TimeoutException {
      setState(() => _locatingDevice = false);
      _showError('Timed out getting your location. Try again.');
    } catch (_) {
      setState(() => _locatingDevice = false);
      _showError('Could not get your location. Try again.');
    }
  }

  /// Address field only sets a coordinate via a selected Places Autocomplete
  /// suggestion (never plain typed text) -- same "always resolves to a
  /// real, verified location" rule create_listing_screen's own address
  /// field follows.
  void _onPlaceSelected(PlaceDetails details) {
    Navigator.of(context).pop(
      ChangeLocationResult(
        latitude: details.latitude,
        longitude: details.longitude,
        label: details.city.isNotEmpty ? details.city : details.formattedAddress,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.md,
        right: AppSpacing.md,
        top: AppSpacing.md,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.md,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Change search location', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          if (_errorMessage != null) ...[
            Text(_errorMessage!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            const SizedBox(height: AppSpacing.sm),
          ],
          OutlinedButton.icon(
            onPressed: _locatingDevice ? null : _useDeviceLocation,
            icon: _locatingDevice
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.my_location),
            label: const Text('Use current location'),
          ),
          const SizedBox(height: AppSpacing.md),
          Text('Or search for a location',
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: AppSpacing.xs),
          AddressAutocompleteField(
            controller: _addressController,
            enabled: !_locatingDevice,
            onPlaceSelected: _onPlaceSelected,
          ),
        ],
      ),
    );
  }
}
