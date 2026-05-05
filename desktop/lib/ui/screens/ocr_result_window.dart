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

  const OcrResultWindow(
      {super.key, this.initialText = '', this.imageBase64});

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
    final cs = Theme.of(context).colorScheme;
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
      home: Scaffold(
        body: Column(
          children: [
            // Screenshot preview
            if (widget.imageBase64 != null &&
                widget.imageBase64!.isNotEmpty)
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 200),
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    border: Border(
                        bottom: BorderSide(
                            color: cs.outlineVariant, width: 1)),
                  ),
                  child: Image.memory(
                    base64Decode(widget.imageBase64!),
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            // Recognized text
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: TextField(
                  controller: _controller,
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                  style: TextStyle(fontSize: 14, color: cs.onSurface),
                  decoration: InputDecoration(
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding: const EdgeInsets.all(12),
                    hintText: s.ocrNoText,
                    filled: true,
                    fillColor:
                        cs.surfaceContainerHighest.withOpacity(0.3),
                  ),
                ),
              ),
            ),
            // Copy button only
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
                    icon:
                        Icon(_copied ? Icons.check : Icons.copy, size: 16),
                    label: Text(_copied ? s.ocrCopied : s.ocrCopy),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
