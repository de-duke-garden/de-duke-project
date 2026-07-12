/// FEAT-029: General In-App Support / Help. Not a screens.md-numbered
/// mobile screen (only the Admin Web Console side, Screen 26, is
/// documented there) -- reachable from Account Settings' "Help & Support"
/// row. Deliberately mirrors chat_thread_screen.dart's structure (loading/
/// loaded/error states, message list, composer) since it's the same
/// underlying interaction shape, just a two-way (user <-> De-Duke Staff)
/// thread instead of three-way and not tied to a listing.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/theme/app_spacing.dart';
import '../../auth/data/auth_repository.dart';
import '../../chat/data/chat_models.dart';
import '../data/support_repository.dart';

enum _ScreenState { loading, loaded, error }

class SupportScreen extends StatefulWidget {
  const SupportScreen({
    super.key,
    required this.supportRepository,
    required this.authRepository,
  });

  final SupportRepository supportRepository;
  final AuthRepository authRepository;

  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends State<SupportScreen> {
  _ScreenState _state = _ScreenState.loading;
  String? _errorMessage;

  String? _conversationId;
  CurrentUser? _currentUser;
  List<ChatMessage> _messages = [];

  final _draftController = TextEditingController();
  final _scrollController = ScrollController();
  bool _sending = false;

  StreamSubscription<List<ChatMessage>>? _messagesSub;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _messagesSub?.cancel();
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
      await widget.supportRepository.ensureSignedIn();
      final user = await widget.authRepository.getCurrentUser();
      final conversationId =
          await widget.supportRepository.getOrCreateConversation();

      _currentUser = user;
      _conversationId = conversationId;

      _messagesSub?.cancel();
      _messagesSub = widget.supportRepository
          .watchMessages(conversationId)
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

  /// Same rationale as chat_thread_screen.dart's own _onStreamError: a
  /// Firestore stream failure (missing index, rules regression) must
  /// surface here rather than silently stranding the screen on its
  /// loading spinner forever.
  void _onStreamError(Object error, StackTrace stackTrace) {
    if (!mounted) return;
    setState(() {
      _state = _ScreenState.error;
      _errorMessage = 'Something went wrong.';
    });
  }

  Future<void> _send() async {
    final body = _draftController.text.trim();
    if (body.isEmpty || _currentUser == null || _conversationId == null) {
      return;
    }
    setState(() => _sending = true);
    try {
      await widget.supportRepository.sendMessage(
        conversationId: _conversationId!,
        senderId: _currentUser!.userId,
        body: body,
      );
      _draftController.clear();
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Help & Support')),
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
        if (_messages.isEmpty)
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Text(
              "Send a message and De-Duke's team will get back to you.",
              style: Theme.of(context).textTheme.bodySmall,
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
              return _SupportMessageBubble(message: message, isMine: isMine);
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

class _SupportMessageBubble extends StatelessWidget {
  const _SupportMessageBubble({required this.message, required this.isMine});

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
              isStaff ? 'De-Duke Staff' : 'You',
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: textColor.withValues(alpha: 0.8)),
            ),
            Text(message.body, style: TextStyle(color: textColor)),
            const SizedBox(height: AppSpacing.xs),
            Text(
              _formatTime(message.sentAt),
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: textColor.withValues(alpha: 0.7)),
            ),
          ],
        ),
      ),
    );
  }

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
