import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:provider/provider.dart';
import '../../l10n/app_strings.dart';
import '../../models/chat_models.dart';
import '../../providers/app_state.dart';
import '../widgets/chat_composer.dart';

class ChatTab extends StatelessWidget {
  const ChatTab({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final runtime = appState.runtime;
    final chat = runtime.chatController;
    final isConnected = runtime.isConnected;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      children: [
        // Top bar with session selector
        _ChatTopBar(
          isConnected: isConnected,
          sessions: chat.sessions,
          currentSessionKey: chat.sessionKey,
          onSessionSelected: (key) => chat.switchSession(key),
          onRefresh: () => chat.refresh(),
          onNewSession: () => chat.switchSession('main'),
        ),

        // Error rail
        if (chat.errorText != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: colorScheme.error.withOpacity(0.1),
            child: Row(
              children: [
                Icon(Icons.error_outline,
                    size: 16, color: colorScheme.error),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    chat.errorText!,
                    style: TextStyle(
                        fontSize: 13, color: colorScheme.error),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 16),
                  onPressed: () {
                    // Clear error by refreshing
                    chat.refresh();
                  },
                ),
              ],
            ),
          ),

        // Pending tool calls
        if (chat.pendingToolCalls.isNotEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            color: colorScheme.primary.withOpacity(0.08),
            child: Wrap(
              spacing: 8,
              children: chat.pendingToolCalls
                  .map((tc) => Chip(
                        avatar: SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: colorScheme.primary,
                          ),
                        ),
                        label: Text(tc.name, style: const TextStyle(fontSize: 12)),
                        visualDensity: VisualDensity.compact,
                      ))
                  .toList(),
            ),
          ),

        // Messages
        Expanded(
          child: !isConnected
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.cloud_off,
                          size: 48,
                          color: colorScheme.onSurface.withOpacity(0.3)),
                      const SizedBox(height: 12),
                      Text(
                        S.current.chatConnectToStart,
                        style: TextStyle(
                          color: colorScheme.onSurface.withOpacity(0.5),
                        ),
                      ),
                    ],
                  ),
                )
              : _ChatMessageList(
                  messages: chat.messages,
                  streamingText: chat.streamingAssistantText,
                  isStreaming: chat.isStreaming,
                ),
        ),

        // Composer
        ChatComposer(
          enabled: isConnected && chat.healthOk,
          isStreaming: chat.isStreaming,
          thinkingLevel: chat.thinkingLevel,
          onSend: (text) => chat.sendMessage(text),
          onAbort: () => chat.abort(),
          onThinkingChanged: (level) => chat.setThinkingLevel(level),
        ),
      ],
    );
  }
}

class _ChatTopBar extends StatelessWidget {
  final bool isConnected;
  final List<ChatSessionEntry> sessions;
  final String currentSessionKey;
  final ValueChanged<String> onSessionSelected;
  final VoidCallback onRefresh;
  final VoidCallback onNewSession;

  const _ChatTopBar({
    required this.isConnected,
    required this.sessions,
    required this.currentSessionKey,
    required this.onSessionSelected,
    required this.onRefresh,
    required this.onNewSession,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: colorScheme.outline.withOpacity(0.1),
          ),
        ),
      ),
      child: Row(
        children: [
          if (sessions.isNotEmpty) ...[
            Expanded(
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: sessions.take(10).map((s) {
                  final isSelected = s.key == currentSessionKey;
                  final label = s.displayName ?? s.key;
                  return Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: ChoiceChip(
                      label: Text(
                        label,
                        style: const TextStyle(fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                      selected: isSelected,
                      onSelected: (_) => onSessionSelected(s.key),
                      visualDensity: VisualDensity.compact,
                    ),
                  );
                }).toList(),
              ),
            ),
          ] else ...[
            Expanded(
              child: Text(
                isConnected ? S.current.tabChat : S.current.chatDisconnected,
                style: theme.textTheme.titleSmall,
              ),
            ),
          ],
          IconButton(
            icon: const Icon(Icons.add, size: 18),
            tooltip: S.current.chatNewSession,
            onPressed: isConnected ? onNewSession : null,
          ),
          IconButton(
            icon: const Icon(Icons.refresh, size: 18),
            tooltip: S.current.chatRefresh,
            onPressed: isConnected ? onRefresh : null,
          ),
        ],
      ),
    );
  }
}

class _ChatMessageList extends StatefulWidget {
  final List<ChatMessage> messages;
  final String? streamingText;
  final bool isStreaming;

  const _ChatMessageList({
    required this.messages,
    this.streamingText,
    required this.isStreaming,
  });

  @override
  State<_ChatMessageList> createState() => _ChatMessageListState();
}

class _ChatMessageListState extends State<_ChatMessageList> {
  final ScrollController _scrollController = ScrollController();
  bool _stickToBottom = true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScrollChanged);
  }

  void _onScrollChanged() {
    if (_scrollController.hasClients) {
      // reverse list: offset 0 = bottom (newest). User scrolled up ⟹ offset > 0.
      _stickToBottom = _scrollController.offset <= 50;
    }
  }

  @override
  void didUpdateWidget(_ChatMessageList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_stickToBottom) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollController.hasClients) return;
        if (_scrollController.offset > 0.1) {
          _scrollController.animateTo(
            0,
            duration: const Duration(milliseconds: 100),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final allItems = <_MessageItem>[
      ...widget.messages.map((m) => _MessageItem(message: m)),
      if (widget.streamingText != null && widget.streamingText!.isNotEmpty)
        _MessageItem(
          message: ChatMessage(
            id: '__streaming__',
            role: 'assistant',
            content: [
              ChatMessageContent(type: 'text', text: widget.streamingText),
            ],
          ),
          isStreaming: true,
        ),
    ];

    if (allItems.isEmpty) {
      return Center(
        child: Text(
          S.current.chatSendToStart,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
          ),
        ),
      );
    }

    // reverse: true makes offset 0 = bottom (newest messages).
    // Items are rendered bottom-to-top, so we reverse the list.
    final reversed = allItems.reversed.toList();

    return ListView.builder(
      controller: _scrollController,
      reverse: true,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      itemCount: reversed.length,
      itemBuilder: (context, index) {
        final item = reversed[index];
        return _MessageBubble(
          message: item.message,
          isStreaming: item.isStreaming,
        );
      },
    );
  }
}

class _MessageItem {
  final ChatMessage message;
  final bool isStreaming;
  const _MessageItem({required this.message, this.isStreaming = false});
}

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isStreaming;

  const _MessageBubble({required this.message, this.isStreaming = false});

  List<ChatMessageContent> get _imageContents =>
      message.content.where((c) =>
          c.type == 'image' && c.base64 != null && c.base64!.isNotEmpty).toList();

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == 'user';
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final text = message.textContent;
    final images = _imageContents;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isUser) ...[
            CircleAvatar(
              radius: 16,
              backgroundColor: colorScheme.primary.withOpacity(0.15),
              child: Icon(Icons.smart_toy,
                  size: 18, color: colorScheme.primary),
            ),
            const SizedBox(width: 10),
          ],
          Flexible(
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.65,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isUser
                    ? colorScheme.primary.withOpacity(0.12)
                    : colorScheme.surfaceContainerHighest.withOpacity(0.5),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isUser ? 16 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 16),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Image thumbnails
                  if (images.isNotEmpty) ...[
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: images.map((img) =>
                        _ImageThumbnail(content: img)).toList(),
                    ),
                    if (text.isNotEmpty) const SizedBox(height: 8),
                  ],
                  if (text.isNotEmpty) ...[
                    if (isUser)
                      SelectableText(
                        text,
                        style: TextStyle(
                          color: colorScheme.onSurface,
                          fontSize: 14,
                          height: 1.5,
                        ),
                      )
                    else
                      MarkdownBody(
                        data: text,
                        selectable: true,
                        styleSheet: MarkdownStyleSheet(
                          p: TextStyle(
                            color: colorScheme.onSurface,
                            fontSize: 14,
                            height: 1.5,
                          ),
                          code: TextStyle(
                            fontFamily: 'Consolas',
                            fontSize: 13,
                            color: colorScheme.onSurface,
                            backgroundColor:
                                colorScheme.surface.withOpacity(0.6),
                          ),
                          codeblockDecoration: BoxDecoration(
                            color: const Color(0xFF1E1E2E),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          codeblockPadding: const EdgeInsets.all(12),
                        ),
                      ),
                  ],
                  if (isStreaming)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colorScheme.primary,
                        ),
                      ),
                    ),
                  if (!isUser && !isStreaming)
                    Align(
                      alignment: Alignment.centerRight,
                      child: IconButton(
                        icon: Icon(Icons.copy,
                            size: 14,
                            color: colorScheme.onSurface.withOpacity(0.3)),
                        tooltip: S.current.chatCopy,
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: text));
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(S.current.chatCopied),
                              duration: const Duration(seconds: 1),
                            ),
                          );
                        },
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                            minWidth: 24, minHeight: 24),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (isUser) ...[
            const SizedBox(width: 10),
            CircleAvatar(
              radius: 16,
              backgroundColor: colorScheme.tertiary.withOpacity(0.15),
              child: Icon(Icons.person,
                  size: 18, color: colorScheme.tertiary),
            ),
          ],
        ],
      ),
    );
  }
}

/// Thumbnail widget for an image attachment in a chat message.
/// Click to open a full-size preview dialog.
class _ImageThumbnail extends StatelessWidget {
  final ChatMessageContent content;

  const _ImageThumbnail({required this.content});

  @override
  Widget build(BuildContext context) {
    final b64 = content.base64;
    if (b64 == null || b64.isEmpty) return const SizedBox.shrink();

    final bytes = base64Decode(b64);
    final colorScheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: () => _showFullImage(context, bytes, content.fileName),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: 240,
                maxHeight: 160,
              ),
              child: Image.memory(
                bytes,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  width: 120,
                  height: 80,
                  color: colorScheme.surfaceContainerHighest,
                  child: Icon(Icons.broken_image,
                      color: colorScheme.onSurface.withOpacity(0.4)),
                ),
              ),
            ),
            Positioned(
              right: 4,
              bottom: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.zoom_in, size: 12, color: Colors.white70),
                    if (content.fileName != null) ...[
                      const SizedBox(width: 4),
                      Text(
                        content.fileName!,
                        style: const TextStyle(
                            fontSize: 10, color: Colors.white70),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showFullImage(BuildContext context, Uint8List bytes, String? fileName) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(24),
        child: Stack(
          children: [
            Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: InteractiveViewer(
                  minScale: 0.5,
                  maxScale: 4.0,
                  child: Image.memory(bytes, fit: BoxFit.contain),
                ),
              ),
            ),
            Positioned(
              top: 0,
              right: 0,
              child: Material(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(20),
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.of(ctx).pop(),
                ),
              ),
            ),
            if (fileName != null)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      fileName,
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 12),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
