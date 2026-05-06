import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';
import '../../l10n/app_strings.dart';

/// Independent OS-level window showing OCR recognition result.
/// Created via desktop_multi_window, separate from the main Bonio window.
class OcrResultWindow extends StatefulWidget {
  final String initialText;
  final String? imageBase64;
  final double preferredImageWidth;
  final double preferredImageHeight;
  final int minimumTextLines;
  final double minimumTextFieldHeight;
  final double minimumWindowWidth;
  final double minimumWindowHeight;

  const OcrResultWindow(
      {super.key,
      this.initialText = '',
      this.imageBase64,
      this.preferredImageWidth = 0,
      this.preferredImageHeight = 0,
      this.minimumTextLines = 2,
      this.minimumTextFieldHeight = 120,
      this.minimumWindowWidth = 600,
      this.minimumWindowHeight = 400});

  @override
  State<OcrResultWindow> createState() => _OcrResultWindowState();
}

class _OcrResultWindowState extends State<OcrResultWindow>
    with WindowListener {
  late final TextEditingController _controller;
  bool _copied = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
    windowManager.ensureInitialized();
    windowManager.addListener(this);
    windowManager.setPreventClose(true);
    windowManager.setTitle(S.current.ocrResultTitle);
    windowManager.setMinimumSize(
      Size(widget.minimumWindowWidth, widget.minimumWindowHeight),
    );
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  void onWindowClose() async {
    await windowManager.setPreventClose(false);
    await windowManager.close();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.current;

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6366F1),
          brightness: Brightness.dark,
        ),
      ),
      home: Builder(
        builder: (context) {
          final cs = Theme.of(context).colorScheme;
          return Scaffold(
            backgroundColor: cs.surface,
            body: Column(
              children: [
                if (widget.imageBase64 != null &&
                    widget.imageBase64!.isNotEmpty)
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      minWidth: widget.preferredImageWidth > 0
                          ? widget.preferredImageWidth
                          : widget.minimumWindowWidth - 24,
                      minHeight: widget.preferredImageHeight > 0
                          ? widget.preferredImageHeight
                          : 120,
                      maxWidth: widget.preferredImageWidth > 0
                          ? widget.preferredImageWidth
                          : double.infinity,
                      maxHeight: widget.preferredImageHeight > 0
                          ? widget.preferredImageHeight
                          : 320,
                    ),
                    child: Container(
                      width: widget.preferredImageWidth > 0
                          ? widget.preferredImageWidth
                          : double.infinity,
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerLow,
                        border: Border(
                          bottom: BorderSide(
                            color: cs.outlineVariant,
                            width: 1,
                          ),
                        ),
                      ),
                      child: Image.memory(
                        base64Decode(widget.imageBase64!),
                        fit: BoxFit.none,
                        alignment: Alignment.topCenter,
                      ),
                    ),
                  ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(12),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: widget.minimumTextFieldHeight,
                      ),
                      child: TextField(
                        controller: _controller,
                        maxLines: null,
                        minLines: widget.minimumTextLines,
                        textAlignVertical: TextAlignVertical.top,
                        cursorColor: cs.primary,
                        style: TextStyle(
                          fontSize: 14,
                          color: cs.onSurface,
                        ),
                        decoration: InputDecoration(
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: cs.outlineVariant),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: cs.primary),
                          ),
                          contentPadding: const EdgeInsets.all(12),
                          hintText: s.ocrNoText,
                          hintStyle: TextStyle(
                            color: cs.onSurfaceVariant,
                          ),
                          filled: true,
                          fillColor: cs.surfaceContainerHigh,
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  child: Row(
                    children: [
                      FilledButton.icon(
                        onPressed: () {
                          Clipboard.setData(
                              ClipboardData(text: _controller.text));
                          setState(() => _copied = true);
                          Future.delayed(const Duration(seconds: 2), () {
                            if (mounted) setState(() => _copied = false);
                          });
                        },
                        icon: Icon(
                          _copied ? Icons.check : Icons.copy,
                          size: 16,
                        ),
                        label: Text(_copied ? s.ocrCopied : s.ocrCopy),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
