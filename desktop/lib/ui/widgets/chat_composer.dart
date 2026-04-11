import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_strings.dart';

class ChatComposer extends StatefulWidget {
  final bool enabled;
  final bool isStreaming;
  final String thinkingLevel;
  final ValueChanged<String> onSend;
  final VoidCallback onAbort;
  final ValueChanged<String> onThinkingChanged;

  const ChatComposer({
    super.key,
    required this.enabled,
    required this.isStreaming,
    required this.thinkingLevel,
    required this.onSend,
    required this.onAbort,
    required this.onThinkingChanged,
  });

  @override
  State<ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends State<ChatComposer> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    widget.onSend(text);
    _controller.clear();
    _focusNode.requestFocus();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: colorScheme.outline.withOpacity(0.1)),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Thinking level selector
          Row(
            children: [
              Text(S.current.composerThinking,
                  style: TextStyle(
                      fontSize: 11,
                      color: colorScheme.onSurface.withOpacity(0.5))),
              for (final level in ['off', 'low', 'medium', 'high'])
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: ChoiceChip(
                    label: Text(
                        switch (level) {
                          'off' => S.current.composerOff,
                          'low' => S.current.composerLow,
                          'medium' => S.current.composerMedium,
                          'high' => S.current.composerHigh,
                          _ => level,
                        },
                        style: const TextStyle(fontSize: 11)),
                    selected: widget.thinkingLevel == level,
                    onSelected: widget.enabled
                        ? (_) => widget.onThinkingChanged(level)
                        : null,
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Focus(
                  onKeyEvent: (node, event) {
                    if (event is KeyDownEvent &&
                        event.logicalKey == LogicalKeyboardKey.enter &&
                        !HardwareKeyboard.instance.isShiftPressed &&
                        !HardwareKeyboard.instance.isControlPressed) {
                      _send();
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.ignored;
                  },
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    maxLines: 5,
                    minLines: 1,
                    enabled: widget.enabled,
                    decoration: InputDecoration(
                      hintText: widget.enabled
                          ? S.current.composerHint
                          : S.current.composerConnectHint,
                      hintStyle: TextStyle(
                        color: colorScheme.onSurface.withOpacity(0.3),
                        fontSize: 14,
                      ),
                    ),
                    style: const TextStyle(fontSize: 14),
                    textInputAction: TextInputAction.newline,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (widget.isStreaming)
                IconButton.filled(
                  onPressed: widget.onAbort,
                  icon: const Icon(Icons.stop, size: 20),
                  tooltip: S.current.composerStop,
                  style: IconButton.styleFrom(
                    backgroundColor: colorScheme.error.withOpacity(0.15),
                    foregroundColor: colorScheme.error,
                  ),
                )
              else
                IconButton.filled(
                  onPressed: widget.enabled ? _send : null,
                  icon: const Icon(Icons.send, size: 20),
                  tooltip: S.current.composerSend,
                ),
            ],
          ),
        ],
      ),
    );
  }
}
