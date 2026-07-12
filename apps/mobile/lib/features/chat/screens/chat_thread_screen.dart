/// screens.md Screen 9: Chat Thread. Real-time three-way support chat
/// (Client, Property Management, De-Duke Staff) for a specific listing --
/// no offer/price composer, per AGENTS.md (pricing is fixed).
library;

import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/route_names.dart';
import '../../../core/theme/app_spacing.dart';
import '../../auth/data/auth_repository.dart';
import '../data/chat_models.dart';
import '../data/chat_repository.dart';

enum _ScreenState { loading, loaded, error }

class ChatThreadScreen extends StatefulWidget {
  const ChatThreadScreen({
    super.key,
    required this.conversationId,
    required this.chatRepository,
    required this.authRepository,
  });

  final String conversationId;
  final ChatRepository chatRepository;
  final AuthRepository authRepository;

  @override
  State<ChatThreadScreen> createState() => _ChatThreadScreenState();
}

class _ChatThreadScreenState extends State<ChatThreadScreen> {
  _ScreenState _state = _ScreenState.loading;
  String? _errorMessage;

  ChatConversation? _conversation;
  CurrentUser? _currentUser;
  List<ChatMessage> _messages = [];
  bool _isOffline = false;

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

      _messagesSub?.cancel();
      _messagesSub = widget.chatRepository
          .watchMessages(widget.conversationId)
          .listen((messages) {
        if (!mounted) return;
        setState(() {
          _messages = messages;
          _state = _ScreenState.loaded;
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
                    const Text('Chat'),
                    Text(
                      'Client • Property Management • De-Duke Staff',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
      ),
      body: switch (_state) {
        _ScreenState.loading =>
          const Center(child: CircularProgressIndicator()),
        _ScreenState.error => _ErrorView(
            message: _errorMessage ?? 'Something went wrong.', onRetry: _init),
        _ScreenState.loaded => _buildThread(context),
      },
    );
  }

  Widget _buildThread(BuildContext context) {
    return Column(
      children: [
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
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  child: Center(
                    child: Text(
                      message.body,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                );
              }
              final isMine = message.senderId == _currentUser?.userId;
              return _MessageBubble(message: message, isMine: isMine);
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

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message, required this.isMine});

  final ChatMessage message;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    final isStaff = message.senderRole == 'deduke_staff';
    final colorScheme = Theme.of(context).colorScheme;
    final bubbleColor = isStaff
        ? colorScheme.tertiaryContainer
        : (isMine ? colorScheme.primary : colorScheme.surfaceContainerHighest);
    final textColor = isMine && !isStaff ? Colors.white : colorScheme.onSurface;

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        padding: const EdgeInsets.all(AppSpacing.sm),
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        decoration: BoxDecoration(
            color: bubbleColor, borderRadius: BorderRadius.circular(12)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _roleLabel(message.senderRole),
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: textColor.withValues(alpha: 0.8)),
            ),
            Text(message.body, style: TextStyle(color: textColor)),
            const SizedBox(height: AppSpacing.xs),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _formatTime(message.sentAt),
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: textColor.withValues(alpha: 0.7)),
                ),
                const SizedBox(width: AppSpacing.xs),
                Icon(_statusIcon(),
                    size: 12, color: textColor.withValues(alpha: 0.7)),
              ],
            ),
          ],
        ),
      ),
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
