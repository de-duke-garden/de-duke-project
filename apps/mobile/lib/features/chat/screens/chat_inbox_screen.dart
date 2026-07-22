/// screens.md Screen 8: Chat Inbox.
/// Shows all of the current user's conversations, merged across both
/// possible participant roles (a user could be the client in one
/// conversation and property management in another -- e.g. a
/// host who is also renting elsewhere as a guest).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/route_names.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/badge_pop.dart';
import '../../../core/widgets/branded_refresh_indicator.dart';
import '../../../core/widgets/de_duke_logo.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/list_stagger.dart';
import '../../../core/widgets/listing_title_text.dart';
import '../../../core/widgets/skeleton_loader.dart';
import '../../../core/widgets/tap_scale.dart';
import '../../auth/data/auth_repository.dart';
import '../../listings/data/listing_repository.dart';
import '../data/chat_models.dart';
import '../data/chat_repository.dart';

enum _ScreenState { loading, loaded, empty, error, offline }

class ChatInboxScreen extends StatefulWidget {
  const ChatInboxScreen({
    super.key,
    required this.chatRepository,
    required this.authRepository,
    required this.listingRepository,
  });

  final ChatRepository chatRepository;
  final AuthRepository authRepository;

  /// Resolves each conversation's `listingId` to its listing title for the
  /// tile heading -- previously the tile showed the raw listing id.
  final ListingRepository listingRepository;

  @override
  State<ChatInboxScreen> createState() => _ChatInboxScreenState();
}

class _ChatInboxScreenState extends State<ChatInboxScreen> {
  _ScreenState _state = _ScreenState.loading;
  String? _errorMessage;
  String? _currentUserId;

  List<ChatConversation> _asClient = [];
  List<ChatConversation> _asPropertyManagement = [];

  // list-stagger applies to first load (and, since this is a bottom-nav
  // tab kept alive by IndexedStack, is re-armed whenever the screen is
  // rebuilt from a fresh `_init()` call) -- not to live in-place updates
  // from the real-time stream, which should update silently/with badge-pop.
  bool _isFirstPaint = true;

  StreamSubscription<List<ChatConversation>>? _clientSub;
  StreamSubscription<List<ChatConversation>>? _pmSub;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _clientSub?.cancel();
    _pmSub?.cancel();
    super.dispose();
  }

  Future<void> _init() async {
    setState(() {
      _state = _ScreenState.loading;
      _errorMessage = null;
      _isFirstPaint = true;
    });
    try {
      await widget.chatRepository.ensureSignedIn();
      final user = await widget.authRepository.getCurrentUser();
      _currentUserId = user.userId;

      _clientSub?.cancel();
      _pmSub?.cancel();
      _clientSub = widget.chatRepository
          .watchConversationsFor(user.userId, asClient: true)
          .listen((items) => _onUpdate(client: items), onError: _onStreamError);
      _pmSub = widget.chatRepository
          .watchConversationsFor(user.userId, asClient: false)
          .listen((items) => _onUpdate(propertyManagement: items),
              onError: _onStreamError);
    } catch (e) {
      if (!mounted) return;
      final message = e is AuthException ? e.message : 'Something went wrong.';
      setState(() {
        _state =
            message == 'offline' ? _ScreenState.offline : _ScreenState.error;
        _errorMessage = message == 'offline'
            ? "You're offline. Showing your last cached conversations."
            : message;
      });
    }
  }

  /// Firestore stream errors (e.g. a missing composite index, a rules
  /// regression, a permission change) surface here rather than through the
  /// `_init()` try/catch above -- without this handler they'd terminate the
  /// subscription silently and strand the screen on the loading skeleton
  /// forever with no visible signal to the user or the developer.
  void _onStreamError(Object error, StackTrace stackTrace) {
    if (!mounted) return;
    setState(() {
      _state = _ScreenState.error;
      _errorMessage = 'Something went wrong.';
    });
  }

  void _onUpdate(
      {List<ChatConversation>? client,
      List<ChatConversation>? propertyManagement}) {
    if (!mounted) return;
    setState(() {
      if (client != null) {
        _asClient = client;
      }
      if (propertyManagement != null) {
        _asPropertyManagement = propertyManagement;
      }

      final merged = <String, ChatConversation>{};
      for (final c in [..._asClient, ..._asPropertyManagement]) {
        merged[c.id] = c;
      }
      final sorted = merged.values.toList()
        ..sort((a, b) => b.lastMessageAt.compareTo(a.lastMessageAt));

      _state = sorted.isEmpty ? _ScreenState.empty : _ScreenState.loaded;
      _sortedConversations = sorted;
    });
    // Let the stagger play once on this paint, then subsequent live stream
    // updates (new messages, unread changes) render in place.
    if (_isFirstPaint) {
      Future.delayed(const Duration(milliseconds: 600), () {
        if (mounted) setState(() => _isFirstPaint = false);
      });
    }
  }

  List<ChatConversation> _sortedConversations = [];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // Consistent tab-root AppBar treatment (mark + label) across Home,
        // Chat, Dashboard, Profile -- see TabAppBarTitle.
        title: const TabAppBarTitle('Messages'),
        automaticallyImplyLeading: false, // tab root (core/routing/app_shell.dart)
      ),
      body: BrandedRefreshIndicator(
        onRefresh: _init,
        child: switch (_state) {
          _ScreenState.loading => const _SkeletonList(),
          _ScreenState.error => _ErrorView(
              message: _errorMessage ?? 'Something went wrong.',
              onRetry: _init),
          _ScreenState.empty => const _EmptyView(),
          _ScreenState.offline || _ScreenState.loaded => _buildList(context),
        },
      ),
    );
  }

  Widget _buildList(BuildContext context) {
    return Column(
      children: [
        if (_state == _ScreenState.offline)
          Container(
            width: double.infinity,
            color: Theme.of(context).colorScheme.errorContainer,
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Text(_errorMessage ?? "You're offline.",
                textAlign: TextAlign.center),
          ),
        Expanded(
          child: ListView.builder(
            itemCount: _sortedConversations.length,
            itemBuilder: (context, index) {
              final conversation = _sortedConversations[index];
              final isClient = conversation.clientId == _currentUserId;
              final tile = _ConversationTile(
                conversation: conversation,
                roleLabel: isClient
                    ? 'You are the guest'
                    : 'You are property management',
                chatRepository: widget.chatRepository,
                listingRepository: widget.listingRepository,
                currentUserId: _currentUserId,
                onTap: () => context.pushNamed(
                  RouteNames.chatThread,
                  pathParameters: {'id': conversation.id},
                ),
              );
              // list-stagger only on first load / return-to-tab, not on
              // pull-to-refresh rebuilds (branding.md).
              return _isFirstPaint
                  ? ListStaggerItem(index: index, child: tile)
                  : tile;
            },
          ),
        ),
      ],
    );
  }
}

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({
    required this.conversation,
    required this.roleLabel,
    required this.chatRepository,
    required this.listingRepository,
    required this.currentUserId,
    required this.onTap,
  });

  final ChatConversation conversation;
  final String roleLabel;
  final ChatRepository chatRepository;
  final ListingRepository listingRepository;
  final String? currentUserId;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Live, not a one-time fetch -- see ChatRepository.watchLastMessage's
    // docstring for the real bug this fixes (unread dot/preview text
    // getting stuck stale until an unrelated conversation-list rebuild).
    return StreamBuilder<ChatMessage?>(
      stream: chatRepository.watchLastMessage(conversation.id),
      builder: (context, snapshot) {
        final lastMessage = snapshot.data;
        final isUnread = lastMessage != null &&
            lastMessage.senderId != currentUserId &&
            lastMessage.deliveryStatus != ChatDeliveryStatus.read;
        // badge-pop key: re-triggers the pop whenever the preview text or
        // unread state actually changes, not on every rebuild.
        final badgeTriggerKey = '${lastMessage?.id}-$isUnread';

        return TapScale(
          onTap: onTap,
          child: Card(
            margin: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md, vertical: AppSpacing.xs),
            child: ListTile(
              onTap: onTap,
              leading: CircleAvatar(
                  child: Icon(isUnread
                      ? Icons.mark_chat_unread
                      : Icons.chat_bubble_outline)),
              // Was `Text('Listing ${conversation.listingId}')` -- the raw
              // Firestore listing id, meaningless to a user. Resolved to
              // the actual listing title via a one-off REST fetch, with the
              // id kept only as a fallback (deleted listing, fetch failure).
              title: ListingTitleText(
                listingId: conversation.listingId,
                listingRepository: listingRepository,
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(roleLabel,
                      style: Theme.of(context).textTheme.bodySmall),
                  BadgePop(
                    triggerKey: badgeTriggerKey,
                    child: Text(
                      lastMessage?.body ?? 'No messages yet',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: isUnread
                          ? const TextStyle(fontWeight: FontWeight.bold)
                          : null,
                    ),
                  ),
                ],
              ),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(_formatTimestamp(conversation.lastMessageAt),
                      style: Theme.of(context).textTheme.bodySmall),
                  if (isUnread)
                    BadgePop(
                      triggerKey: badgeTriggerKey,
                      child: Container(
                        margin: const EdgeInsets.only(top: AppSpacing.xs),
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.tertiary,
                            shape: BoxShape.circle),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String _formatTimestamp(DateTime dt) {
    final now = DateTime.now();
    if (now.difference(dt).inHours < 24 && now.day == dt.day) {
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
    return '${dt.month}/${dt.day}';
  }
}

class _SkeletonList extends StatelessWidget {
  const _SkeletonList();

  @override
  Widget build(BuildContext context) {
    return const SkeletonList(count: 6, builder: _buildSkeletonRow);
  }

  static Widget _buildSkeletonRow(BuildContext context, int index) =>
      const SkeletonRow(height: 56);
}

class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    return EmptyStateView(
      title: 'No messages yet',
      message: 'Start a conversation from a listing you are interested in.',
      actionLabel: 'Browse listings',
      onAction: () => context.goNamed(RouteNames.home),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: AppSpacing.md),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.md),
            ElevatedButton(
                onPressed: () => onRetry(), child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
