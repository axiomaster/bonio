import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:window_manager/window_manager.dart';

import '../../models/agent_avatar_models.dart';
import '../../models/avatar_snapshot.dart';
import '../../services/avatar_controller.dart';
import '../../services/desktop_avatar_theme.dart';

/// A text widget that auto-scrolls to the bottom when content exceeds
/// [maxLines], creating a teleprompter effect for streaming assistant replies.
class _AutoScrollText extends StatefulWidget {
  final String text;
  final TextStyle style;
  final int maxLines;

  const _AutoScrollText({
    required this.text,
    required this.style,
    required this.maxLines,
  });

  @override
  State<_AutoScrollText> createState() => _AutoScrollTextState();
}

class _AutoScrollTextState extends State<_AutoScrollText> {
  final ScrollController _scrollController = ScrollController();

  @override
  void didUpdateWidget(_AutoScrollText old) {
    super.didUpdateWidget(old);
    if (widget.text != old.text) {
      _scrollToEnd();
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final max = _scrollController.position.maxScrollExtent;
      if (max <= 0) return;
      _scrollController.animateTo(
        max,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      controller: _scrollController,
      physics: const ClampingScrollPhysics(),
      child: Text(widget.text, style: widget.style),
    );
  }
}

/// Renders avatar from a snapshot (used by the OS-level floating window).
class DesktopAvatarView extends StatefulWidget {
  final AvatarSnapshot snapshot;

  /// For non-floating (in-app overlay) usage: delta-based drag callback.
  final void Function(Offset delta)? onPanUpdate;
  final VoidCallback? onAvatarTap;

  /// When true (separate avatar engine): cat is centered; drag uses native
  /// [windowManager.startDragging] so the OS moves the window flicker-free.
  final bool isFloatingWindow;

  const DesktopAvatarView({
    super.key,
    required this.snapshot,
    this.onPanUpdate,
    this.onAvatarTap,
    this.isFloatingWindow = false,
  });

  @override
  State<DesktopAvatarView> createState() => _DesktopAvatarViewState();
}

class _DesktopAvatarViewState extends State<DesktopAvatarView> {
  DesktopAvatarTheme? _theme;

  @override
  void initState() {
    super.initState();
    DesktopAvatarTheme.load().then((t) {
      if (mounted) setState(() => _theme = t);
    });
  }

  @override
  Widget build(BuildContext context) {
    final bubble = _bubbleContent(context, widget.snapshot);
    final pos = Offset(widget.snapshot.posX, widget.snapshot.posY);
    final tint = widget.snapshot.colorFilter;
    final primary = Theme.of(context).colorScheme.primary;
    final g = widget.snapshot.gestureEnum;

    final asset = _theme?.lottieAssetFor(widget.snapshot) ??
        DesktopAvatarTheme.fallbackLottieAsset;

    final visual = AvatarController.avatarVisualSize;
    // Single layout path: explicit width/height + BoxFit.contain (no nested FittedBox).
    // Floating window: skip RepaintBoundary and Lottie's extra boundary — fewer
    // layers when moving a transparent HWND (reduces ghosting).
    final lottie = Lottie.asset(
      asset,
      key: ValueKey(asset),
      width: visual,
      height: visual,
      fit: BoxFit.contain,
      repeat: true,
      addRepaintBoundary: !widget.isFloatingWindow,
      errorBuilder: (_, __, ___) => _fallbackAvatar(context, tint, primary),
    );

    final avatarCore = widget.isFloatingWindow
        ? SizedBox(width: visual, height: visual, child: lottie)
        : RepaintBoundary(
            child: SizedBox(width: visual, height: visual, child: lottie),
          );

    final avatarStack = Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        avatarCore,
        if (g != DesktopAvatarGesture.none)
          Positioned(
            bottom: -2,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 6,
                vertical: 2,
              ),
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .surfaceContainerHighest,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                gestureLabel(g),
                style: TextStyle(
                  fontSize: 9,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurfaceVariant,
                ),
              ),
            ),
          ),
      ],
    );

    // For the floating window, tap and drag are handled on the avatarStack
    // only; the bubble above is not interactive.
    // For the in-app overlay, the GestureDetector wraps the whole Column.
    final interactiveAvatar = widget.isFloatingWindow
        ? GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onAvatarTap,
            onPanStart: (_) => windowManager.startDragging(),
            child: avatarStack,
          )
        : GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onAvatarTap,
            onPanUpdate: widget.onPanUpdate != null
                ? (d) => widget.onPanUpdate!(d.delta)
                : null,
            child: avatarStack,
          );

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (bubble != null) ...[
          bubble,
          const SizedBox(height: 6),
        ],
        interactiveAvatar,
        if (!widget.isFloatingWindow) ...[
          const SizedBox(height: 2),
          Text(
            activityLabel(widget.snapshot.effectiveActivityEnum),
            style: TextStyle(
              fontSize: 10,
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withOpacity(0.55),
            ),
          ),
          if (widget.snapshot.isMoving)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
        ],
      ],
    );

    // Floating avatar: anchor at the bottom-center so the bubble grows upward
    // from the cat.  Avoid Material (extra composited layer on transparent HWND).
    if (widget.isFloatingWindow) {
      return Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: const EdgeInsets.only(bottom: AvatarSnapshot.kFloatingWindowPadding),
          child: content,
        ),
      );
    }

    return Material(
      color: Colors.transparent,
      child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: pos.dx,
                  top: pos.dy,
                  child: content,
                ),
              ],
            ),
    );
  }


  Widget _fallbackAvatar(BuildContext context, Color? tint, Color primary) {
    return Container(
      width: AvatarController.avatarVisualSize,
      height: AvatarController.avatarVisualSize,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Icon(
        Icons.pets,
        size: 40,
        color: tint ?? primary,
      ),
    );
  }

  Widget? _bubbleContent(BuildContext context, AvatarSnapshot c) {
    final text = c.bubbleText;
    final countdown = c.bubbleCountdown;
    if (text == null && (countdown == null || countdown.isEmpty)) {
      return null;
    }
    final bg = c.bubbleBgArgb != null ? Color(c.bubbleBgArgb!) : null;
    final fg = c.bubbleTextArgb != null ? Color(c.bubbleTextArgb!) : null;

    final body = StringBuffer();
    if (text != null) body.write(text);
    if (countdown != null && countdown.isNotEmpty) {
      if (body.isNotEmpty) body.write('\n');
      body.write(countdown);
    }

    final style = TextStyle(
      fontSize: 12,
      height: 1.35,
      color: fg ?? Theme.of(context).colorScheme.onSurfaceVariant,
    );
    // 3 lines max: fontSize * lineHeight * 3 + vertical padding
    const maxLines = 3;
    final maxBubbleHeight = style.fontSize! * style.height! * maxLines + 16;

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: 220, maxHeight: maxBubbleHeight),
      child: Material(
        elevation: 3,
        borderRadius: BorderRadius.circular(12),
        color: bg ?? Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: _AutoScrollText(
            text: body.toString(),
            style: style,
            maxLines: maxLines,
          ),
        ),
      ),
    );
  }
}
