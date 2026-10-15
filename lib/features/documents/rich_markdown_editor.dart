import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as q;
import 'package:markdown/markdown.dart' as md;
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_scope.dart';
import '../../theme/akribos_theme.dart';
import '../../widgets/common.dart';
import 'rich_markdown_controller.dart';

/// Block actions live in the document header, never in a permanent editor toolbar.
enum RichMarkdownBlock {
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

Future<void> insertRichMarkdownBlock(
  BuildContext context,
  RichMarkdownController controller,
  RichMarkdownBlock block,
) async {
  if (controller.quill.readOnly) return;
  if (block == RichMarkdownBlock.table) {
    final source = await showDialog<String>(
      context: context,
      builder: (_) => const _TableDialog(
        source: '| Überschrift | Überschrift |\n| --- | --- |\n| Inhalt | Inhalt |\n',
      ),
    );
    if (source != null && !controller.quill.readOnly) {
      controller.insertMarkdown('\n\n$source\n');
    }
    return;
  }
  if (block == RichMarkdownBlock.footnote) {
    final source = await showDialog<String>(
      context: context,
      builder: (_) => const _TextBlockDialog(title: 'Fußnote', source: ''),
    );
    if (source != null && !controller.quill.readOnly) {
      controller.insertFootnote(content: source);
    }
    return;
  }
  if (block == RichMarkdownBlock.rule) {
    controller.insertMarkdown('\n\n---\n\n');
    return;
  }
  final editor = controller.quill;
  for (final attribute in <q.Attribute>[
    q.Attribute.header,
    q.Attribute.list,
    q.Attribute.blockQuote,
    q.Attribute.codeBlock,
  ]) {
    editor.formatSelection(q.Attribute.clone(attribute, null));
  }
  final attribute = switch (block) {
    RichMarkdownBlock.heading1 => q.Attribute.h1,
    RichMarkdownBlock.heading2 => q.Attribute.h2,
    RichMarkdownBlock.heading3 => q.Attribute.h3,
    RichMarkdownBlock.bulletedList => q.Attribute.ul,
    RichMarkdownBlock.numberedList => q.Attribute.ol,
    RichMarkdownBlock.quote => q.Attribute.blockQuote,
    RichMarkdownBlock.code => q.Attribute.codeBlock,
    _ => null,
  };
  if (attribute != null) editor.formatSelection(attribute);
}

/// A single native editing surface. Read mode keeps the same document, selection,
/// undo history and scroll controller, but cannot open the software keyboard.
class RichMarkdownEditor extends StatefulWidget {
  const RichMarkdownEditor({
    super.key,
    required this.controller,
    required this.readOnly,
    this.scrollController,
    this.focusNode,
    this.fontScale = 1,
  });
  final RichMarkdownController controller;
  final bool readOnly;
  final ScrollController? scrollController;
  final FocusNode? focusNode;
  final double fontScale;

  @override
  State<RichMarkdownEditor> createState() => _RichMarkdownEditorState();
}

class _RichMarkdownEditorState extends State<RichMarkdownEditor> {
  late final ScrollController _ownedScroll = ScrollController();
  late final FocusNode _ownedFocus = FocusNode();
  ScrollController get _scroll => widget.scrollController ?? _ownedScroll;
  FocusNode get _focus => widget.focusNode ?? _ownedFocus;

  @override
  void initState() {
    super.initState();
    widget.controller.quill.readOnly = widget.readOnly;
  }

  @override
  void didUpdateWidget(RichMarkdownEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    widget.controller.quill.readOnly = widget.readOnly;
    if (widget.readOnly && !oldWidget.readOnly) {
      ContextMenuController.removeAny();
      _focus.unfocus();
    }
  }

  @override
  void dispose() {
    _ownedScroll.dispose();
    _ownedFocus.dispose();
    super.dispose();
  }

  Widget _selectionMenu(BuildContext context, q.QuillRawEditorState state) {
    final editor = widget.controller.quill;
    final nativeItems = state.contextMenuButtonItems;
    if (widget.readOnly || editor.selection.isCollapsed) {
      return AdaptiveTextSelectionToolbar.buttonItems(
        anchors: state.contextMenuAnchors,
        buttonItems: nativeItems,
      );
    }
    final style = editor.getSelectionStyle().attributes;
    Widget format(String label, IconData icon, q.Attribute attribute) {
      final active = style[attribute.key]?.value != null;
      return IconButton(
        tooltip: label,
        isSelected: active,
        onPressed: () {
          if (widget.readOnly || editor.selection.isCollapsed) return;
          editor.formatSelection(
            active ? q.Attribute.clone(attribute, null) : attribute,
          );
          state.hideToolbar();
        },
        icon: Icon(icon),
      );
    }

    // Flutter's platform selection toolbar provides a single row and a native
    // overflow menu at narrow widths, with its anchor clamped above the keyboard.
    return AdaptiveTextSelectionToolbar(
      anchors: state.contextMenuAnchors,
      children: [
        format('Fett', Icons.format_bold, q.Attribute.bold),
        format('Kursiv', Icons.format_italic, q.Attribute.italic),
        format(
          'Unterstreichen',
          Icons.format_underlined,
          q.Attribute.underline,
        ),
        format(
          'Durchstreichen',
          Icons.format_strikethrough,
          q.Attribute.strikeThrough,
        ),
        format(
          'Hervorheben',
          Icons.highlight_outlined,
          const q.BackgroundAttribute('#fff2a8'),
        ),
        IconButton(
          tooltip: 'Link bearbeiten',
          icon: const Icon(Icons.link),
          onPressed: () async {
            final selection = editor.selection;
            final old = style[q.Attribute.link.key]?.value?.toString() ?? '';
            state.hideToolbar();
            final value = await showDialog<String>(
              context: this.context,
              builder: (_) => _LinkDialog(value: old),
            );
            if (!mounted || widget.readOnly || value == null) return;
            editor.formatText(
              selection.start,
              selection.end - selection.start,
              q.LinkAttribute(value.isEmpty ? null : value),
            );
          },
        ),
        ...AdaptiveTextSelectionToolbar.getAdaptiveButtons(
          context,
          nativeItems,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AkribosThemeTokens.of(context);
    final color = Theme.of(context).colorScheme.onSurface;
    final text = TextStyle(
      fontFamily: 'AkribosText',
      fontFamilyFallback: const ['NotoSansHebrew'],
      fontSize: 19 * widget.fontScale,
      height: 1.6,
      color: color,
    );
    q.DefaultTextBlockStyle block(
      TextStyle style, {
      double before = 0,
      double after = 10,
    }) => q.DefaultTextBlockStyle(
      style,
      q.HorizontalSpacing.zero,
      q.VerticalSpacing(before, after),
      q.VerticalSpacing.zero,
      null,
    );
    final defaults = q.DefaultStyles.getInstance(context);
    final styles = q.DefaultStyles(
      paragraph: block(text),
      h1: block(
        text.copyWith(
          fontSize: 32 * widget.fontScale,
          fontWeight: FontWeight.w700,
          height: 1.2,
        ),
        before: 20,
      ),
      h2: block(
        text.copyWith(
          fontSize: 27 * widget.fontScale,
          fontWeight: FontWeight.w600,
          height: 1.25,
        ),
        before: 18,
      ),
      h3: block(
        text.copyWith(
          fontSize: 23 * widget.fontScale,
          fontWeight: FontWeight.w600,
          height: 1.3,
        ),
        before: 14,
      ),
      h4: block(text.copyWith(fontWeight: FontWeight.w700), before: 12),
      h5: block(text.copyWith(fontWeight: FontWeight.w600), before: 10),
      h6: block(text.copyWith(fontWeight: FontWeight.w600), before: 8),
      lists: defaults.lists?.copyWith(style: text),
      quote: block(text.copyWith(color: tokens.muted)).copyWith(
        horizontalSpacing: const q.HorizontalSpacing(18, 0),
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: tokens.accent, width: 2)),
        ),
      ),
      code: block(
        text.copyWith(
          fontFamily: 'monospace',
          fontSize: 15 * widget.fontScale,
          height: 1.5,
        ),
      ),
      placeHolder: block(text.copyWith(color: tokens.muted)),
      link: TextStyle(
        color: tokens.accent,
        decoration: TextDecoration.underline,
      ),
    );
    return ColoredBox(
      color: tokens.paper,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 850),
          child: DefaultTextStyle(
            style: text,
            child: q.QuillEditor(
              controller: widget.controller.quill,
              scrollController: _scroll,
              focusNode: _focus,
              config: q.QuillEditorConfig(
                expands: true,
                autoFocus: false,
                showCursor: !widget.readOnly,
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 80),
                placeholder: 'Deine Gedanken …',
                customStyles: styles,
                scrollPhysics: const ClampingScrollPhysics(),
                showCodeBlockLineNumbers: false,
                contextMenuBuilder: _selectionMenu,
                transformLink: (link) => link,
                onLaunchUrl: (link) => _openLink(context, link),
                linkActionPickerDelegate: widget.readOnly
                    ? (_, _, _) async => q.LinkMenuAction.launch
                    : q.defaultLinkActionPickerDelegate,
                embedBuilders: [
                  _SourceEmbedBuilder(widget.controller),
                  _FootnoteEmbedBuilder(widget.controller),
                ],
                unknownEmbedBuilder: _UnknownEmbedBuilder(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> _openLink(BuildContext context, String link) async {
  final scope = AppScope.of(context);
  final parsed = Uri.tryParse(link);
  if (parsed == null || parsed.userInfo.isNotEmpty) return;
  final uri = scope.api.origin.resolveUri(parsed);
  if (!['https', 'http', 'mailto'].contains(uri.scheme)) return;
  if (uri.scheme != 'mailto' && uri.origin == scope.api.origin.origin) {
    await scope.open(
      '${uri.path}${uri.hasQuery ? '?${uri.query}' : ''}${uri.hasFragment ? '#${uri.fragment}' : ''}',
    );
  } else if (await confirmAction(
    context,
    'Externen Link öffnen?',
    uri.toString(),
  )) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

Map<String, dynamic> _payload(dynamic value) {
  try {
    final decoded = value is String ? jsonDecode(value) : value;
    return decoded is Map ? Map<String, dynamic>.from(decoded) : {};
  } catch (_) {
    return {};
  }
}

String _footnoteBody(String raw) {
  final first = raw.replaceFirst(RegExp(r'^ {0,3}\[\^[^\]]+\]:[ \t]?'), '');
  return first
      .split('\n')
      .map(
        (line) => line.startsWith('    ')
            ? line.substring(4)
            : line.startsWith('\t')
            ? line.substring(1)
            : line,
      )
      .join('\n')
      .trimRight();
}

Map<String, String> _footnotes(RichMarkdownController controller) {
  final notes = <String, String>{};
  for (final operation in controller.quill.document.toDelta().toList()) {
    final data = operation.data;
    if (data is Map && data.containsKey(richMarkdownSourceEmbedType)) {
      final payload = _payload(data[richMarkdownSourceEmbedType]);
      if (payload['kind'] == 'footnote') {
        final raw = '${payload['raw'] ?? ''}';
        final id =
            payload['id']?.toString() ??
            RegExp(r'^ {0,3}\[\^([^\]]+)\]:').firstMatch(raw)?.group(1);
        if (id != null) notes[id] = _footnoteBody(raw);
      }
    }
  }
  return notes;
}

String _footnoteNumber(RichMarkdownController controller, String id) {
  final seen = <String>{};
  for (final operation in controller.quill.document.toDelta().toList()) {
    final data = operation.data;
    if (data is Map && data.containsKey(richMarkdownFootnoteEmbedType)) {
      final reference = _payload(
        data[richMarkdownFootnoteEmbedType],
      )['id']?.toString();
      if (reference != null) seen.add(reference);
      if (reference == id) return '${seen.length}';
    }
  }
  return id;
}

class _FootnoteEmbedBuilder extends q.EmbedBuilder {
  const _FootnoteEmbedBuilder(this.controller);
  final RichMarkdownController controller;
  @override
  String get key => richMarkdownFootnoteEmbedType;
  @override
  bool get expanded => false;
  @override
  Widget build(BuildContext context, q.EmbedContext embedContext) {
    final data = _payload(embedContext.node.value.data);
    final id = '${data['id'] ?? ''}';
    final number = _footnoteNumber(controller, id);
    return Semantics(
      button: true,
      label: 'Fußnote $number öffnen',
      child: InkWell(
        onTap: () => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          sheetAnimationStyle: AppScope.of(context).eInk
              ? AnimationStyle.noAnimation
              : null,
          builder: (context) => DraggableScrollableSheet(
            expand: false,
            initialChildSize: .45,
            minChildSize: .25,
            maxChildSize: .85,
            builder: (context, scroll) => ListView(
              controller: scroll,
              padding: const EdgeInsets.all(20),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Fußnote $number',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Zurück zum Text',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                _MarkdownPreview(
                  _footnotes(controller)[id] ??
                      'Diese Fußnote enthält noch keinen Text.',
                ),
              ],
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: Text(
            '[$number]',
            style: embedContext.textStyle.copyWith(
              fontSize: (embedContext.textStyle.fontSize ?? 19) * .72,
              color: AkribosThemeTokens.of(context).accent,
            ),
          ),
        ),
      ),
    );
  }
}

class _SourceEmbedBuilder extends q.EmbedBuilder {
  const _SourceEmbedBuilder(this.controller);
  final RichMarkdownController controller;
  @override
  String get key => richMarkdownSourceEmbedType;
  @override
  Widget build(BuildContext context, q.EmbedContext embedContext) {
    final data = _payload(embedContext.node.value.data);
    final raw = '${data['raw'] ?? ''}';
    final kind = '${data['kind'] ?? 'unsupported'}';
    if (kind == 'rule') return const Divider(height: 32);
    final title = switch (kind) {
      'table' => 'Tabelle',
      'footnote' =>
        'Fußnote ${_footnoteNumber(controller, '${data['id'] ?? ''}')}',
      'image' => 'Abbildung',
      'html' => 'Formatierter Abschnitt',
      _ => 'Abschnitt',
    };
    final body = kind == 'footnote' ? _footnoteBody(raw) : raw;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: embedContext.readOnly
          ? EdgeInsets.zero
          : const EdgeInsets.all(12),
      decoration: embedContext.readOnly
          ? null
          : BoxDecoration(
              border: Border.all(color: AkribosThemeTokens.of(context).line),
              borderRadius: BorderRadius.circular(9),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!embedContext.readOnly || kind == 'footnote')
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
                if (!embedContext.readOnly)
                  IconButton(
                    tooltip: '$title bearbeiten',
                    icon: const Icon(Icons.edit_outlined, size: 19),
                    onPressed: () async {
                      final String? result;
                      if (kind == 'table' && _TableSource.parse(raw) != null) {
                        result = await showDialog<String>(
                          context: context,
                          builder: (_) => _TableDialog(source: raw),
                        );
                      } else if (kind == 'footnote') {
                        final edited = await showDialog<String>(
                          context: context,
                          builder: (_) =>
                              _TextBlockDialog(title: title, source: body),
                        );
                        final prefix =
                            RegExp(r'^ {0,3}\[\^[^\]]+\]:[ \t]?')
                                .firstMatch(raw)
                                ?.group(0) ??
                            '[^${data['id']}]: ';
                        result = edited == null
                            ? null
                            : edited == body
                            ? raw
                            : '$prefix${edited.split('\n').join('\n    ')}\n';
                      } else {
                        result = await showDialog<String>(
                          context: context,
                          builder: (_) =>
                              _SourceDialog(title: title, source: raw),
                        );
                      }
                      if (result == null ||
                          result == raw ||
                          controller.quill.readOnly ||
                          embedContext.node.parent == null) {
                        return;
                      }
                      final offset = embedContext.node.documentOffset;
                      controller.quill.replaceText(
                        offset,
                        1,
                        q.Embeddable(
                          richMarkdownSourceEmbedType,
                          jsonEncode({...data, 'raw': result}),
                        ),
                        TextSelection.collapsed(offset: offset + 1),
                      );
                    },
                  ),
              ],
            ),
          if (kind == 'image')
            const Text(
              'Abbildung im Dokument erhalten. Bilder werden hier nicht automatisch geladen.',
            )
          else
            _MarkdownPreview(body),
        ],
      ),
    );
  }
}

class _UnknownEmbedBuilder extends q.EmbedBuilder {
  @override
  String get key => 'unknown';
  @override
  Widget build(BuildContext context, q.EmbedContext embedContext) =>
      const Text('Eingebetteter Inhalt bleibt im Dokument erhalten.');
}

class _MarkdownPreview extends StatelessWidget {
  const _MarkdownPreview(this.source);
  final String source;
  @override
  Widget build(BuildContext context) => HtmlContent(
    html: md.markdownToHtml(
      source,
      extensionSet: md.ExtensionSet.gitHubFlavored,
      encodeHtml: false,
    ),
  );
}

class _LinkDialog extends StatefulWidget {
  const _LinkDialog({required this.value});
  final String value;
  @override
  State<_LinkDialog> createState() => _LinkDialogState();
}

class _LinkDialogState extends State<_LinkDialog> {
  late final _text = TextEditingController(text: widget.value);
  String? _error;
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _text.text.trim();
    final uri = Uri.tryParse(value);
    if (value.isNotEmpty &&
        (uri == null ||
            uri.userInfo.isNotEmpty ||
            (!value.startsWith('/') &&
                !value.startsWith('#') &&
                !['https', 'http', 'mailto'].contains(uri.scheme)))) {
      setState(
        () => _error = 'Bitte eine https://-Adresse, Bibelstelle als /Joh3,16 oder einen Dokumentlink eingeben.',
      );
      return;
    }
    Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Link bearbeiten'),
    content: TextField(
      controller: _text,
      autofocus: true,
      keyboardType: TextInputType.url,
      decoration: InputDecoration(labelText: 'Adresse', errorText: _error),
      onSubmitted: (_) => _submit(),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Abbrechen'),
      ),
      if (widget.value.isNotEmpty)
        TextButton(
          onPressed: () => Navigator.pop(context, ''),
          child: const Text('Link entfernen'),
        ),
      FilledButton(onPressed: _submit, child: const Text('Übernehmen')),
    ],
  );
}

class _TextBlockDialog extends StatefulWidget {
  const _TextBlockDialog({required this.title, required this.source});
  final String title, source;
  @override
  State<_TextBlockDialog> createState() => _TextBlockDialogState();
}

class _TextBlockDialogState extends State<_TextBlockDialog> {
  late final _rich = RichMarkdownController(markdown: widget.source);
  @override
  void dispose() {
    _rich.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.all(16),
    child: SizedBox(
      width: 680,
      height: math.min(520, MediaQuery.sizeOf(context).height * .75),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: 'Abbrechen',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          Expanded(
            child: RichMarkdownEditor(controller: _rich, readOnly: false),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: () => Navigator.pop(context, _rich.markdown),
                child: const Text('Übernehmen'),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Explicit source editing is reserved for structures with no lossless native
/// editing model. Merely opening/closing this dialog does not rewrite source.
class _SourceDialog extends StatefulWidget {
  const _SourceDialog({required this.title, required this.source});
  final String title, source;
  @override
  State<_SourceDialog> createState() => _SourceDialogState();
}

class _SourceDialogState extends State<_SourceDialog> {
  late final _text = TextEditingController(text: widget.source);
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SizedBox(
      width: 600,
      child: TextField(
        controller: _text,
        minLines: 5,
        maxLines: 14,
        decoration: const InputDecoration(
          labelText: 'Originalformat bearbeiten',
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Abbrechen'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _text.text),
        child: const Text('Übernehmen'),
      ),
    ],
  );
}

class _TableSource {
  _TableSource(this.lines, this.rows, this.cells);
  final List<String> lines;
  final List<int> rows;
  final List<List<String>> cells;
  static _TableSource? parse(String source) {
    final lines = source.split('\n');
    final rows = <int>[];
    final cells = <List<String>>[];
    var separator = false;
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;
      final values = _split(line);
      if (values == null || values.isEmpty) return null;
      if (!separator &&
          cells.length == 1 &&
          values.every(
            (value) => RegExp(r'^\s*:?-{3,}:?\s*$').hasMatch(value),
          )) {
        separator = true;
        continue;
      }
      rows.add(i);
      cells.add(values);
    }
    if (!separator ||
        cells.isEmpty ||
        cells.any((row) => row.length != cells.first.length)) {
      return null;
    }
    return _TableSource(lines, rows, cells);
  }

  static List<String>? _split(String source) {
    final result = <String>[];
    var cell = StringBuffer();
    var escaped = false;
    var ticks = 0;
    for (var i = 0; i < source.length; i++) {
      final character = source[i];
      if (character == '\\' && !escaped) {
        escaped = true;
        cell.write(character);
        continue;
      }
      if (character == '`' && !escaped) {
        var end = i + 1;
        while (end < source.length && source[end] == '`') {
          end++;
        }
        final run = end - i;
        if (ticks == 0) {
          ticks = run;
        } else if (ticks == run) {
          ticks = 0;
        }
        cell.write(source.substring(i, end));
        i = end - 1;
        continue;
      }
      if (character == '|' && !escaped && ticks == 0) {
        result.add(cell.toString());
        cell = StringBuffer();
      } else {
        cell.write(character);
      }
      escaped = false;
    }
    result.add(cell.toString());
    if (result.first.trim().isEmpty) result.removeAt(0);
    if (result.isNotEmpty && result.last.trim().isEmpty) result.removeLast();
    return result;
  }

  String withCells(List<List<String>> next) {
    final output = List<String>.of(lines);
    for (var r = 0; r < cells.length; r++) {
      if (List.generate(
        cells[r].length,
        (c) => cells[r][c].trim() == next[r][c],
      ).every((same) => same)) {
        continue;
      }
      final original = lines[rows[r]];
      final prefix = RegExp(r'^\s*').firstMatch(original)!.group(0)!;
      final suffix = RegExp(r'\s*$').firstMatch(original)!.group(0)!;
      final edited = List.generate(cells[r].length, (c) {
        final old = cells[r][c];
        if (old.trim() == next[r][c]) return old;
        final leading = RegExp(r'^\s*').firstMatch(old)!.group(0)!;
        final trailing = RegExp(r'\s*$').firstMatch(old)!.group(0)!;
        return '$leading${next[r][c].replaceAll('\n', '<br>').replaceAll(RegExp(r'(?<!\\)\|'), r'\|')}$trailing';
      }).join('|');
      output[rows[r]] =
          '$prefix${original.trimLeft().startsWith('|') ? '|' : ''}$edited${original.trimRight().endsWith('|') ? '|' : ''}$suffix';
    }
    return output.join('\n');
  }
}

class _TableDialog extends StatefulWidget {
  const _TableDialog({required this.source});
  final String source;
  @override
  State<_TableDialog> createState() => _TableDialogState();
}

class _TableDialogState extends State<_TableDialog> {
  late final _table = _TableSource.parse(widget.source)!;
  late final _cells = _table.cells
      .map((row) => row.map((cell) => cell.trim()).toList())
      .toList();
  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.all(16),
    child: SizedBox(
      width: 760,
      height: math.min(540, MediaQuery.sizeOf(context).height * .8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Tabelle bearbeiten',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: 'Abbrechen',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text('Tippe eine Zelle an, um ihren Inhalt zu bearbeiten.'),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Table(
                  defaultColumnWidth: const FixedColumnWidth(180),
                  border: TableBorder.all(
                    color: AkribosThemeTokens.of(context).line,
                  ),
                  children: List.generate(
                    _cells.length,
                    (r) => TableRow(
                      children: List.generate(
                        _cells[r].length,
                        (c) => InkWell(
                          onTap: () async {
                            final value = await showDialog<String>(
                              context: context,
                              builder: (_) => _TextBlockDialog(
                                title: 'Zeile ${r + 1}, Spalte ${c + 1}',
                                source: _cells[r][c],
                              ),
                            );
                            if (value != null && mounted) {
                              setState(() => _cells[r][c] = value.trim());
                            }
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: _cells[r][c].isEmpty
                                ? const Text('Leere Zelle')
                                : _MarkdownPreview(_cells[r][c]),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: () =>
                    Navigator.pop(context, _table.withCells(_cells)),
                child: const Text('Übernehmen'),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
