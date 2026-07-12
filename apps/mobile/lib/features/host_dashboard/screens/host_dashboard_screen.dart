/// screens.md Screen 12: Host Dashboard (FEAT-017). Fetches listings and
/// verification status in parallel per that screen's Data Flow step 1.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_spacing.dart';
import '../../become_host/data/host_account_models.dart';
import '../../become_host/data/host_account_repository.dart';
import '../data/host_dashboard_models.dart';
import '../data/host_dashboard_repository.dart';

enum _ScreenState { loading, unverified, loaded, empty, error, offline }

class HostDashboardScreen extends StatefulWidget {
  const HostDashboardScreen({
    super.key,
    required this.dashboardRepository,
    required this.hostAccountRepository,
  });

  final HostDashboardRepository dashboardRepository;
  final HostAccountRepository hostAccountRepository;

  @override
  State<HostDashboardScreen> createState() => _HostDashboardScreenState();
}

class _HostDashboardScreenState extends State<HostDashboardScreen> {
  _ScreenState _state = _ScreenState.loading;
  List<HostDashboardListingItem> _listings = [];
  HostAccountStatus? _verification;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _state = _ScreenState.loading);
    try {
      final verificationFuture = widget.hostAccountRepository.getMySubmission();
      final listingsFuture = widget.dashboardRepository.getMyListings();
      final verification = await verificationFuture;
      final listings = await listingsFuture;

      if (!mounted) return;
      setState(() {
        _verification = verification;
        _listings = listings;
        if (verification == null || verification.status != 'verified') {
          _state = _ScreenState.unverified;
        } else if (listings.isEmpty) {
          _state = _ScreenState.empty;
        } else {
          _state = _ScreenState.loaded;
        }
      });
    } on HostDashboardException catch (e) {
      if (!mounted) return;
      setState(() => _state = e.message == 'offline' ? _ScreenState.offline : _ScreenState.error);
    } catch (_) {
      if (!mounted) return;
      setState(() => _state = _ScreenState.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Listings'),
        automaticallyImplyLeading: false, // tab root (core/routing/app_shell.dart)
        actions: [
          if (_verification != null)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.md),
              child: Center(
                child: TextButton(
                  onPressed: () => context.push('/verification'),
                  child: Text(_verification!.status == 'verified' ? 'Verified Host' : 'Verify'),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _state == _ScreenState.unverified
            ? () => context.push('/verification')
            : () => context.push('/listing/new'),
        icon: const Icon(Icons.add),
        label: const Text('New Listing'),
      ),
      body: SafeArea(child: _buildBody(context)),
    );
  }

  Widget _buildBody(BuildContext context) {
    switch (_state) {
      case _ScreenState.loading:
        return ListView.builder(
          padding: const EdgeInsets.all(AppSpacing.md),
          itemCount: 4,
          itemBuilder: (_, __) => Container(
            height: 88,
            margin: const EdgeInsets.only(bottom: AppSpacing.sm),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(AppRadii.md),
            ),
          ),
        );
      case _ScreenState.unverified:
        return Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Verify your identity to start listing',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  ElevatedButton(
                    onPressed: () => context.push('/verification'),
                    child: const Text('Become a Host'),
                  ),
                ],
              ),
            ),
          ),
        );
      case _ScreenState.empty:
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.home_work_outlined, size: 48),
              const SizedBox(height: AppSpacing.sm),
              const Text("You haven't listed anything yet"),
              const SizedBox(height: AppSpacing.sm),
              ElevatedButton(
                onPressed: () => context.push('/listing/new'),
                child: const Text('Create your first listing'),
              ),
            ],
          ),
        );
      case _ScreenState.error:
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48),
              const SizedBox(height: AppSpacing.sm),
              const Text('Something went wrong'),
              TextButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        );
      case _ScreenState.offline:
        return Column(
          children: [
            MaterialBanner(
              content: const Text("You're offline."),
              actions: [TextButton(onPressed: _load, child: const Text('Retry'))],
            ),
            if (_listings.isNotEmpty) Expanded(child: _buildListingList(context)),
          ],
        );
      case _ScreenState.loaded:
        return RefreshIndicator(onRefresh: _load, child: _buildListingList(context));
    }
  }

  Widget _buildListingList(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(AppSpacing.md),
      itemCount: _listings.length,
      itemBuilder: (context, index) => _ListingStatusCard(
        listing: _listings[index],
        onTap: () => context.push('/listing/${_listings[index].id}'),
      ),
    );
  }
}

class _ListingStatusCard extends StatelessWidget {
  const _ListingStatusCard({required this.listing, required this.onTap});

  final HostDashboardListingItem listing;
  final VoidCallback onTap;

  Color _statusColor(BuildContext context) {
    return switch (listing.status) {
      'active' => Colors.green,
      'banned' => Theme.of(context).colorScheme.error,
      _ => Colors.orange, // under_review | unpublished | closed
    };
  }

  String _statusLabel() {
    return switch (listing.status) {
      'active' => 'Active',
      'under_review' => 'Under Review',
      'banned' => 'Banned',
      'unpublished' => 'Unpublished',
      'closed' => 'Closed',
      _ => listing.status,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.md),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(listing.title, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: AppSpacing.xs),
                    Row(
                      children: [
                        Chip(
                          label: Text(_statusLabel()),
                          backgroundColor: _statusColor(context).withValues(alpha: 0.15),
                          labelStyle: TextStyle(color: _statusColor(context)),
                          visualDensity: VisualDensity.compact,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Text('${listing.viewCount} views · ${listing.inquiryCount} inquiries'),
                      ],
                    ),
                    if (listing.status == 'banned' && listing.statusReason != null)
                      Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.xs),
                        child: Text(
                          listing.statusReason!,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: Theme.of(context).colorScheme.error),
                        ),
                      ),
                    if (listing.isStale)
                      const Padding(
                        padding: EdgeInsets.only(top: AppSpacing.xs),
                        child: Text(
                          'No activity yet — consider updating photos or price',
                          style: TextStyle(fontStyle: FontStyle.italic, fontSize: 12),
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chat_bubble_outline),
                tooltip: 'Chat threads',
                onPressed: () => context.push('/chat'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
