import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lottie/lottie.dart';
import 'package:window_manager/window_manager.dart';

import '../../models/agent_avatar_models.dart';
import '../../models/avatar_snapshot.dart';
import '../../models/chat_models.dart';
import '../../platform/win32_screen_capture.dart';
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

  /// Long-press to start/stop voice input.
  final VoidCallback? onVoiceStart;
  final VoidCallback? onVoiceStop;

  /// Single left click: random animation + emotion bubble.
  final VoidCallback? onAvatarClick;

  /// Double left click: toggle text input.
  final VoidCallback? onAvatarDoubleClick;

  /// Right click: show native context menu (Win32 TrackPopupMenu).
  final VoidCallback? onShowNativeMenu;

  /// Text submitted from the input field (double-click to show).
  final void Function(String text, {List<OutgoingAttachment> attachments})?
      onTextSubmit;

  /// Called when the input field should be dismissed (Esc, focus loss).
  final VoidCallback? onInputDismiss;

  /// Programmatically add attachments (e.g. from BoJi Lens capture).
  final List<OutgoingAttachment>? initialAttachments;

  /// Programmatically set initial text (e.g. lens prompt).
  final String? initialText;

  /// Pre-loaded theme from the parent (avoids async re-load on widget recreation).
  final DesktopAvatarTheme? preloadedTheme;

  /// When true (separate avatar engine): cat is centered; drag uses native
  /// [windowManager.startDragging] so the OS moves the window flicker-free.
  final bool isFloatingWindow;

  /// Flip the cat horizontally so it faces left (e.g. walking leftward).
  final bool facingLeft;

  const DesktopAvatarView({
    super.key,
    required this.snapshot,
    this.onPanUpdate,
    this.onVoiceStart,
    this.onVoiceStop,
    this.onAvatarClick,
    this.onAvatarDoubleClick,
    this.onShowNativeMenu,
    this.onTextSubmit,
    this.onInputDismiss,
    this.initialAttachments,
    this.initialText,
    this.preloadedTheme,
    this.isFloatingWindow = false,
    this.facingLeft = false,
  });

  @override
  State<DesktopAvatarView> createState() => _DesktopAvatarViewState();
}

class _DesktopAvatarViewState extends State<DesktopAvatarView> {
  DesktopAvatarTheme? _theme;

  // Pointer state machine for floating window:
  //   PointerDown (left)
  //     ├─ move > 2px before 300ms → DRAG
  //     ├─ 300ms fires (no move) → VOICE start
  //     └─ PointerUp < 300ms → CLICK_PENDING
  //          ├─ 2nd PointerDown within 400ms → DOUBLE_CLICK
  //          └─ 400ms timeout → SINGLE_CLICK
  //   PointerDown (right) → RIGHT_CLICK immediately
  Timer? _longPressTimer;
  Timer? _clickTimer;
  bool _voiceActive = false;
  bool _clickPending = false;
  static const _longPressDuration = Duration(milliseconds: 300);
  static const _doubleClickWindow = Duration(milliseconds: 400);

  final TextEditingController _inputController = TextEditingController();
  final FocusNode _inputFocusNode = FocusNode();

  final List<OutgoingAttachment> _attachments = [];

  @override
  void initState() {
    super.initState();
    _initTheme();
    // Process initial data (e.g. from BoJi Lens) — only runs when the
    // widget is first created (LensAnnotationOverlay → DesktopAvatarView).
    final incoming = widget.initialAttachments;
    if (incoming != null && incoming.isNotEmpty) {
      _attachments.addAll(incoming);
    }
    final incomingText = widget.initialText;
    if (incomingText != null && incomingText.isNotEmpty) {
      _inputController.text = incomingText;
      _inputController.selection = TextSelection.fromPosition(
        TextPosition(offset: incomingText.length),
      );
    }
  }

  void _initTheme() {
    if (widget.preloadedTheme != null) {
      _theme = widget.preloadedTheme;
    }
    if (_theme == null) {
      DesktopAvatarTheme.load().then((t) {
        debugPrint('AvatarView: theme loaded (${t.toString()})');
        if (mounted) setState(() => _theme = t);
      }).catchError((e) {
        debugPrint('AvatarView: theme load FAILED: $e');
      });
    }
  }

  @override
  void didUpdateWidget(DesktopAvatarView old) {
    super.didUpdateWidget(old);
    // Pick up preloaded theme from parent once it becomes available
    if (_theme == null && widget.preloadedTheme != null) {
      _theme = widget.preloadedTheme;
    }
    final incoming = widget.initialAttachments;
    if (incoming != null && incoming.isNotEmpty && incoming != old.initialAttachments) {
      setState(() {
        _attachments.addAll(incoming);
      });
    }
    final incomingText = widget.initialText;
    if (incomingText != null && incomingText.isNotEmpty &&
        incomingText != old.initialText) {
      _inputController.text = incomingText;
      _inputController.selection = TextSelection.fromPosition(
        TextPosition(offset: incomingText.length),
      );
    }
  }

  @override
  void dispose() {
    _longPressTimer?.cancel();
    _clickTimer?.cancel();
    _inputFocusNode.removeListener(_onInputFocusChange);
    _inputController.dispose();
    _inputFocusNode.dispose();
    super.dispose();
  }

  void _onPointerDown(PointerDownEvent event) {
    // Right-click → native context menu
    if (event.buttons & 0x02 != 0) {
      _cancelAllTimers();
      widget.onShowNativeMenu?.call();
      return;
    }

    // Left button
    if (_clickPending) {
      // Second click within double-click window
      _cancelAllTimers();
      _clickPending = false;
      widget.onAvatarDoubleClick?.call();
      return;
    }

    _longPressTimer?.cancel();
    _longPressTimer = Timer(_longPressDuration, () {
      _voiceActive = true;
      widget.onVoiceStart?.call();
    });
  }

  void _onPointerUp(PointerUpEvent _) {
    if (_voiceActive) {
      _voiceActive = false;
      _longPressTimer?.cancel();
      _longPressTimer = null;
      widget.onVoiceStop?.call();
      return;
    }

    if (_longPressTimer?.isActive ?? false) {
      // Released before long-press threshold → potential click
      _longPressTimer?.cancel();
      _longPressTimer = null;
      _clickPending = true;
      _clickTimer?.cancel();
      _clickTimer = Timer(_doubleClickWindow, () {
        _clickPending = false;
        widget.onAvatarClick?.call();
      });
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (_voiceActive) return;
    final moved = event.delta.distance;
    if (moved > 2 && _longPressTimer != null && (_longPressTimer!.isActive)) {
      _cancelAllTimers();
      windowManager.startDragging();
    }
  }

  void _onPointerCancel(PointerCancelEvent _) {
    _cancelAllTimers();
    if (_voiceActive) {
      _voiceActive = false;
      widget.onVoiceStop?.call();
    }
  }

  void _cancelAllTimers() {
    _longPressTimer?.cancel();
    _longPressTimer = null;
    _clickTimer?.cancel();
    _clickTimer = null;
    _clickPending = false;
  }

  @override
  Widget build(BuildContext context) {
    final bubble = _bubbleContent(context, widget.snapshot);
    final pos = Offset(widget.snapshot.posX, widget.snapshot.posY);
    final tint = widget.snapshot.colorFilter;
    final primary = Theme.of(context).colorScheme.primary;
    final g = widget.snapshot.gestureEnum;

    // Use local theme, parent's preloaded theme, or fallback — in that order
    final effectiveTheme = _theme ?? widget.preloadedTheme;
    final asset = effectiveTheme?.lottieAssetFor(widget.snapshot) ??
        DesktopAvatarTheme.fallbackLottieAsset;

    final visual = AvatarController.avatarVisualSize;
    final noBoundary = widget.isFloatingWindow;
    final lottie = Lottie.asset(
      asset,
      key: ValueKey(asset),
      width: visual,
      height: visual,
      fit: BoxFit.contain,
      repeat: true,
      addRepaintBoundary: !noBoundary,
      errorBuilder: (_, error, ___) {
        debugPrint('AvatarView: Lottie error for "$asset": $error');
        // Try the idle animation before showing the static fallback
        if (asset != DesktopAvatarTheme.fallbackLottieAsset) {
          return Lottie.asset(
            DesktopAvatarTheme.fallbackLottieAsset,
            width: visual,
            height: visual,
            fit: BoxFit.contain,
            repeat: true,
            addRepaintBoundary: !noBoundary,
            errorBuilder: (_, e2, ___) {
              debugPrint('AvatarView: fallback Lottie also failed: $e2');
              return _fallbackAvatar(context, tint, primary);
            },
          );
        }
        return _fallbackAvatar(context, tint, primary);
      },
    );

    Widget avatarCore = widget.isFloatingWindow
        ? SizedBox(width: visual, height: visual, child: lottie)
        : RepaintBoundary(
            child: SizedBox(width: visual, height: visual, child: lottie),
          );

    if (widget.facingLeft) {
      avatarCore = Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()..scale(-1.0, 1.0),
        child: avatarCore,
      );
    }

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
    // Floating window: use raw Listener to disambiguate long-press (voice)
    // vs drag manually. GestureDetector can't handle both because
    // windowManager.startDragging() captures the OS pointer.
    // In-app overlay: use standard GestureDetector.
    final interactiveAvatar = widget.isFloatingWindow
        ? Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: _onPointerDown,
            onPointerUp: _onPointerUp,
            onPointerMove: _onPointerMove,
            onPointerCancel: _onPointerCancel,
            child: avatarStack,
          )
        : GestureDetector(
            behavior: HitTestBehavior.opaque,
            onLongPressStart: (_) => widget.onVoiceStart?.call(),
            onLongPressEnd: (_) => widget.onVoiceStop?.call(),
            onPanUpdate: widget.onPanUpdate != null
                ? (d) => widget.onPanUpdate!(d.delta)
                : null,
            child: avatarStack,
          );

    final showInputField = widget.isFloatingWindow && widget.snapshot.showInput;

    // Floating window: use Stack so the input field appears BELOW the avatar
    // without shifting the avatar's visual position.
    if (widget.isFloatingWindow) {
      const pad = AvatarSnapshot.kFloatingWindowPadding;
      const inputH = AvatarSnapshot.kInputFieldHeight;

      final avatarContent = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (bubble != null) ...[
            bubble,
            const SizedBox(height: 6),
          ],
          interactiveAvatar,
        ],
      );

      return ClipRect(
        child: Stack(
          children: [
            // Avatar anchored at a fixed position from bottom.
            // When input is visible the window extends below, so we offset
            // the avatar upward by the input height to keep it in place.
            Positioned(
              left: 0,
              right: 0,
              bottom: pad + (showInputField ? inputH + 4 : 0),
              child: Center(child: avatarContent),
            ),
            if (showInputField)
              Positioned(
                left: 0,
                right: 0,
                bottom: pad,
                child: Center(child: _buildInputField(context)),
              ),
          ],
        ),
      );
    }

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


  bool _inputFocusListenerAttached = false;

  void _submitInput() {
    final text = _inputController.text.trim();
    if (text.isEmpty && _attachments.isEmpty) return;
    final atts = List<OutgoingAttachment>.from(_attachments);
    _inputController.clear();
    setState(() => _attachments.clear());
    widget.onInputDismiss?.call();
    widget.onTextSubmit?.call(text, attachments: atts);
  }

  void _onInputFocusChange() {
    if (!_inputFocusNode.hasFocus && mounted) {
      if (_attachments.isEmpty && _inputController.text.trim().isEmpty) {
        widget.onInputDismiss?.call();
      }
    }
  }

  Future<void> _pickAttachment() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp'],
        allowMultiple: true,
      );
      if (result == null || result.files.isEmpty) return;
      for (final pf in result.files) {
        final path = pf.path;
        if (path == null) continue;
        final bytes = await File(path).readAsBytes();
        final ext = path.split('.').last.toLowerCase();
        final mime = switch (ext) {
          'png' => 'image/png',
          'jpg' || 'jpeg' => 'image/jpeg',
          'gif' => 'image/gif',
          'webp' => 'image/webp',
          'bmp' => 'image/bmp',
          _ => 'application/octet-stream',
        };
        if (mounted) {
          setState(() {
            _attachments.add(OutgoingAttachment(
              type: 'image',
              mimeType: mime,
              fileName: pf.name,
              base64: base64Encode(bytes),
            ));
          });
        }
      }
      if (mounted && !_inputFocusNode.hasFocus) {
        _inputFocusNode.requestFocus();
      }
    } catch (e) {
      debugPrint('AvatarInput: pickAttachment error: $e');
    }
  }

  Widget _buildInputField(BuildContext context) {
    if (!_inputFocusListenerAttached) {
      _inputFocusListenerAttached = true;
      _inputFocusNode.addListener(_onInputFocusChange);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_inputFocusNode.hasFocus) {
        _inputFocusNode.requestFocus();
      }
    });

    final cs = Theme.of(context).colorScheme;
    const inputWidth = 220.0;

    return KeyboardListener(
      focusNode: FocusNode(),
      onKeyEvent: (event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          _inputController.clear();
          setState(() => _attachments.clear());
          widget.onInputDismiss?.call();
        }
      },
      child: SizedBox(
        width: inputWidth,
        child: Material(
          borderRadius: BorderRadius.circular(14),
          color: cs.surfaceContainerHighest,
          elevation: 2,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_attachments.isNotEmpty)
                _buildAttachmentPreviews(cs),
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 36, maxHeight: 80),
                child: TextField(
                  controller: _inputController,
                  focusNode: _inputFocusNode,
                  style: const TextStyle(fontSize: 13),
                  maxLines: 4,
                  minLines: 1,
                  textInputAction: TextInputAction.newline,
                  keyboardType: TextInputType.multiline,
                  decoration: InputDecoration(
                    hintText: 'Ask something...',
                    hintStyle: TextStyle(
                      fontSize: 13,
                      color: cs.onSurface.withValues(alpha: 0.4),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    border: InputBorder.none,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(
                    left: 4, right: 4, bottom: 4),
                child: Row(
                  children: [
                    _InputIconButton(
                      icon: Icons.add,
                      tooltip: 'Add attachment',
                      onPressed: _pickAttachment,
                    ),
                    const Spacer(),
                    _InputIconButton(
                      icon: Icons.send,
                      tooltip: 'Send',
                      onPressed: _submitInput,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAttachmentPreviews(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, right: 8, top: 8),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: List.generate(_attachments.length, (i) {
          final att = _attachments[i];
          Uint8List? bytes;
          try {
            bytes = base64Decode(att.base64);
          } catch (_) {}
          return Stack(
            clipBehavior: Clip.none,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: bytes != null
                    ? Image.memory(bytes,
                        width: 48, height: 48, fit: BoxFit.cover)
                    : Container(
                        width: 48,
                        height: 48,
                        color: cs.surfaceContainerHigh,
                        child: const Icon(Icons.broken_image, size: 20),
                      ),
              ),
              Positioned(
                top: -6,
                right: -6,
                child: GestureDetector(
                  onTap: () => setState(() => _attachments.removeAt(i)),
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.close,
                        size: 10, color: Colors.white),
                  ),
                ),
              ),
            ],
          );
        }),
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

// ---------------------------------------------------------------------------
// BoJi Lens Annotation Overlay
// ---------------------------------------------------------------------------

/// Full-window overlay for the BoJi Lens "圈一圈" annotation mode.
/// Rendered in place of the normal avatar view when lens mode is active.
class LensAnnotationOverlay extends StatefulWidget {
  final ScreenCaptureResult? capture;
  final List<Rect> rects;
  final Rect? drawingRect;
  final void Function(Offset localPos) onRectStart;
  final void Function(Offset localPos, Offset startPos) onRectUpdate;
  final VoidCallback onRectEnd;
  final VoidCallback onUndo;
  final VoidCallback onCancel;
  final VoidCallback onConfirm;

  const LensAnnotationOverlay({
    super.key,
    required this.capture,
    required this.rects,
    required this.drawingRect,
    required this.onRectStart,
    required this.onRectUpdate,
    required this.onRectEnd,
    required this.onUndo,
    required this.onCancel,
    required this.onConfirm,
  });

  @override
  State<LensAnnotationOverlay> createState() => _LensAnnotationOverlayState();
}

class _LensAnnotationOverlayState extends State<LensAnnotationOverlay> {
  Offset? _panStart;
  ui.Image? _screenshotImage;

  @override
  void initState() {
    super.initState();
    _decodeScreenshot();
  }

  @override
  void didUpdateWidget(LensAnnotationOverlay old) {
    super.didUpdateWidget(old);
    if (widget.capture != old.capture) {
      _decodeScreenshot();
    }
  }

  Future<void> _decodeScreenshot() async {
    final capture = widget.capture;
    if (capture == null) return;

    final rgba = capture.toRgba();
    final buffer = await ui.ImmutableBuffer.fromUint8List(rgba);
    final descriptor = ui.ImageDescriptor.raw(
      buffer,
      width: capture.width,
      height: capture.height,
      pixelFormat: ui.PixelFormat.rgba8888,
    );
    final codec = await descriptor.instantiateCodec();
    final frame = await codec.getNextFrame();
    descriptor.dispose();

    if (mounted) {
      setState(() => _screenshotImage = frame.image);
    }
  }

  @override
  void dispose() {
    _screenshotImage?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const borderWidth = 3.0;
    const borderColor = Colors.red;

    return MouseRegion(
      cursor: SystemMouseCursors.precise,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Screenshot background (semi-transparent so the annotation is visible)
          if (_screenshotImage != null)
            Positioned.fill(
              child: CustomPaint(
                painter: _ScreenshotPainter(_screenshotImage!),
              ),
            ),

          // Red border around the entire window
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: borderColor, width: borderWidth),
                ),
              ),
            ),
          ),

          // Drawing surface
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onPanStart: (details) {
                _panStart = details.localPosition;
                widget.onRectStart(details.localPosition);
              },
              onPanUpdate: (details) {
                if (_panStart != null) {
                  widget.onRectUpdate(details.localPosition, _panStart!);
                }
              },
              onPanEnd: (_) {
                _panStart = null;
                widget.onRectEnd();
              },
            ),
          ),

          // Saved annotation rectangles
          for (final rect in widget.rects)
            Positioned(
              left: rect.left,
              top: rect.top,
              width: rect.width,
              height: rect.height,
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: borderColor, width: 2),
                    color: borderColor.withValues(alpha: 0.08),
                  ),
                ),
              ),
            ),

          // Currently-drawing rectangle
          if (widget.drawingRect != null)
            Positioned(
              left: widget.drawingRect!.left,
              top: widget.drawingRect!.top,
              width: widget.drawingRect!.width,
              height: widget.drawingRect!.height,
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: borderColor, width: 2),
                    color: borderColor.withValues(alpha: 0.12),
                  ),
                ),
              ),
            ),

          // Toolbar: Cancel, Undo, Confirm — positioned at top-right
          Positioned(
            top: borderWidth + 8,
            right: borderWidth + 8,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _LensToolbarButton(
                  label: '取消',
                  icon: Icons.close,
                  onPressed: widget.onCancel,
                  color: Colors.grey.shade700,
                ),
                const SizedBox(width: 6),
                _LensToolbarButton(
                  label: '撤回',
                  icon: Icons.undo,
                  onPressed: widget.rects.isEmpty ? null : widget.onUndo,
                  color: Colors.orange.shade700,
                ),
                const SizedBox(width: 6),
                _LensToolbarButton(
                  label: '确认',
                  icon: Icons.check,
                  onPressed: widget.onConfirm,
                  color: Colors.green.shade700,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LensToolbarButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final Color color;

  const _LensToolbarButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Material(
      color: enabled ? color : color.withValues(alpha: 0.4),
      borderRadius: BorderRadius.circular(6),
      elevation: 2,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: Colors.white),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: enabled ? Colors.white : Colors.white60,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InputIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  const _InputIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, size: 18,
              color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }
}

class _ScreenshotPainter extends CustomPainter {
  final ui.Image image;

  _ScreenshotPainter(this.image);

  @override
  void paint(Canvas canvas, Size size) {
    final src = Rect.fromLTWH(
      0, 0, image.width.toDouble(), image.height.toDouble());
    final dst = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.drawImageRect(image, src, dst, Paint());
  }

  @override
  bool shouldRepaint(_ScreenshotPainter old) => old.image != image;
}
