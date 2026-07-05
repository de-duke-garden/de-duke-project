/// Map view for Screen 5's Map/List toggle. FEAT-006 acceptance criterion:
/// "Results update when the user pans/zooms a map view" -- implemented as an
/// explicit "Search this area" button (per screens.md's own Edge Case note:
/// "offer a 'Search this area' button rather than auto-refetching on every
/// pixel of movement").
library;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../data/search_models.dart';

class SearchMapView extends StatefulWidget {
  const SearchMapView({
    super.key,
    required this.results,
    required this.onMarkerTap,
    required this.onSearchThisArea,
  });

  final List<ListingSearchResult> results;
  final void Function(String listingId) onMarkerTap;
  final void Function(double latitude, double longitude) onSearchThisArea;

  @override
  State<SearchMapView> createState() => _SearchMapViewState();
}

class _SearchMapViewState extends State<SearchMapView> {
  // Kept for future use (e.g. programmatically re-centering the camera);
  // not currently read, so onMapCreated intentionally discards it below
  // rather than declaring an unused field.
  CameraPosition? _lastMovedCamera;
  bool _showSearchThisArea = false;

  @override
  Widget build(BuildContext context) {
    final initialTarget = widget.results.isNotEmpty
        ? LatLng(widget.results.first.latitude, widget.results.first.longitude)
        : const LatLng(6.5244, 3.3792); // Lagos, Nigeria -- sensible default center

    return Stack(
      children: [
        GoogleMap(
          initialCameraPosition: CameraPosition(target: initialTarget, zoom: 13),
          onCameraMove: (position) {
            _lastMovedCamera = position;
            if (!_showSearchThisArea) setState(() => _showSearchThisArea = true);
          },
          markers: widget.results
              .map(
                (result) => Marker(
                  markerId: MarkerId(result.id),
                  position: LatLng(result.latitude, result.longitude),
                  infoWindow: InfoWindow(
                    title: result.title,
                    snippet: result.displayPrice != null ? '₦${result.displayPrice!.toStringAsFixed(0)}' : null,
                    onTap: () => widget.onMarkerTap(result.id),
                  ),
                ),
              )
              .toSet(),
        ),
        if (_showSearchThisArea)
          Positioned(
            top: AppSpacing.md,
            left: 0,
            right: 0,
            child: Center(
              child: ElevatedButton.icon(
                onPressed: () {
                  final target = _lastMovedCamera?.target ?? initialTarget;
                  widget.onSearchThisArea(target.latitude, target.longitude);
                  setState(() => _showSearchThisArea = false);
                },
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                icon: const Icon(Icons.search, color: Colors.white, size: 18),
                label: const Text('Search this area', style: TextStyle(color: Colors.white)),
              ),
            ),
          ),
      ],
    );
  }
}
