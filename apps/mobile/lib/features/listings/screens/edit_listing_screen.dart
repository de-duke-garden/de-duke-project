/// Edit Listing -- FEAT-004 AC "Host can edit the price, location, or
/// other details, or unpublish an existing listing." No dedicated
/// screens.md screen number exists for this yet (screens.md's Host
/// Dashboard, Screen 12, only lists "Listing Detail (own listings)" as its
/// exit point) -- this fills a confirmed real gap: hosts had no way to
/// edit a fixed price/description or take a listing down after
/// publishing, despite it being an explicit FEAT-004 acceptance criterion.
/// Modeled on Create Listing's single-page field styling rather than its
/// multi-step wizard, since editing an existing listing is a much smaller
/// task than authoring one from scratch.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/route_names.dart';
import '../../../core/theme/app_spacing.dart';
import '../data/listing_models.dart';
import '../data/listing_repository.dart';

enum _ScreenState { loading, loaded, error, offline }
enum _SaveState { idle, saving, error }

class EditListingScreen extends StatefulWidget {
  const EditListingScreen({
    super.key,
    required this.listingId,
    required this.repository,
  });

  final String listingId;
  final ListingRepository repository;

  @override
  State<EditListingScreen> createState() => _EditListingScreenState();
}

class _EditListingScreenState extends State<EditListingScreen> {
  final _formKey = GlobalKey<FormState>();
  _ScreenState _state = _ScreenState.loading;
  _SaveState _saveState = _SaveState.idle;
  String? _errorMessage;
  String? _saveErrorMessage;

  Listing? _listing;
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _priceController = TextEditingController();
  // FEAT-018 AC "originating client/owner" tagging -- only meaningful for
  // agency-owned listings (see Listing.ownerClientName's docstring), but
  // shown for every listing rather than conditioned on a role check here:
  // it's harmless to leave blank, and a host who becomes agency-affiliated
  // later doesn't need a different edit screen to start using it.
  final _ownerClientNameController = TextEditingController();
  // Active/Unpublished only -- a host can't set under_review/banned
  // themselves (see ListingRepository.updateListing's docstring); those
  // stay whatever the backend already reports until staff act on them, so
  // this switch is disabled entirely outside that pair.
  bool _isPublished = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _priceController.dispose();
    _ownerClientNameController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _state = _ScreenState.loading;
      _errorMessage = null;
    });
    try {
      final listing = await widget.repository.getListing(widget.listingId);
      if (!mounted) return;
      setState(() {
        _listing = listing;
        _titleController.text = listing.title;
        _descriptionController.text = listing.description;
        _priceController.text =
            (listing.commercial?.price ?? listing.shortlet?.nightlyPrice ?? 0)
                .toStringAsFixed(0);
        _ownerClientNameController.text = listing.ownerClientName ?? '';
        _isPublished = listing.status == 'active';
        _state = _ScreenState.loaded;
      });
    } catch (e) {
      if (!mounted) return;
      final message = e.toString();
      setState(() {
        _state = message.contains('SocketException') ||
                message.contains('connection')
            ? _ScreenState.offline
            : _ScreenState.error;
        _errorMessage = 'Could not load this listing.';
      });
    }
  }

  Future<void> _save() async {
    final listing = _listing;
    if (listing == null || !_formKey.currentState!.validate()) return;

    final price = double.tryParse(_priceController.text.trim());
    if (price == null) {
      setState(() {
        _saveState = _SaveState.error;
        _saveErrorMessage = 'Enter a valid price.';
      });
      return;
    }

    // A host can only ever move between active/unpublished (see
    // ListingRepository.updateListing's docstring) -- if the listing is
    // currently under_review/banned, the toggle above is disabled and this
    // simply omits `status` from the request rather than sending a value
    // the backend would reject anyway.
    final canTogglePublished =
        listing.status == 'active' || listing.status == 'unpublished';

    setState(() {
      _saveState = _SaveState.saving;
      _saveErrorMessage = null;
    });

    try {
      await widget.repository.updateListing(
        widget.listingId,
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        status: canTogglePublished
            ? (_isPublished ? 'active' : 'unpublished')
            : null,
        ownerClientName: _ownerClientNameController.text.trim(),
        commercial: listing.commercial == null
            ? null
            : (CommercialListingDetails(
                dealType: listing.commercial!.dealType,
                price: price,
                possessionPeriodDays: listing.commercial!.possessionPeriodDays,
                sizeSquareMeters: listing.commercial!.sizeSquareMeters,
                propertySubtype: listing.commercial!.propertySubtype,
                bathrooms: listing.commercial!.bathrooms,
                legalDocuments: listing.commercial!.legalDocuments,
                rooms: listing.commercial!.rooms,
              )),
        shortlet: listing.shortlet == null
            ? null
            : (ShortletListingDetails(
                nightlyPrice: price,
                minimumStayNights: listing.shortlet!.minimumStayNights,
                maximumStayNights: listing.shortlet!.maximumStayNights,
                bedrooms: listing.shortlet!.bedrooms,
                bathrooms: listing.shortlet!.bathrooms,
                subtype: listing.shortlet!.subtype,
                houseRules: listing.shortlet!.houseRules,
                blockedDates: listing.shortlet!.blockedDates,
              )),
      );
      if (!mounted) return;
      // Pops back to My Listings with a signal to refresh, rather than
      // pushing the read-only Listing Detail screen -- there's nothing
      // further to do here once a save succeeds.
      context.pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saveState = _SaveState.error;
        _saveErrorMessage = "Couldn't save your changes. Try again.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Listing'),
        actions: [
          if (_state == _ScreenState.loaded)
            IconButton(
              onPressed: () => context.pushNamed(
                RouteNames.listingDetail,
                pathParameters: {'id': widget.listingId},
              ),
              icon: const Icon(Icons.visibility_outlined),
              tooltip: 'View listing',
            ),
        ],
      ),
      body: switch (_state) {
        _ScreenState.loading =>
          const Center(child: CircularProgressIndicator()),
        _ScreenState.error || _ScreenState.offline => Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 48),
                  const SizedBox(height: AppSpacing.md),
                  Text(_errorMessage ?? 'Something went wrong.',
                      textAlign: TextAlign.center),
                  const SizedBox(height: AppSpacing.md),
                  ElevatedButton(onPressed: _load, child: const Text('Retry')),
                ],
              ),
            ),
          ),
        _ScreenState.loaded => _buildForm(context),
      },
    );
  }

  Widget _buildForm(BuildContext context) {
    final listing = _listing!;
    final canTogglePublished =
        listing.status == 'active' || listing.status == 'unpublished';
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          if (_saveErrorMessage != null) ...[
            Text(_saveErrorMessage!,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
            const SizedBox(height: AppSpacing.sm),
          ],
          TextFormField(
            controller: _titleController,
            decoration: const InputDecoration(labelText: 'Title'),
            enabled: _saveState != _SaveState.saving,
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Title is required.' : null,
          ),
          const SizedBox(height: AppSpacing.sm),
          TextFormField(
            controller: _descriptionController,
            decoration: const InputDecoration(
                labelText: 'Description', alignLabelWithHint: true),
            minLines: 3,
            maxLines: 6,
            enabled: _saveState != _SaveState.saving,
            validator: (v) => (v == null || v.trim().isEmpty)
                ? 'Description is required.'
                : null,
          ),
          const SizedBox(height: AppSpacing.sm),
          TextFormField(
            controller: _priceController,
            decoration: InputDecoration(
              labelText: listing.commercial != null
                  ? 'Price (NGN)'
                  : 'Nightly price (NGN)',
            ),
            keyboardType: TextInputType.number,
            enabled: _saveState != _SaveState.saving,
            validator: (v) =>
                (double.tryParse(v ?? '') == null) ? 'Enter a valid price.' : null,
          ),
          const SizedBox(height: AppSpacing.sm),
          // FEAT-018 AC "originating client/owner" tagging -- optional for
          // every listing, most relevant for agency-managed ones (Screen
          // 14's Portfolio List View shows it per row when set).
          TextFormField(
            controller: _ownerClientNameController,
            decoration: const InputDecoration(
              labelText: 'Owner/Client name (optional)',
              helperText:
                  "For agency-managed listings -- who this property belongs to.",
            ),
            enabled: _saveState != _SaveState.saving,
          ),
          const SizedBox(height: AppSpacing.lg),
          // FEAT-004 AC "... or unpublish an existing listing" -- the
          // piece of this screen that previously didn't exist anywhere in
          // the app at all.
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Published'),
            subtitle: Text(
              canTogglePublished
                  ? (_isPublished
                      ? 'Visible to guests in search and on your listing page.'
                      : 'Hidden from search -- you can republish any time.')
                  : "This listing is ${_statusLabel(listing.status)} and can't be toggled here.",
            ),
            value: _isPublished,
            onChanged: (!canTogglePublished || _saveState == _SaveState.saving)
                ? null
                : (value) => setState(() => _isPublished = value),
          ),
          const SizedBox(height: AppSpacing.lg),
          ElevatedButton(
            onPressed: _saveState == _SaveState.saving ? null : _save,
            child: _saveState == _SaveState.saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save changes'),
          ),
        ],
      ),
    );
  }

  String _statusLabel(String status) => switch (status) {
        'under_review' => 'under review',
        'banned' => 'banned',
        _ => status,
      };
}
