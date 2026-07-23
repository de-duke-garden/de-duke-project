/// FEAT-007 filter panel -- Screen 5's `ModalBottomSheet` (price range
/// slider, property type, verified-only switch, sort dropdown, etc).
library;

import 'package:flutter/material.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/currency_format.dart';
import '../data/search_models.dart';

Future<void> showSearchFilterSheet({
  required BuildContext context,
  required SearchQueryState current,
  required void Function(SearchQueryState) onApply,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) =>
        _FilterSheetContent(current: current, onApply: onApply),
  );
}

class _FilterSheetContent extends StatefulWidget {
  const _FilterSheetContent({required this.current, required this.onApply});

  final SearchQueryState current;
  final void Function(SearchQueryState) onApply;

  @override
  State<_FilterSheetContent> createState() => _FilterSheetContentState();
}

class _FilterSheetContentState extends State<_FilterSheetContent> {
  late SearchQueryState _draft = widget.current;

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.of(context).size.height * 0.85;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: SingleChildScrollView(
          padding: EdgeInsets.only(
            left: AppSpacing.lg,
            right: AppSpacing.lg,
            top: AppSpacing.lg,
            bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Filters',
                      style:
                          TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                  TextButton(
                    onPressed: () =>
                        setState(() => _draft = _draft.clearAllFilters()),
                    child: const Text('Clear all'),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              _buildListingTypeRow(),
              const SizedBox(height: AppSpacing.md),
              _buildDealTypeRow(),
              const SizedBox(height: AppSpacing.md),
              _buildSubtypeRow(),
              const SizedBox(height: AppSpacing.md),
              _buildPriceRange(),
              const SizedBox(height: AppSpacing.md),
              _buildSizeRange(),
              const SizedBox(height: AppSpacing.md),
              _buildBathrooms(),
              const SizedBox(height: AppSpacing.md),
              _buildVerifiedOnlySwitch(),
              const SizedBox(height: AppSpacing.md),
              _buildSortRow(),
              const SizedBox(height: AppSpacing.lg),
              SizedBox(
                height: AppSpacing.xxl,
                child: ElevatedButton(
                  onPressed: () {
                    widget.onApply(_draft);
                    Navigator.of(context).pop();
                  },
                  // No explicit style override needed -- ElevatedButtonTheme
                  // (AppTheme) already resolves background/foreground from
                  // the current ColorScheme per brightness.
                  child: const Text('Apply filters'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildListingTypeRow() {
    return _FilterSection(
      label: 'Listing type',
      child: Wrap(
        spacing: AppSpacing.sm,
        children: [
          ChoiceChip(
            label: const Text('Commercial'),
            selected: _draft.listingType == ListingTypeFilter.commercial,
            onSelected: (selected) => setState(() {
              _draft = _draft.copyWith(
                listingType: selected ? ListingTypeFilter.commercial : null,
                clearListingType: !selected,
                clearCommercialSubtype: true,
                clearShortletSubtype: true,
              );
            }),
          ),
          ChoiceChip(
            label: const Text('Shortlet'),
            selected: _draft.listingType == ListingTypeFilter.shortlet,
            onSelected: (selected) => setState(() {
              _draft = _draft.copyWith(
                listingType: selected ? ListingTypeFilter.shortlet : null,
                clearListingType: !selected,
                clearCommercialSubtype: true,
                clearShortletSubtype: true,
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildDealTypeRow() {
    if (_draft.listingType == ListingTypeFilter.shortlet) {
      return const SizedBox.shrink();
    }
    return _FilterSection(
      label: 'Deal type',
      child: Wrap(
        spacing: AppSpacing.sm,
        children: DealTypeFilter.values.map((dealType) {
          return ChoiceChip(
            label: Text(dealType.label),
            selected: _draft.dealType == dealType,
            onSelected: (selected) => setState(() {
              _draft = _draft.copyWith(
                  dealType: selected ? dealType : null,
                  clearDealType: !selected);
            }),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildSubtypeRow() {
    if (_draft.listingType == ListingTypeFilter.shortlet) {
      return _FilterSection(
        label: 'Shortlet type',
        child: Wrap(
          spacing: AppSpacing.sm,
          children: ShortletSubtype.values.map((subtype) {
            return ChoiceChip(
              label: Text(subtype.label),
              selected: _draft.shortletSubtype == subtype,
              onSelected: (selected) => setState(() {
                _draft = _draft.copyWith(
                  shortletSubtype: selected ? subtype : null,
                  clearShortletSubtype: !selected,
                );
              }),
            );
          }).toList(),
        ),
      );
    }
    return _FilterSection(
      label: 'Property type',
      child: Wrap(
        spacing: AppSpacing.sm,
        children: CommercialSubtype.values.map((subtype) {
          return ChoiceChip(
            label: Text(subtype.label),
            selected: _draft.commercialSubtype == subtype,
            onSelected: (selected) => setState(() {
              _draft = _draft.copyWith(
                commercialSubtype: selected ? subtype : null,
                clearCommercialSubtype: !selected,
              );
            }),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildPriceRange() {
    final min = _draft.minPrice ?? 0;
    final max = _draft.maxPrice ?? 500000000;
    return _FilterSection(
      label: 'Price range (NGN)',
      child: RangeSlider(
        min: 0,
        max: 500000000,
        divisions: 50,
        values: RangeValues(min, max),
        labels: RangeLabels(formatAmount(min), formatAmount(max)),
        activeColor: Theme.of(context).colorScheme.primary,
        onChanged: (values) => setState(() {
          _draft =
              _draft.copyWith(minPrice: values.start, maxPrice: values.end);
        }),
      ),
    );
  }

  Widget _buildSizeRange() {
    if (_draft.listingType == ListingTypeFilter.shortlet) {
      return const SizedBox.shrink();
    }
    final min = _draft.minSizeSqm ?? 0;
    final max = _draft.maxSizeSqm ?? 2000;
    return _FilterSection(
      label: 'Size range (sqm)',
      child: RangeSlider(
        min: 0,
        max: 2000,
        divisions: 40,
        values: RangeValues(min, max),
        labels: RangeLabels(min.toStringAsFixed(0), max.toStringAsFixed(0)),
        activeColor: Theme.of(context).colorScheme.primary,
        onChanged: (values) => setState(() {
          _draft =
              _draft.copyWith(minSizeSqm: values.start, maxSizeSqm: values.end);
        }),
      ),
    );
  }

  Widget _buildBathrooms() {
    // Bathrooms filter -- backed by CommercialListing.bathrooms /
    // ShortletListing.bathrooms server-side (app/services/search_service.py).
    return _FilterSection(
      label: 'Bathrooms',
      child: Wrap(
        spacing: AppSpacing.sm,
        children: [1, 2, 3, 4].map((count) {
          return ChoiceChip(
            label: Text('$count+'),
            selected: _draft.bathrooms == count,
            onSelected: (selected) => setState(() {
              _draft = _draft.copyWith(
                  bathrooms: selected ? count : null,
                  clearBathrooms: !selected);
            }),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildVerifiedOnlySwitch() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text('Verified Host only',
            style: TextStyle(fontWeight: FontWeight.w600)),
        Switch(
          value: _draft.verifiedOnly,
          activeThumbColor: Theme.of(context).colorScheme.primary,
          onChanged: (value) =>
              setState(() => _draft = _draft.copyWith(verifiedOnly: value)),
        ),
      ],
    );
  }

  Widget _buildSortRow() {
    return _FilterSection(
      label: 'Sort by',
      child: DropdownButtonFormField<SortField>(
        initialValue: _draft.sortBy,
        items: SortField.values
            .map((field) =>
                DropdownMenuItem(value: field, child: Text(field.label)))
            .toList(),
        onChanged: (value) {
          if (value != null) {
            setState(() => _draft = _draft.copyWith(sortBy: value));
          }
        },
      ),
    );
  }
}

class _FilterSection extends StatelessWidget {
  const _FilterSection({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
        const SizedBox(height: AppSpacing.sm),
        child,
      ],
    );
  }
}
