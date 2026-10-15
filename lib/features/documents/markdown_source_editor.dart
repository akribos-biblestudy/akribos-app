import 'package:flutter/material.dart';

import '../../theme/akribos_theme.dart';

/// Explicit source operations for the document's existing insertion menu.
enum MarkdownInsertBlock {
  paragraph,
  heading1,
  heading2,
  heading3,
  bulletedList,
  numberedList,
  quote,
  code,
  rule,
  table,
  footnote,
}

TextSelection _selection(TextEditingController controller) {
  final selection = controller.selection;
  return selection.isValid && selection.end <= controller.text.length
      ? selection
      : TextSelection.collapsed(offset: controller.text.length);
}

/// Inserts source exactly as provided, at the selection or at the document end.
void insertMarkdownText(TextEditingController controller, String markdown) {
  if (markdown.isEmpty) return;
  final selection = _selection(controller);
  controller.value = TextEditingValue(
    text: controller.text.replaceRange(
      selection.start,
      selection.end,
      markdown,
    ),
    selection: TextSelection.collapsed(
      offset: selection.start + markdown.length,
    ),
  );
}

void _insertBlock(TextEditingController controller, String source) {
  final selection = _selection(controller);
  final before = controller.text.substring(0, selection.start);
  final after = controller.text.substring(selection.end);
  String separator(String text, {bool start = false}) {
    if (text.isEmpty ||
        (start ? text.startsWith('\n\n') : text.endsWith('\n\n'))) {
      return '';
    }
    return (start ? text.startsWith('\n') : text.endsWith('\n'))
        ? '\n'
        : '\n\n';
  }

  insertMarkdownText(
    controller,
    '${separator(before)}$source${separator(after, start: true)}',
  );
}

/// Changes only the selected lines or inserts a literal Markdown template.
/// This does not parse, reserialize, or normalize the surrounding document.
void insertMarkdownBlock(
  TextEditingController controller,
  MarkdownInsertBlock block,
) {
  final selection = _selection(controller);
  final text = controller.text;
  if (block == MarkdownInsertBlock.footnote) {
    final used = RegExp(r'\[\^([^\]\r\n]+)\]')
        .allMatches(text)
        .map((match) => match[1])
        .toSet();
    var id = 1;
    while (used.contains('$id')) {
      id++;
    }
    final withReference = text.replaceRange(
      selection.end,
      selection.end,
      '[^$id]',
    );
    final gap = withReference.endsWith('\n\n')
        ? ''
        : withReference.endsWith('\n')
        ? '\n'
        : '\n\n';
    final prefix = '$withReference$gap[^$id]: ';
    const placeholder = 'Fußnotentext';
    controller.value = TextEditingValue(
      text: '$prefix$placeholder\n',
      selection: TextSelection(
        baseOffset: prefix.length,
        extentOffset: prefix.length + placeholder.length,
      ),
    );
    return;
  }
  if (block == MarkdownInsertBlock.rule) {
    _insertBlock(controller, '---');
    return;
  }
  if (block == MarkdownInsertBlock.table) {
    _insertBlock(
      controller,
      '| Überschrift | Überschrift |\n| --- | --- |\n| Inhalt | Inhalt |',
    );
    return;
  }
  if (block == MarkdownInsertBlock.code) {
    final selected = selection.textInside(text);
    var fenceLength = 3;
    for (final run in RegExp(r'`+').allMatches(selected)) {
      if (run.group(0)!.length >= fenceLength) {
        fenceLength = run.group(0)!.length + 1;
      }
    }
    final fence = '`' * fenceLength;
    _insertBlock(controller, '$fence\n$selected\n$fence');
    return;
  }

  final start = selection.start == 0
      ? 0
      : text.lastIndexOf('\n', selection.start - 1) + 1;
  final selectedEnd = selection.end > start && text[selection.end - 1] == '\n'
      ? selection.end - 1
      : selection.end;
  final nextBreak = text.indexOf('\n', selectedEnd);
  final end = nextBreak < 0 ? text.length : nextBreak;
  final lines = text.substring(start, end).split('\n');
  var number = 0;
  final changed = lines
      .map((line) {
        if (line.isEmpty && lines.length > 1) return line;
        final indent = RegExp(r'^[\t ]*').firstMatch(line)!.group(0)!;
        var body = line.substring(indent.length);
        final prefix = switch (block) {
          MarkdownInsertBlock.heading1 => '# ',
          MarkdownInsertBlock.heading2 => '## ',
          MarkdownInsertBlock.heading3 => '### ',
          MarkdownInsertBlock.bulletedList => '- ',
          MarkdownInsertBlock.numberedList => '${++number}. ',
          MarkdownInsertBlock.quote => '> ',
          _ => '',
        };
        if (block == MarkdownInsertBlock.paragraph) {
          body = body.replaceFirst(
            RegExp(r'^(?:#{1,6}[\t ]+|[-+*][\t ]+|\d+[.)][\t ]+|>[\t ]?)'),
            '',
          );
        } else if (block == MarkdownInsertBlock.heading1 ||
            block == MarkdownInsertBlock.heading2 ||
            block == MarkdownInsertBlock.heading3) {
          body = body.replaceFirst(RegExp(r'^#{1,6}[\t ]+'), '');
        } else if (block == MarkdownInsertBlock.bulletedList ||
            block == MarkdownInsertBlock.numberedList) {
          body = body.replaceFirst(RegExp(r'^(?:[-+*]|\d+[.)])[\t ]+'), '');
        }
        return '$indent$prefix$body';
      })
      .join('\n');
  controller.value = TextEditingValue(
    text: text.replaceRange(start, end, changed),
    selection: selection.isCollapsed
        ? TextSelection.collapsed(
            offset: (selection.start + changed.length - (end - start)).clamp(
              start,
              start + changed.length,
            ),
          )
        : TextSelection(
            baseOffset: start,
            extentOffset: start + changed.length,
          ),
  );
}

/// Native source editing only. The host keeps this widget mounted while its
/// separate reading surface is visible, retaining Flutter's own undo history.
class MarkdownSourceEditor extends StatefulWidget {
  const MarkdownSourceEditor({
    super.key,
    required this.controller,
    required this.undoController,
    required this.focusNode,
    required this.scrollController,
    this.readOnly = false,
    this.fontScale = 1,
  });
  final TextEditingController controller;
  final UndoHistoryController undoController;
  final FocusNode focusNode;
  final ScrollController scrollController;
  final bool readOnly;
  final double fontScale;

  @override
  State<MarkdownSourceEditor> createState() => _MarkdownSourceEditorState();
}

enum _InlineFormat { underline, strike, highlight, code }

class _MarkdownSourceEditorState extends State<MarkdownSourceEditor> {
  @override
  void didUpdateWidget(MarkdownSourceEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.readOnly && !oldWidget.readOnly) {
      ContextMenuController.removeAny();
      widget.focusNode.unfocus();
    }
  }

  bool _canApply(TextEditingController controller, TextEditingValue original) =>
      mounted &&
      !widget.readOnly &&
      identical(widget.controller, controller) &&
      controller.text == original.text;

  void _wrap(String before, String after, TextEditingValue original) {
    if (widget.readOnly) return;
    final controller = widget.controller;
    final selection = original.selection;
    if (!selection.isValid || selection.isCollapsed) return;
    final selected = selection.textInside(controller.text);
    // Keep boundary whitespace outside emphasis instead of changing its bytes.
    final leading = RegExp(r'^\s*').firstMatch(selected)!.group(0)!;
    final trailing = RegExp(r'\s*$').firstMatch(selected)!.group(0)!;
    if (leading.length == selected.length) return;
    final start = selection.start + leading.length;
    final end = selection.end - trailing.length;
    final content = controller.text.substring(start, end);
    controller.value = TextEditingValue(
      text: controller.text.replaceRange(start, end, '$before$content$after'),
      selection: TextSelection(
        baseOffset: start + before.length,
        extentOffset: end + before.length,
      ),
    );
  }

  Future<void> _link(EditableTextState state, TextEditingValue original) async {
    final controller = widget.controller;
    if (!_canApply(controller, original)) return;
    state.hideToolbar();
    final destination = await showDialog<String>(
      context: context,
      builder: (_) => const _LinkDialog(),
    );
    if (destination == null || !_canApply(controller, original)) return;
    final selection = original.selection;
    if (!selection.isValid || selection.isCollapsed) return;
    final label = selection
        .textInside(original.text)
        .replaceAll('[', r'\[')
        .replaceAll(']', r'\]');
    final href = Uri.parse(destination)
        .toString()
        .replaceAll('(', '%28')
        .replaceAll(')', '%29');
    controller.value = original.copyWith(
      selection: selection,
      composing: TextRange.empty,
    );
    insertMarkdownText(controller, '[$label]($href)');
  }

  Future<void> _more(EditableTextState state, TextEditingValue original) async {
    final controller = widget.controller;
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final anchor = overlay.globalToLocal(
      state.contextMenuAnchors.primaryAnchor,
    );
    state.hideToolbar();
    // This future belongs to the editor, not to its transient selection overlay.
    final value = await showMenu<_InlineFormat>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(anchor.dx, anchor.dy, 1, 1),
        Offset.zero & overlay.size,
      ),
      items: const [
        PopupMenuItem(
          value: _InlineFormat.underline,
          child: Text('Unterstreichen'),
        ),
        PopupMenuItem(
          value: _InlineFormat.strike,
          child: Text('Durchstreichen'),
        ),
        PopupMenuItem(
          value: _InlineFormat.highlight,
          child: Text('Hervorheben'),
        ),
        PopupMenuItem(value: _InlineFormat.code, child: Text('Code')),
      ],
    );
    if (value == null || !_canApply(controller, original)) return;
    switch (value) {
      case _InlineFormat.underline:
        _wrap('<u>', '</u>', original);
      case _InlineFormat.strike:
        _wrap('~~', '~~', original);
      case _InlineFormat.highlight:
        _wrap('<mark>', '</mark>', original);
      case _InlineFormat.code:
        final selected = original.selection.textInside(original.text);
        var length = 1;
        for (final run in RegExp(r'`+').allMatches(selected)) {
          if (run.group(0)!.length >= length) {
            length = run.group(0)!.length + 1;
          }
        }
        final fence = '`' * length;
        final padding = selected.startsWith('`') || selected.endsWith('`')
            ? ' '
            : '';
        _wrap('$fence$padding', '$padding$fence', original);
    }
  }

  Widget _menu(BuildContext context, EditableTextState state) {
    final nativeItems = state.contextMenuButtonItems;
    if (widget.readOnly || widget.controller.selection.isCollapsed) {
      return AdaptiveTextSelectionToolbar.buttonItems(
        anchors: state.contextMenuAnchors,
        buttonItems: nativeItems,
      );
    }
    final controller = widget.controller;
    final original = controller.value;
    void format(String before, String after) {
      if (!_canApply(controller, original)) return;
      _wrap(before, after, original);
      state.hideToolbar();
    }

    return AdaptiveTextSelectionToolbar(
      anchors: state.contextMenuAnchors,
      children: [
        IconButton(
          tooltip: 'Fett',
          onPressed: () => format('**', '**'),
          icon: const Icon(Icons.format_bold),
        ),
        IconButton(
          tooltip: 'Kursiv',
          onPressed: () => format('*', '*'),
          icon: const Icon(Icons.format_italic),
        ),
        IconButton(
          tooltip: 'Link einfügen',
          onPressed: () => _link(state, original),
          icon: const Icon(Icons.link),
        ),
        IconButton(
          tooltip: 'Weitere Formatierung',
          icon: const Icon(Icons.more_horiz),
          onPressed: () => _more(state, original),
        ),
        ...AdaptiveTextSelectionToolbar.getAdaptiveButtons(
          context,
          nativeItems,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 850),
      child: TextField(
        key: const Key('markdown-source-field'),
        controller: widget.controller,
        undoController: widget.undoController,
        focusNode: widget.focusNode,
        scrollController: widget.scrollController,
        readOnly: widget.readOnly,
        expands: true,
        minLines: null,
        maxLines: null,
        keyboardType: TextInputType.multiline,
        textInputAction: TextInputAction.newline,
        textCapitalization: TextCapitalization.sentences,
        smartDashesType: SmartDashesType.disabled,
        smartQuotesType: SmartQuotesType.disabled,
        autofillHints: null,
        textAlignVertical: TextAlignVertical.top,
        style: TextStyle(
          fontFamily: 'monospace',
          fontFamilyFallback: const ['NotoSansHebrew'],
          fontSize: 17 * widget.fontScale,
          height: 1.5,
          color: Theme.of(context).colorScheme.onSurface,
        ),
        cursorOpacityAnimates: !AkribosThemeTokens.of(context).eInk,
        decoration: const InputDecoration(
          hintText: 'Deine Gedanken …',
          isDense: true,
          filled: false,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          disabledBorder: InputBorder.none,
          errorBorder: InputBorder.none,
          focusedErrorBorder: InputBorder.none,
          contentPadding: EdgeInsets.fromLTRB(4, 12, 4, 24),
        ),
        contextMenuBuilder: _menu,
      ),
    ),
  );
}

class _LinkDialog extends StatefulWidget {
  const _LinkDialog();
  @override
  State<_LinkDialog> createState() => _LinkDialogState();
}

class _LinkDialogState extends State<_LinkDialog> {
  final _address = TextEditingController();
  String? _error;
  @override
  void dispose() {
    _address.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _address.text.trim();
    final uri = Uri.tryParse(value);
    if (value.isEmpty ||
        uri == null ||
        uri.userInfo.isNotEmpty ||
        uri.host.isNotEmpty && !['https', 'http'].contains(uri.scheme) ||
        (!value.startsWith('/') &&
            !value.startsWith('#') &&
            !['https', 'http', 'mailto'].contains(uri.scheme))) {
      setState(
        () => _error = 'Bitte eine Webadresse oder einen internen Link wie /Joh3,16 eingeben.',
      );
      return;
    }
    Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Link einfügen'),
    content: TextField(
      controller: _address,
      autofocus: true,
      keyboardType: TextInputType.url,
      autofillHints: null,
      decoration: InputDecoration(labelText: 'Adresse', errorText: _error),
      onSubmitted: (_) => _submit(),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Abbrechen'),
      ),
      FilledButton(onPressed: _submit, child: const Text('Einfügen')),
    ],
  );
}
