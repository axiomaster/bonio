import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../l10n/app_strings.dart';

/// Shows an OCR result popup with editable text and a copy button.
class OcrResultDialog extends StatefulWidget {
  final String initialText;
  final String windowTitle;

  const OcrResultDialog({
    super.key,
    required this.initialText,
    this.windowTitle = '',
  });

  /// Show the dialog and return the text when user closes it.
  static Future<String?> show(
    BuildContext context, {
    required String initialText,
    String windowTitle = '',
  }) {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => OcrResultDialog(
        initialText: initialText,
        windowTitle: windowTitle,
      ),
    );
  }

  @override
  State<OcrResultDialog> createState() => _OcrResultDialogState();
}

class _OcrResultDialogState extends State<OcrResultDialog> {
  late final TextEditingController _controller;
  bool _copied = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s = S.current;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: 520,
          maxHeight: 460,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Title bar
            Container(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
              decoration: BoxDecoration(
                color: cs.primaryContainer.withOpacity(0.3),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(12)),
              ),
              child: Row(
                children: [
                  Icon(Icons.text_fields, size: 18, color: cs.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      s.ocrResultTitle,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => Navigator.pop(context),
                    tooltip: s.ocrClose,
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
            // Editable text area
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: TextField(
                  controller: _controller,
                  maxLines: null,
                  minLines: 4,
                  style: TextStyle(fontSize: 14, color: cs.onSurface),
                  decoration: InputDecoration(
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding: const EdgeInsets.all(12),
                    hintText: s.ocrNoText,
                  ),
                ),
              ),
            ),
            // Bottom action bar
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
              child: Row(
                children: [
                  // Copy button
                  FilledButton.icon(
                    onPressed: () {
                      Clipboard.setData(
                          ClipboardData(text: _controller.text));
                      setState(() => _copied = true);
                      Future.delayed(
                          const Duration(seconds: 2),
                          () {
                        if (mounted) setState(() => _copied = false);
                      });
                    },
                    icon: Icon(
                      _copied ? Icons.check : Icons.copy,
                      size: 16,
                    ),
                    label: Text(_copied ? s.ocrCopied : s.ocrCopy),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(s.ocrClose),
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
