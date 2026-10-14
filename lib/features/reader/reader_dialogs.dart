import 'package:flutter/material.dart';

import '../../core/app_scope.dart';

/// Overlay routes live above the shell's inherited scope in the Navigator.
Widget readerOverlayScope(BuildContext source, Widget child) {
  final scope = AppScope.of(source);
  return AppScope(
    api: scope.api,
    open: scope.open,
    refreshSession: scope.refreshSession,
    setNavigationGuard: scope.setNavigationGuard,
    setTheme: scope.setTheme,
    themeMode: scope.themeMode,
    eInk: scope.eInk,
    setEInk: scope.setEInk,
    child: child,
  );
}

class ReaderTextDialog extends StatefulWidget {
  const ReaderTextDialog({
    super.key,
    required this.title,
    this.initial = '',
    this.hint,
    this.lines = 1,
    this.maxLength,
    this.requireValue = false,
    this.submitLabel = 'Übernehmen',
  });
  final String title, initial, submitLabel;
  final String? hint;
  final int lines;
  final int? maxLength;
  final bool requireValue;
  @override
  State<ReaderTextDialog> createState() => _ReaderTextDialogState();
}

class _ReaderTextDialogState extends State<ReaderTextDialog> {
  late final _controller = TextEditingController(text: widget.initial);
  void _submit() {
    if (!widget.requireValue || _controller.text.trim().isNotEmpty) {
      Navigator.pop(context, _controller.text.trim());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      controller: _controller,
      autofocus: true,
      minLines: widget.lines,
      maxLines: widget.lines == 1 ? 1 : 12,
      maxLength: widget.maxLength,
      decoration: InputDecoration(hintText: widget.hint),
      onSubmitted: widget.lines == 1 ? (_) => _submit() : null,
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Abbrechen'),
      ),
      FilledButton(onPressed: _submit, child: Text(widget.submitLabel)),
    ],
  );
}
