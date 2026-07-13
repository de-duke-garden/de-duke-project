/// Screen 20: Saved Searches (screens.md) -- FEAT-023.
/// Route: /search/saved (registered additively in
/// core/routing/app_router.dart).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/list_stagger.dart';
import '../../../core/widgets/skeleton_loader.dart';
import '../data/saved_search_models.dart';
import '../logic/saved_search_providers.dart';

class SavedSearchesScreen extends ConsumerStatefulWidget {
  const SavedSearchesScreen({super.key});

  @override
  ConsumerState<SavedSearchesScreen> createState() =>
      _SavedSearchesScreenState();
}

class _SavedSearchesScreenState extends ConsumerState<SavedSearchesScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(savedSearchNotifierProvider.notifier).load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(savedSearchNotifierProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Saved Searches')),
      body: _buildBody(state),
    );
  }

  Widget _buildBody(SavedSearchState state) {
    switch (state.status) {
      case SavedSearchStatus.loading:
        return ListView.builder(
          itemCount: 4,
          itemBuilder: (context, index) => const Padding(
            padding: EdgeInsets.symmetric(
                horizontal: AppSpacing.md, vertical: AppSpacing.xs),
            child: SkeletonRow(),
          ),
        );
      case SavedSearchStatus.error:
        return EmptyStateView(
          isError: true,
          title: 'Something went wrong',
          message: state.errorMessage ?? 'Could not load your saved searches.',
          actionLabel: 'Retry',
          onAction: () => ref.read(savedSearchNotifierProvider.notifier).load(),
        );
      case SavedSearchStatus.empty:
        return const EmptyStateView(
          title: 'No saved searches yet',
          message: 'Save a search to get notified about new matches.',
        );
      case SavedSearchStatus.loaded:
        return ListView.builder(
          itemCount: state.searches.length,
          itemBuilder: (context, index) {
            final search = state.searches[index];
            // `list-stagger` on first load per Screen 20 Modernization Notes.
            return ListStaggerItem(
              index: index,
              child: _SavedSearchRow(
                key: ValueKey(search.id),
                search: search,
                isPending: state.pendingIds.contains(search.id),
                onToggleAlerts: (enabled) async {
                  final ok = await ref
                      .read(savedSearchNotifierProvider.notifier)
                      .toggleAlerts(search.id, enabled);
                  if (!ok && mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text(
                              "Couldn't update alerts. Please try again.")),
                    );
                  }
                },
                onDelete: () async {
                  final ok = await ref
                      .read(savedSearchNotifierProvider.notifier)
                      .delete(search.id);
                  if (!ok && mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text(
                              "Couldn't delete this saved search. Please try again.")),
                    );
                  }
                },
              ),
            );
          },
        );
    }
  }
}

class _SavedSearchRow extends StatelessWidget {
  const _SavedSearchRow({
    super.key,
    required this.search,
    required this.isPending,
    required this.onToggleAlerts,
    required this.onDelete,
  });

  final SavedSearch search;
  final bool isPending;
  final ValueChanged<bool> onToggleAlerts;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey('dismissible-${search.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        color: AppColors.error,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      confirmDismiss: (_) => showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Delete saved search?'),
          content: Text('"${search.label}" will no longer alert you to new matches.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete'),
            ),
          ],
        ),
      ).then((confirmed) => confirmed ?? false),
      onDismissed: (_) => onDelete(),
      child: ListTile(
        title: Text(search.label),
        subtitle: Text(search.filterSummary),
        trailing: isPending
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Switch(
                value: search.alertsEnabled,
                onChanged: onToggleAlerts,
              ),
      ),
    );
  }
}
