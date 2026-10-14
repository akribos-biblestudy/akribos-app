import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/app_scope.dart';
import '../../widgets/common.dart';
import 'comment_markdown.dart';

Future<bool> editCollectionComment(
  BuildContext context, {
  required String path,
  required Json fields,
  String? originalHtml,
  bool reply = false,
}) async =>
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _CommentEditor(
        api: AppScope.of(context).api,
        path: path,
        fields: fields,
        originalHtml: originalHtml,
        reply: reply,
      ),
    ) ??
    false;

class _CommentEditor extends StatefulWidget {
  const _CommentEditor({
    required this.api,
    required this.path,
    required this.fields,
    required this.originalHtml,
    required this.reply,
  });
  final AppApi api;
  final String path;
  final Json fields;
  final String? originalHtml;
  final bool reply;
  @override
  State<_CommentEditor> createState() => _CommentEditorState();
}

class _CommentEditorState extends State<_CommentEditor> {
  late final String _initial = widget.originalHtml == null
      ? ''
      : commentToMarkdown(widget.originalHtml!);
  late final _controller = TextEditingController(text: _initial);
  bool _preview = false;
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String get _html => commentFromMarkdown(
    _controller.text,
    originalHtml: widget.originalHtml,
    initialMarkdown: _initial,
  );

  void _insert(String before, [String after = '']) {
    final selection = _controller.selection;
    final start = selection.isValid ? selection.start : _controller.text.length;
    final end = selection.isValid ? selection.end : start;
    final text = _controller.text.substring(start, end);
    _controller.value = TextEditingValue(
      text: _controller.text.replaceRange(start, end, '$before$text$after'),
      selection: TextSelection.collapsed(
        offset: start + before.length + text.length,
      ),
    );
  }

  Future<void> _save() async {
    if (_controller.text.trim().isEmpty) {
      setState(() => _error = 'Bitte einen Kommentar eingeben.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.api.action(widget.path, 'comment', {
        ...widget.fields,
        'note': _html,
      });
      if (!mounted) return;
      if (result.isSuccess) {
        Navigator.pop(context, true);
      } else {
        setState(() => _error = result.message);
      }
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.originalHtml != null
          ? 'Kommentar bearbeiten'
          : widget.reply
          ? 'Antwort schreiben'
          : 'Kommentieren',
    ),
    content: SizedBox(
      width: 580,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              children: [
                IconButton(
                  tooltip: 'Fett',
                  onPressed: _busy ? null : () => _insert('**', '**'),
                  icon: const Icon(Icons.format_bold),
                ),
                IconButton(
                  tooltip: 'Kursiv',
                  onPressed: _busy ? null : () => _insert('*', '*'),
                  icon: const Icon(Icons.format_italic),
                ),
                IconButton(
                  tooltip: 'Unterstreichen',
                  onPressed: _busy ? null : () => _insert('<u>', '</u>'),
                  icon: const Icon(Icons.format_underlined),
                ),
                IconButton(
                  tooltip: 'Liste',
                  onPressed: _busy ? null : () => _insert('\n- '),
                  icon: const Icon(Icons.format_list_bulleted),
                ),
                IconButton(
                  tooltip: 'Zitat',
                  onPressed: _busy ? null : () => _insert('\n> '),
                  icon: const Icon(Icons.format_quote),
                ),
                IconButton(
                  tooltip: _preview ? 'Bearbeiten' : 'Vorschau',
                  onPressed: () => setState(() => _preview = !_preview),
                  icon: Icon(
                    _preview ? Icons.edit_outlined : Icons.visibility_outlined,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_preview)
              HtmlContent(html: _html)
            else
              TextField(
                controller: _controller,
                enabled: !_busy,
                minLines: 5,
                maxLines: 12,
                keyboardType: TextInputType.multiline,
                decoration: const InputDecoration(
                  labelText: 'Dein Kommentar',
                  helperText:
                      'Formatieren mit den Schaltflächen oder Markdown.',
                  helperMaxLines: 3,
                ),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context, false),
        child: const Text('Abbrechen'),
      ),
      FilledButton(
        onPressed: _busy ? null : _save,
        child: Text(_busy ? 'Speichert …' : 'Speichern'),
      ),
    ],
  );
}
