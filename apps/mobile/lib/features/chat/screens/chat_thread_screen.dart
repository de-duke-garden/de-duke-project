/// screens.md Screen 9: Chat Thread. Real-time three-way support chat
/// (Client, Property Management, De-Duke Staff) for a specific listing --
/// no offer/price composer, per AGENTS.md (pricing is fixed).
library;

import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/route_names.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/badge_pop.dart';
import '../../../core/widgets/skeleton_loader.dart';
import '../../auth/data/auth_repository.dart';
import '../../listings/data/listing_repository.dart';
import '../../reporting/data/report_repository.dart';
import '../../reporting/screens/report_sheet.dart';
import '../data/chat_models.dart';
import '../data/chat_repository.dart';

enum _ScreenState { loading, loaded, error }

/// FEAT-016 (Off-Platform Payment Leakage Mitigation) AC: "Chat surfaces a
/// 'Pay safely in-app' prompt once a client shows booking intent (e.g.,
/// asks about availability/next steps)." Client-side keyword heuristic --
/// no backend ML needed (task brief) -- checked against every incoming/
/// outgoing message body. Deliberately broad (covers both "shows booking
/// intent" language and the classic off-platform-leakage phrases like
/// "cash"/"transfer"/"whatsapp") so the nudge fires whenever either signal
/// appears, per the task brief's example word list.
const List<String> kBookingIntentKeywords = [
  'available',
  'availability',
  'price',
  'book',
  'booking',
  'deposit',
  'cash',
  'transfer',
  'whatsapp',
  'call me',
  'next steps',
];

bool messageShowsBookingIntent(String body) {
  final lower = body.toLowerCase();
  return kBookingIntentKeywords.any(lower.contains);
}

class ChatThreadScreen extends StatefulWidget {
  const ChatThreadScreen({
    super.key,
    required this.conversationId,
    required this.chatRepository,
    required this.authRepository,
    required this.reportRepository,
    required this.listingRepository,
  });

  final String conversationId;
  final ChatRepository chatRepository;
  final AuthRepository authRepository;

  /// FEAT-009 -- backs the overflow menu's "Report conversation" action.
  final ReportRepository reportRepository;

  /// Resolves the conversation's `listingId` to its title for the AppBar
  /// heading -- previously the AppBar just read "Chat" with no indication
  /// of which listing the thread was about.
  final ListingRepository listingRepository;

  @override
  State<ChatThreadScreen> createState() => _ChatThreadScreenState();
}

class _ChatThreadScreenState extends State<ChatThreadScreen> {
  _ScreenState _state = _ScreenState.loading;
  String? _errorMessage;

  ChatConversation? _conversation;
  // Fetched once the conversation resolves its listingId. Left null (AppBar
  // falls back to "Chat") if the fetch fails -- a missing title is not
  // worth blocking or erroring the whole thread screen over.
  String? _listingTitle;
  CurrentUser? _currentUser;
  List<ChatMessage> _messages = [];
  bool _isOffline = false;

  // Tracks which message ids have already been rendered once, so the
  // slide-up+fade entrance (branding.md `duration-fast`) only plays for
  // genuinely new incoming bubbles, not for the initial history load.
  final Set<String> _seenMessageIds = {};
  Set<String> _newlyArrivedIds = {};
  bool _firstMessagesSnapshot = true;

  // FEAT-016 -- "Pay safely in-app" nudge, once shown for this thread,
  // stays dismissible but never re-triggers automatically (avoids
  // re-showing on every subsequent booking-intent-shaped message).
  bool _showPaySafelyNudge = false;
  bool _paySafelyNudgeDismissed = false;

  final _draftController = TextEditingController();
  final _scrollController = ScrollController();
  bool _sending = false;

  StreamSubscription<List<ChatMessage>>? _messagesSub;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  @override
  void initState() {
    super.initState();
    _init();
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      if (!mounted) return;
      setState(() =>
          _isOffline = results.every((r) => r == ConnectivityResult.none));
    });
  }

  @override
  void dispose() {
    _messagesSub?.cancel();
    _connectivitySub?.cancel();
    _draftController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    setState(() {
      _state = _ScreenState.loading;
      _errorMessage = null;
    });
    try {
      await widget.chatRepository.ensureSignedIn();
      final user = await widget.authRepository.getCurrentUser();
      final conversation =
          await widget.chatRepository.getConversation(widget.conversationId);
      if (conversation == null) {
        if (!mounted) return;
        setState(() {
          _state = _ScreenState.error;
          _errorMessage = 'This conversation could not be found.';
        });
        return;
      }

      _currentUser = user;
      _conversation = conversation;

      // Fire-and-forget: doesn't block the message stream subscription
      // below, and a failed/slow title fetch shouldn't hold up the rest of
      // the thread from loading.
      unawaited(
        widget.listingRepository.getListing(conversation.listingId).then(
          (listing) {
            if (!mounted) return;
            setState(() => _listingTitle = listing.title);
          },
          onError: (_) {},
        ),
      );

      _messagesSub?.cancel();
      _messagesSub = widget.chatRepository
          .watchMessages(widget.conversationId)
          .listen((messages) {
        if (!mounted) return;
        setState(() {
          final incomingIds = messages.map((m) => m.id).toSet();
          if (_firstMessagesSnapshot) {
            _newlyArrivedIds = {};
            _firstMessagesSnapshot = false;
          } else {
            _newlyArrivedIds = incomingIds.difference(_seenMessageIds);
          }
          _seenMessageIds.addAll(incomingIds);
          _messages = messages;
          _state = _ScreenState.loaded;
          // FEAT-016 AC: nudge appears "once a client shows booking
          // intent" -- checked across the whole visible history (not just
          // new arrivals) so it also surfaces on a thread reopened after
          // the intent-showing message was sent in a prior session.
          if (!_paySafelyNudgeDismissed &&
              messages.any((m) => messageShowsBookingIntent(m.body))) {
            _showPaySafelyNudge = true;
          }
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController
                .jumpTo(_scrollController.position.maxScrollExtent);
          }
        });
      }, onError: _onStreamError);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _state = _ScreenState.error;
        _errorMessage =
            e is AuthException ? e.message : 'Something went wrong.';
      });
    }
  }

  /// Firestore stream errors (e.g. a missing composite index, a rules
  /// regression, a permission change) surface here rather than through the
  /// `_init()` try/catch above -- without this handler they'd terminate the
  /// subscription silently and strand the screen on its loading spinner
  /// forever with no visible signal to the user or the developer.
  void _onStreamError(Object error, StackTrace stackTrace) {
    if (!mounted) return;
    setState(() {
      _state = _ScreenState.error;
      _errorMessage = 'Something went wrong.';
    });
  }

  Future<void> _send() async {
    final body = _draftController.text.trim();
    if (body.isEmpty || _currentUser == null) return;
    setState(() => _sending = true);
    try {
      await widget.chatRepository.sendMessage(
        conversationId: widget.conversationId,
        senderId: _currentUser!.userId,
        senderRole: _roleForSend(),
        body: body,
      );
      _draftController.clear();
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// Tap-to-retry affordance on a Send Failed bubble (screens.md Screen 9
  /// States) -- resends the same content rather than leaving the user with
  /// no recourse. This screen has no card grid so `tap-scale`/`list-stagger`
  /// don't apply here; this retry tap is the screen's equivalent tactile
  /// feedback point (branding.md Modernization Notes).
  Future<void> _retrySend(ChatMessage message) async {
    if (_currentUser == null) return;
    await widget.chatRepository.sendMessage(
      conversationId: widget.conversationId,
      senderId: message.senderId ?? _currentUser!.userId,
      senderRole: message.senderRole ?? _roleForSend(),
      body: message.body,
    );
  }

  String _roleForSend() {
    final user = _currentUser!;
    final conversation = _conversation!;
    if (user.role == 'deduke_staff' || user.role == 'deduke_admin') {
      return 'deduke_staff';
    }
    return user.userId == conversation.clientId
        ? 'client'
        : 'property_management';
  }

  /// "Report conversation" -- overflow-menu action wired to the
  /// report-a-conversation flow (FEAT-009).
  Future<void> _openReportSheet() async {
    final submitted = await showReportSheet(
      context,
      repository: widget.reportRepository,
      kind: ReportTargetKind.conversation,
      targetId: widget.conversationId,
    );
    if (submitted == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Thanks, we'll review this.")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: _conversation == null
            ? const Text('Chat')
            : GestureDetector(
                onTap: () => context.pushNamed(
                  RouteNames.listingDetail,
                  pathParameters: {'id': _conversation!.listingId},
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Was a static "Chat" -- now shows the listing title
                    // this thread is about, once resolved (falls back to
                    // "Chat" while loading/on fetch failure).
                    Text(
                      _listingTitle ?? 'Chat',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      'Client • Property Management • De-Duke Staff',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
        actions: [
          if (_state == _ScreenState.loaded)
            PopupMenuButton<void>(
              tooltip: 'More options',
              itemBuilder: (context) => [
                PopupMenuItem<void>(
                  onTap: _openReportSheet,
                  child: const Row(
                    children: [
                      Icon(Icons.flag_outlined, size: 20),
                      SizedBox(width: AppSpacing.sm),
                      Text('Report conversation'),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
      body: switch (_state) {
        _ScreenState.loading => const _SkeletonThread(),
        _ScreenState.error => _ErrorView(
            message: _errorMessage ?? 'Something went wrong.', onRetry: _init),
        _ScreenState.loaded => _buildThread(context),
      },
    );
  }

  Widget _buildThread(BuildContext context) {
    return Column(
      children: [
        if (_showPaySafelyNudge && !_paySafelyNudgeDismissed)
          _PaySafelyNudgeBanner(
            onDismiss: () => setState(() => _paySafelyNudgeDismissed = true),
            onGoToListing: _conversation == null
                ? null
                : () => context.pushNamed(
                      RouteNames.listingDetail,
                      pathParameters: {'id': _conversation!.listingId},
                    ),
          ),
        if (_isOffline)
          Container(
            width: double.infinity,
            color: Theme.of(context).colorScheme.errorContainer,
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: const Text(
              "You're offline. Messages will send when you're back online.",
              textAlign: TextAlign.center,
            ),
          ),
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.all(AppSpacing.md),
            itemCount: _messages.length,
            itemBuilder: (context, index) {
              final message = _messages[index];
              if (message.isSystemMessage) {
                final isStaffJoined = message.body.toLowerCase().contains('staff');
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  child: Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isStaffJoined)
                          Padding(
                            padding:
                                const EdgeInsets.only(right: AppSpacing.xs),
                            child: BadgePop(
                              triggerKey: message.id,
                              child: Icon(Icons.support_agent,
                                  size: 16,
                                  color: Theme.of(context).colorScheme.primary),
                            ),
                          ),
                        Text(
                          message.body,
                          style: AppTypography.bodySmall.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                );
              }
              final isMine = message.senderId == _currentUser?.userId;
              final bubble = _MessageBubble(
                message: message,
                isMine: isMine,
                onRetry: message.deliveryStatus == ChatDeliveryStatus.failed
                    ? () => _retrySend(message)
                    : null,
              );
              // Quick slide-up + fade (duration-fast) for genuinely new
              // incoming bubbles only -- history loads in place.
              return _newlyArrivedIds.contains(message.id)
                  ? _BubbleEntrance(key: ValueKey(message.id), child: bubble)
                  : bubble;
            },
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _draftController,
                    decoration: const InputDecoration(hintText: 'Message...'),
                    minLines: 1,
                    maxLines: 4,
                    enabled: !_sending,
                  ),
                ),
                IconButton(
                  onPressed: _sending ? null : _send,
                  icon: const Icon(Icons.send),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// branding.md `duration-fast` (200ms) slide-up + fade entrance for a
/// genuinely new incoming bubble.
class _BubbleEntrance extends StatefulWidget {
  const _BubbleEntrance({super.key, required this.child});

  final Widget child;

  @override
  State<_BubbleEntrance> createState() => _BubbleEntranceState();
}

class _BubbleEntranceState extends State<_BubbleEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppDurations.fast,
  )..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curved =
        CurvedAnimation(parent: _controller, curve: AppCurves.easeOutSmooth);
    return AnimatedBuilder(
      animation: curved,
      builder: (context, child) => Opacity(
        opacity: curved.value.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(0, 10 * (1 - curved.value)),
          child: child,
        ),
      ),
      child: widget.child,
    );
  }
}

/// Skeleton bubbles replacing the bare spinner while message history loads
/// (branding.md Loading States / screens.md Screen 9 Loading state) --
/// matches bubble shape/radius and alternates alignment like real messages.
class _SkeletonThread extends StatelessWidget {
  const _SkeletonThread();

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(AppSpacing.md),
      itemCount: 8,
      itemBuilder: (context, index) =>
          SkeletonChatBubble(outgoing: index.isOdd),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.isMine,
    this.onRetry,
  });

  final ChatMessage message;
  final bool isMine;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isStaff = message.senderRole == 'deduke_staff';
    // Chat Bubble component tokens (branding.md): outgoing uses `primary`
    // background/white text with a squared tail corner; incoming uses
    // `surface-secondary`. De-Duke Staff messages get a distinct tint so
    // all three participant roles stay visually distinguishable (Layout).
    final bubbleColor = isStaff
        ? colorScheme.tertiaryContainer
        : (isMine ? colorScheme.primary : colorScheme.surfaceContainerHighest);
    final textColor =
        isMine && !isStaff ? colorScheme.onPrimary : colorScheme.onSurface;
    final isFailed = message.deliveryStatus == ChatDeliveryStatus.failed;

    // `radius-md` on 3 corners, sharp (squared) tail corner -- bottom-right
    // for outgoing (right-aligned), bottom-left for incoming.
    final radius = BorderRadius.only(
      topLeft: const Radius.circular(AppRadii.md),
      topRight: const Radius.circular(AppRadii.md),
      bottomLeft: Radius.circular(isMine ? AppRadii.md : 0),
      bottomRight: Radius.circular(isMine ? 0 : AppRadii.md),
    );

    final bubble = Container(
      margin: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      padding: const EdgeInsets.all(AppSpacing.sm),
      constraints:
          BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
      decoration: BoxDecoration(
        color: bubbleColor,
        borderRadius: radius,
        border: isFailed ? Border.all(color: colorScheme.error) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _roleLabel(message.senderRole),
            style: AppTypography.caption
                .copyWith(color: textColor.withValues(alpha: 0.8)),
          ),
          Text(message.body, style: TextStyle(color: textColor)),
          const SizedBox(height: AppSpacing.xs),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _formatTime(message.sentAt),
                style: AppTypography.bodySmall
                    .copyWith(color: textColor.withValues(alpha: 0.7)),
              ),
              const SizedBox(width: AppSpacing.xs),
              Icon(_statusIcon(),
                  size: 12,
                  color: isFailed
                      ? colorScheme.error
                      : textColor.withValues(alpha: 0.7)),
              if (isFailed) ...[
                const SizedBox(width: AppSpacing.xs),
                Text('Tap to retry',
                    style: AppTypography.bodySmall
                        .copyWith(color: colorScheme.error)),
              ],
            ],
          ),
        ],
      ),
    );

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: isFailed && onRetry != null
          ? GestureDetector(onTap: onRetry, child: bubble)
          : bubble,
    );
  }

  IconData _statusIcon() {
    if (message.pendingWrite ||
        message.deliveryStatus == ChatDeliveryStatus.sending) {
      return Icons.access_time;
    }
    if (message.deliveryStatus == ChatDeliveryStatus.failed) {
      return Icons.error_outline;
    }
    if (message.deliveryStatus == ChatDeliveryStatus.read) {
      return Icons.done_all;
    }
    return Icons.done;
  }

  String _roleLabel(String? role) => switch (role) {
        'client' => 'Client',
        'property_management' => 'Property Management',
        'deduke_staff' => 'De-Duke Staff',
        _ => 'Unknown',
      };

  String _formatTime(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
}

/// FEAT-016 AC: "Pay safely in-app" prompt once booking intent is
/// detected, plus the "buyer protection/guarantee not available
/// off-platform" messaging (also an AC). Icon+text (never color alone,
/// AGENTS.md accessibility) and a dismiss control at least
/// AppSizing.minTouchTarget so it's tappable without being intrusive.
class _PaySafelyNudgeBanner extends StatelessWidget {
  const _PaySafelyNudgeBanner({required this.onDismiss, this.onGoToListing});

  final VoidCallback onDismiss;
  final VoidCallback? onGoToListing;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: colorScheme.primaryContainer,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          Icon(Icons.shield_outlined, color: colorScheme.onPrimaryContainer),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Pay safely in-app',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 2),
                Text(
                  'Payments made in the app are protected by De-Duke\'s '
                  'buyer guarantee -- off-platform payments are not.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (onGoToListing != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  SizedBox(
                    height: 48,
                    child: TextButton(
                      onPressed: onGoToListing,
                      child: const Text('Book Now'),
                    ),
                  ),
                ],
              ],
            ),
          ),
          SizedBox(
            width: 48,
            height: 48,
            child: IconButton(
              onPressed: onDismiss,
              icon: const Icon(Icons.close, size: 20),
              tooltip: 'Dismiss',
            ),
          ),
        ],
      ),
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
