/// Address text field with live Google Places Autocomplete suggestions.
/// Selecting a suggestion resolves to a real coordinate via Place Details
/// and reports it back through [onPlaceSelected] -- this is the address
/// half of Create Listing's bidirectional address/map-pin sync (the other
/// half, pin -> address via reverse geocoding, lives in the caller).
///
/// Typing without selecting a suggestion still updates [controller]'s text
/// (so the field behaves like a normal TextFormField for validation/manual
/// entry), but does NOT set a coordinate -- only a selected suggestion is
/// considered "traceable" per the product requirement that a listing's
/// address always resolves to a real, Google-verified location.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../services/places_service.dart';

class AddressAutocompleteField extends StatefulWidget {
  const AddressAutocompleteField({
    super.key,
    required this.controller,
    required this.enabled,
    required this.onPlaceSelected,
  });

  final TextEditingController controller;
  final bool enabled;
  final void Function(PlaceDetails details) onPlaceSelected;

  @override
  State<AddressAutocompleteField> createState() =>
      _AddressAutocompleteFieldState();
}

class _AddressAutocompleteFieldState extends State<AddressAutocompleteField> {
  List<PlaceSuggestion> _suggestions = const [];
  Timer? _debounce;
  String? _sessionToken;
  bool _loading = false;

  // Set right before programmatically writing widget.controller.text after
  // a selection, so the resulting onChanged doesn't immediately re-query
  // suggestions for the text we just wrote.
  bool _suppressNextChange = false;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(String value) {
    if (_suppressNextChange) {
      _suppressNextChange = false;
      return;
    }
    _sessionToken ??= const Uuid().v4();

    _debounce?.cancel();
    if (value.trim().length < 3) {
      setState(() => _suggestions = const []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      setState(() => _loading = true);
      final results =
          await autocompleteAddress(value, sessionToken: _sessionToken);
      if (!mounted) return;
      setState(() {
        _suggestions = results;
        _loading = false;
      });
    });
  }

  Future<void> _select(PlaceSuggestion suggestion) async {
    final token = _sessionToken;
    setState(() {
      _suggestions = const [];
      _loading = true;
    });

    final details =
        await placeDetails(suggestion.placeId, sessionToken: token);
    // A fresh session token per completed lookup -- Places billing treats
    // an autocomplete-then-details pair sharing a token as one session.
    _sessionToken = null;

    if (!mounted) return;
    setState(() => _loading = false);
    if (details == null) return;

    _suppressNextChange = true;
    widget.controller.text =
        details.formattedAddress.isNotEmpty
            ? details.formattedAddress
            : suggestion.description;
    widget.onPlaceSelected(details);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: widget.controller,
          decoration: InputDecoration(
            labelText: 'Address line',
            suffixIcon: _loading
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : null,
          ),
          enabled: widget.enabled,
          onChanged: _onChanged,
        ),
        if (_suggestions.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).dividerColor),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: _suggestions
                  .map(
                    (s) => ListTile(
                      dense: true,
                      leading: const Icon(Icons.location_on_outlined),
                      title: Text(s.description),
                      onTap: () => _select(s),
                    ),
                  )
                  .toList(),
            ),
          ),
      ],
    );
  }
}
