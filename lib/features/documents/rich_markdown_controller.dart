// Clipboard configuration is experimental upstream; pinned Quill 11.6.0 is covered by tests.
// ignore_for_file: experimental_member_use

import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_quill/flutter_quill.dart' as q;
import 'package:flutter_quill/quill_delta.dart';
import 'package:markdown/markdown.dart' as md;

/// Embed data is a JSON string, never HTML to execute or a URL to fetch.
/// Source: {raw, kind, label, id?}. Footnote reference: {raw, id}.
const richMarkdownSourceEmbedType = 'akribos-source';
const richMarkdownFootnoteEmbedType = 'akribos-footnote-ref';
const _sourceId = 'akribos-source-id';
const _sourcePart = 'akribos-source-part';
const _listNumber = 'akribos-list-number';
const _listContinuation = 'akribos-list-continuation';
const _listLoose = 'akribos-list-loose';
const _codeLanguage = 'akribos-code-language';
const _linkTitle = 'akribos-link-title';

/// Projects Markdown into Quill without making Quill the persisted source.
///
/// Each original block keeps its raw source and its projected Delta. Unchanged
/// blocks are emitted verbatim, even after changes elsewhere. Unrepresentable
/// blocks remain explicit source embeds. No conversion occurs merely on opening,
/// selecting text, changing readOnly or recovering a draft. Export is synchronous
/// and cached; callers can safely capture an immutable string before an await.
class RichMarkdownController extends ChangeNotifier {
  RichMarkdownController({required String markdown}) {
    final delta = _decode(markdown);
    quill = q.QuillController(
      document: q.Document.fromDelta(delta),
      selection: const TextSelection.collapsed(offset: 0),
      config: q.QuillControllerConfig(
        clipboardConfig: q.QuillClipboardConfig(
          enableExternalRichPaste: false,
          onImagePaste: (_) async => null,
          onGifPaste: (_) async => null,
        ),
      ),
    );
    _lastDelta = quill.document.toDelta();
    _cachedMarkdown = markdown;
    _listen();
    quill.addListener(_checkContent);
  }

  late final q.QuillController quill;
  final Map<String, _OriginalBlock> _originals = {};
  late Delta _lastDelta;
  Delta? _serializedDelta;
  String? _cachedMarkdown;
  StreamSubscription<q.DocChange>? _subscription;
  int _nextId = 0;
  bool _replacing = false;
  bool _disposed = false;

  String get markdown {
    // Document.compose can precede Quill's asynchronous document change event.
    // Always compare the current snapshot, so flush/save never misses that edit.
    final current = quill.document.toDelta();
    if (current != (_serializedDelta ?? _lastDelta)) {
      _cachedMarkdown = null;
    }
    _serializedDelta = current;
    return _cachedMarkdown ??= _encode(current);
  }

  void _listen() {
    final document = quill.document;
    _subscription = document.changes.listen((_) {
      if (!_disposed && identical(document, quill.document)) {
        _checkContent();
      }
    });
  }

  void _checkContent() {
    if (_disposed || _replacing) return;
    final current = quill.document.toDelta();
    if (current == _lastDelta) return;
    _lastDelta = current;
    _cachedMarkdown = null;
    notifyListeners();
  }

  void setMarkdown(String source, {bool notify = false}) {
    if (source == markdown) return;
    final oldDocument = quill.document;
    _replacing = true;
    _subscription?.cancel();
    _originals.clear();
    quill.document = q.Document.fromDelta(_decode(source));
    _lastDelta = quill.document.toDelta();
    _serializedDelta = _lastDelta;
    _cachedMarkdown = source;
    _listen();
    _replacing = false;
    oldDocument.close();
    if (notify) notifyListeners();
  }

  /// Inserts Markdown at the selection. Inline fragments stay within the current
  /// paragraph; block fragments retain their own block/source representation.
  void insertMarkdown(String fragment) {
    if (fragment.isEmpty) return;
    final selection = quill.selection;
    final start = selection.start.clamp(0, quill.document.length - 1);
    final length = (selection.end - start).clamp(
      0,
      quill.document.length - start - 1,
    );
    final parsed = _decode(fragment);
    final lines = _lines(parsed);
    final inline =
        !fragment.contains('\n') &&
        lines.length == 1 &&
        lines.single.blockAttributes.isEmpty &&
        !lines.single.hasSource;
    var insertion = inline ? lines.single.content : parsed;
    if (!inline &&
        start > 0 &&
        quill.document.toPlainText()[start - 1] != '\n' &&
        !(insertion.first.data is String &&
            (insertion.first.data as String).startsWith('\n'))) {
      insertion = (Delta()..insert('\n')).concat(insertion);
    }
    quill.replaceText(
      start,
      length,
      insertion,
      TextSelection.collapsed(offset: start + insertion.length),
    );
  }

  /// Inserts the reference and its definition in a single document transaction.
  void insertFootnote({String? id, String content = ''}) {
    final source = markdown;
    final used = RegExp(r'\[\^([^\]\s]+)\]')
        .allMatches(source)
        .map((match) => match[1]!)
        .toSet();
    var number = 1;
    while (used.contains('$number')) {
      number++;
    }
    final label =
        id != null && RegExp(r'^[\w-]+$').hasMatch(id) && !used.contains(id)
        ? id
        : '$number';
    final selection = quill.selection;
    final start = selection.start.clamp(0, quill.document.length - 1);
    final count = (selection.end - start).clamp(
      0,
      quill.document.length - start - 1,
    );
    final definition = '[^$label]: ${content.replaceAll('\n', '\n    ')}\n';
    final change = Delta()
      ..retain(start)
      ..delete(count)
      ..insert({
        richMarkdownFootnoteEmbedType: jsonEncode({
          'raw': '[^$label]',
          'id': label,
        }),
      });
    change.retain(quill.document.length - start - count - 1);
    change.insert('\n');
    change.insert({
      richMarkdownSourceEmbedType: jsonEncode({
        'raw': definition,
        'kind': 'footnote',
        'label': 'Fußnote $label',
        'id': label,
      }),
    });
    change.insert('\n');
    quill.compose(
      change,
      TextSelection.collapsed(offset: start + 1),
      q.ChangeSource.local,
    );
  }

  Delta _decode(String source) {
    final result = Delta();
    final blocks = <_SourceBlock>[];
    var leading = '';
    for (final raw in _sourceBlocks(source)) {
      if (raw.trim().isEmpty) {
        if (blocks.isEmpty) {
          leading += raw;
        } else {
          blocks.last.separator += raw;
        }
      } else {
        blocks.add(_SourceBlock(raw));
      }
    }
    for (final entry in blocks) {
      final raw = entry.raw;
      final prefix = identical(entry, blocks.first) ? leading : '';
      final id = '${_nextId++}';
      final block = _project(raw);
      final lines = _lines(block);
      for (var i = 0; i < lines.length; i++) {
        for (final operation in lines[i].content.toList()) {
          result.push(operation);
        }
        result.insert('\n', {
          ...lines[i].attributes,
          _sourceId: id,
          _sourcePart: i,
        });
      }
      _originals[id] = _OriginalBlock(
        '$prefix$raw${entry.separator}',
        lines.map(_fingerprint).toList(),
        leading: prefix,
        separator: entry.separator,
      );
    }
    if (result.isEmpty) {
      final id = '${_nextId++}';
      _originals[id] = _OriginalBlock(source, [
        _fingerprint(_Line(Delta(), {})),
      ]);
      result.insert('\n', {_sourceId: id, _sourcePart: 0});
    }
    return result;
  }

  String _encode(Delta delta) {
    final lines = _lines(delta);
    final out = StringBuffer();
    var i = 0;
    while (i < lines.length) {
      final line = lines[i];
      final original = _originals[line.attributes[_sourceId]];
      if (original != null &&
          line.attributes[_sourcePart] == 0 &&
          i + original.fingerprints.length <= lines.length &&
          List.generate(original.fingerprints.length, (n) => n).every(
            (n) =>
                lines[i + n].attributes[_sourceId] ==
                    line.attributes[_sourceId] &&
                lines[i + n].attributes[_sourcePart] == n &&
                _fingerprint(lines[i + n]) == original.fingerprints[n],
          )) {
        out.write(original.raw);
        if (i + original.fingerprints.length < lines.length &&
            !original.raw.endsWith('\n') &&
            !original.raw.endsWith('\r')) {
          out.write('\n');
        }
        i += original.fingerprints.length;
        continue;
      }
      if (original != null && line.attributes[_sourcePart] == 0) {
        out.write(original.leading);
      }
      if (line.attributes['list'] != null) {
        final listLines = <_Line>[];
        final sourceId = line.attributes[_sourceId];
        while (i < lines.length &&
            lines[i].attributes[_sourceId] == sourceId &&
            (lines[i].attributes['list'] != null ||
                lines[i].attributes[_listContinuation] != null)) {
          listLines.add(lines[i++]);
        }
        out.write(_encodeListLines(listLines));
        if (original != null &&
            (i == lines.length || lines[i].attributes[_sourceId] != sourceId)) {
          out.write(original.separator);
        }
        continue;
      }
      if (line.attributes['code-block'] == true) {
        final code = <String>[];
        final language = line.attributes[_codeLanguage] as String? ?? '';
        while (i < lines.length &&
            lines[i].attributes['code-block'] == true &&
            lines[i].attributes[_sourceId] == line.attributes[_sourceId]) {
          code.add(_plainText(lines[i].content));
          i++;
        }
        final longest = RegExp(r'`+')
            .allMatches(code.join('\n'))
            .fold<int>(
              2,
              (length, match) =>
                  match[0]!.length > length ? match[0]!.length : length,
            );
        final fence = '`' * (longest + 1);
        out.write('$fence$language\n${code.join('\n')}\n$fence\n');
        out.write(original?.separator ?? '');
        continue;
      }
      final value = _encodeLine(line);
      out.write(value);
      // Every Quill line has a terminal newline; a source embed already owns
      // its exact terminator, and the final originally unterminated line can
      // stay unterminated after a normal edit.
      if (line.hasSource &&
          i < lines.length - 1 &&
          !value.endsWith('\n') &&
          !value.endsWith('\r')) {
        out.write('\n');
      }
      if (!line.hasSource) {
        final last = i == lines.length - 1;
        final keepUnterminated =
            last &&
            original != null &&
            !original.raw.endsWith('\n') &&
            !original.raw.endsWith('\r');
        if (!keepUnterminated) out.write('\n');
      }
      final next = i + 1 < lines.length ? lines[i + 1] : null;
      final endsOriginal =
          next == null ||
          next.attributes[_sourceId] != line.attributes[_sourceId];
      final separator = endsOriginal ? original?.separator ?? '' : '';
      out.write(separator);
      // Enter creates a real new paragraph. Markdown needs a blank separator
      // between plain paragraphs even though Quill needs only one newline.
      if (separator.isEmpty &&
          next != null &&
          !line.hasSource &&
          !next.hasSource &&
          line.blockAttributes.isEmpty &&
          next.blockAttributes.isEmpty) {
        out.write('\n');
      }
      i++;
    }
    return out.toString();
  }

  @override
  void dispose() {
    _disposed = true;
    _subscription?.cancel();
    quill.removeListener(_checkContent);
    quill.dispose();
    super.dispose();
  }
}

class _SourceBlock {
  _SourceBlock(this.raw);
  final String raw;
  String separator = '';
}

class _OriginalBlock {
  const _OriginalBlock(
    this.raw,
    this.fingerprints, {
    this.leading = '',
    this.separator = '',
  });
  final String raw;
  final List<String> fingerprints;
  final String leading;
  final String separator;
}

class _Line {
  _Line(this.content, this.attributes);
  final Delta content;
  final Map<String, dynamic> attributes;
  Map<String, dynamic> get blockAttributes => Map.fromEntries(
    attributes.entries.where(
      (entry) => q.Attribute.blockKeys.contains(entry.key),
    ),
  );
  bool get hasSource => content.toList().any(
    (operation) =>
        operation.data is Map &&
        (operation.data as Map).containsKey(richMarkdownSourceEmbedType),
  );
}

List<_Line> _lines(Delta delta) {
  final lines = <_Line>[];
  var content = Delta();
  for (final operation in delta.toList()) {
    final value = operation.data;
    if (value is! String) {
      content.push(operation);
      continue;
    }
    final pieces = value.split('\n');
    for (var index = 0; index < pieces.length; index++) {
      if (pieces[index].isNotEmpty) {
        content.insert(pieces[index], operation.attributes);
      }
      if (index < pieces.length - 1) {
        lines.add(_Line(content, operation.attributes ?? {}));
        content = Delta();
      }
    }
  }
  if (content.isNotEmpty) lines.add(_Line(content, {}));
  return lines;
}

String _fingerprint(_Line line) {
  final normalized = Delta();
  for (final op in line.content.toList()) {
    final attrs = op.attributes;
    normalized.insert(op.data, attrs == null || attrs.isEmpty ? null : attrs);
  }
  Object? ordered(Object? value) {
    if (value is Map) {
      final keys = value.keys.map((key) => key.toString()).toList()..sort();
      return {for (final key in keys) key: ordered(value[key])};
    }
    if (value is List) return value.map(ordered).toList();
    return value;
  }

  return jsonEncode(
    ordered({
      'content': normalized.toJson(),
      'attributes': Map.fromEntries(
        line.attributes.entries.where(
          (entry) => entry.key != _sourceId && entry.key != _sourcePart,
        ),
      ),
    }),
  );
}

Iterable<String> _sourceBlocks(String source) sync* {
  final lines = RegExp(r'[^\r\n]*(?:\r\n|\r|\n|$)')
      .allMatches(source)
      .map((match) => match[0]!)
      .where((line) => line.isNotEmpty)
      .toList();
  var i = 0;
  while (i < lines.length) {
    final start = i;
    final text = lines[i].trimRight();
    final listEnd = _listBlockEnd(lines, i);
    final fence = RegExp(r'^ {0,3}(`{3,}|~{3,})').firstMatch(text);
    if (listEnd != null) {
      i = listEnd;
    } else if (fence != null) {
      final token = fence[1]!;
      i++;
      while (i < lines.length) {
        final current = lines[i++].trim();
        if (RegExp('^${RegExp.escape(token[0])}{${token.length},}\\s*\$')
            .hasMatch(current)) {
          break;
        }
      }
    } else if (RegExp(r'^ {0,3}\[\^[^\]]+\]:').hasMatch(text)) {
      i++;
      while (i < lines.length) {
        if (RegExp(r'^(?: {4}|\t)').hasMatch(lines[i])) {
          i++;
          continue;
        }
        if (lines[i].trim().isEmpty &&
            i + 1 < lines.length &&
            RegExp(r'^(?: {4}|\t)').hasMatch(lines[i + 1])) {
          i++;
          continue;
        }
        break;
      }
    } else if (text.isEmpty || RegExp(r'^ {0,3}#{1,6}\s').hasMatch(text)) {
      i++;
    } else {
      i++;
      while (i < lines.length && lines[i].trim().isNotEmpty) {
        if (_listBlockEnd(lines, i, interruptParagraph: true) != null) break;
        if (RegExp(r'^ {0,3}(?:#{1,6}\s|`{3,}|~{3,}|\[\^[^\]]+\]:)')
            .hasMatch(lines[i])) {
          break;
        }
        i++;
      }
    }
    yield lines.sublist(start, i).join();
  }
}

/// Let Markdown determine whether indentation belongs to a list or to code.
/// Splitting on blank lines first loses that parent context (notably Turndown's
/// `-   parent\n\n    -   child` output). Public parser APIs also handle varying
/// ordered-marker widths and the exact termination rules for loose lists.
int? _listBlockEnd(
  List<String> rawLines,
  int start, {
  bool interruptParagraph = false,
}) {
  if (!RegExp(r'^ {0,3}(?:[-+*]|\d{1,9}[.)])(?:[ \t]+|$)')
      .hasMatch(rawLines[start].trimRight())) {
    return null;
  }
  final lines = rawLines
      .skip(start)
      .map((raw) => md.Line(raw.replaceFirst(RegExp(r'[\r\n]+$'), '')))
      .toList();
  final parser = md.BlockParser(lines, _markdownDocument());
  const syntaxes = <md.ListSyntax>[
    md.UnorderedListWithCheckboxSyntax(),
    md.OrderedListWithCheckboxSyntax(),
  ];
  for (final syntax in syntaxes) {
    if (!syntax.canParse(parser) ||
        (interruptParagraph && !syntax.canEndBlock(parser))) {
      continue;
    }
    syntax.parse(parser);
    var consumed = parser.isDone ? lines.length : lines.indexOf(parser.current);
    // Trailing blank lines are raw separators, not visible empty list items.
    while (consumed > 1 && rawLines[start + consumed - 1].trim().isEmpty) {
      consumed--;
    }
    return start + consumed;
  }
  return null;
}

Delta _sourceEmbed(String raw, String kind, String label, {String? id}) =>
    Delta()
      ..insert({
        richMarkdownSourceEmbedType: jsonEncode({
          'raw': raw,
          'kind': kind,
          'label': label,
          ...?id == null ? null : {'id': id},
        }),
      })
      ..insert('\n');

md.Document _markdownDocument() => md.Document(
  extensionSet: md.ExtensionSet.gitHubFlavored,
  encodeHtml: false,
  inlineSyntaxes: [_FootnoteSyntax(), _HtmlStyleSyntax(), _BreakSyntax()],
);

Delta _project(String raw) {
  if (raw.trim().isEmpty) return Delta()..insert('\n');
  final footnote = RegExp(r'^ {0,3}\[\^([^\]]+)\]:').firstMatch(raw);
  if (footnote != null) {
    return _sourceEmbed(
      raw,
      'footnote',
      'Fußnote ${footnote[1]}',
      id: footnote[1],
    );
  }
  if (RegExp(r'!\[[^\]]*\]\(|<img\b', caseSensitive: false).hasMatch(raw)) {
    return _sourceEmbed(raw, 'image', 'Bildquelle');
  }
  // Arbitrary HTML and reference-link definitions stay opaque. The supported
  // inline HTML subset has explicit semantic parsers below.
  final withoutStyles = raw.replaceAll(RegExp(r'</?(?:u|mark)>|<br\s*/?>'), '');
  if (RegExp(r'</?[A-Za-z][^>]*>|<!--').hasMatch(withoutStyles) ||
      RegExp(r'^ {0,3}\[[^\]]+\]:', multiLine: true).hasMatch(raw) ||
      RegExp(r'\[[^\]]+\]\s*\[[^\]]*\]').hasMatch(raw)) {
    return _sourceEmbed(raw, 'html', 'Erweiterter Inhalt');
  }
  final nodes = _markdownDocument().parseLines(
    raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n'),
  );
  if (nodes.any((node) => node is md.Element && node.tag == 'table')) {
    return _sourceEmbed(raw, 'table', 'Tabelle');
  }
  if (nodes.any((node) => node is md.Element && node.tag == 'hr')) {
    return _sourceEmbed(raw, 'rule', 'Trennlinie');
  }
  final delta = Delta();
  try {
    for (final node in nodes) {
      _appendBlock(node, delta);
    }
    return delta.isEmpty
        ? _sourceEmbed(raw, 'unsupported', 'Markdown-Inhalt')
        : delta;
  } on _UnsupportedMarkdown {
    return _sourceEmbed(raw, 'unsupported', 'Markdown-Inhalt');
  }
}

class _UnsupportedMarkdown implements Exception {}

void _appendBlock(
  md.Node node,
  Delta delta, {
  int indent = 0,
  Map<String, dynamic> block = const {},
}) {
  if (node is! md.Element) throw _UnsupportedMarkdown();
  final children = node.children ?? [];
  switch (node.tag) {
    case 'p':
    case 'h1':
    case 'h2':
    case 'h3':
    case 'h4':
    case 'h5':
    case 'h6':
      for (final child in children) {
        _appendInline(child, delta);
      }
      delta.insert('\n', {
        ...block,
        if (node.tag.startsWith('h')) 'header': int.parse(node.tag[1]),
      });
    case 'ul':
    case 'ol':
      var ordinal = int.tryParse(node.attributes['start'] ?? '') ?? 1;
      final loose = children.whereType<md.Element>().any(
        (item) => (item.children ?? []).any(
          (part) => part is md.Element && part.tag == 'p',
        ),
      );
      for (final item in children) {
        if (item is! md.Element || item.tag != 'li') {
          throw _UnsupportedMarkdown();
        }
        final itemNumber = ordinal++;
        var firstParagraph = true;
        final pending = <md.Node>[];
        void paragraph(List<md.Node> content) {
          final inline = List<md.Node>.of(content);
          // Markdown list-marker padding can remain in the AST text (e.g.
          // Turndown emits '-   '). It is syntax, not visible item content.
          while (inline.isNotEmpty && inline.first is md.Text) {
            final text = (inline.first as md.Text).text.replaceFirst(
              RegExp(r'^[ \t]+'),
              '',
            );
            inline.removeAt(0);
            if (text.isNotEmpty) {
              inline.insert(0, md.Text(text));
              break;
            }
          }
          var list = node.tag == 'ol' ? 'ordered' : 'bullet';
          if (inline.isNotEmpty &&
              inline.first is md.Element &&
              (inline.first as md.Element).tag == 'input') {
            final input = inline.removeAt(0) as md.Element;
            list = input.attributes.containsKey('checked')
                ? 'checked'
                : 'unchecked';
          }
          for (final part in inline) {
            _appendInline(part, delta);
          }
          delta.insert(
            '\n',
            firstParagraph
                ? {
                    'list': list,
                    if (indent > 0) 'indent': indent,
                    if (list == 'ordered') _listNumber: itemNumber,
                    if (loose) _listLoose: true,
                  }
                : {'indent': indent + 1, _listContinuation: indent},
          );
          firstParagraph = false;
        }

        void flush() {
          if (pending.isNotEmpty) {
            paragraph(pending);
            pending.clear();
          }
        }

        for (final part in item.children ?? <md.Node>[]) {
          if (part is md.Element && part.tag == 'p') {
            flush();
            paragraph(part.children ?? []);
          } else if (part is md.Element &&
              (part.tag == 'ul' || part.tag == 'ol')) {
            flush();
            if (firstParagraph) paragraph([]);
            _appendBlock(part, delta, indent: indent + 1);
          } else if (part is md.Element && part.tag == 'pre') {
            flush();
            if (firstParagraph) paragraph([]);
            _appendBlock(
              part,
              delta,
              block: {'indent': indent + 1, _listContinuation: indent},
            );
          } else {
            pending.add(part);
          }
        }
        flush();
        if (firstParagraph) paragraph([]);
      }
    case 'blockquote':
      if (children.any((child) => child is! md.Element || child.tag != 'p')) {
        throw _UnsupportedMarkdown();
      }
      for (final child in children) {
        _appendBlock(child, delta, block: {'blockquote': true});
      }
    case 'pre':
      if (children.length != 1 || children.single is! md.Element) {
        throw _UnsupportedMarkdown();
      }
      final code = children.single as md.Element;
      final language = (code.attributes['class'] ?? '').replaceFirst(
        'language-',
        '',
      );
      final text = code.textContent;
      final lines =
          (text.endsWith('\n') ? text.substring(0, text.length - 1) : text)
              .split('\n');
      for (final line in lines) {
        if (line.isNotEmpty) delta.insert(line);
        delta.insert('\n', {
          ...block,
          'code-block': true,
          if (language.isNotEmpty) _codeLanguage: language,
        });
      }
    default:
      throw _UnsupportedMarkdown();
  }
}

void _appendInline(
  md.Node node,
  Delta delta, [
  Map<String, dynamic> attributes = const {},
]) {
  if (node is md.Text) {
    final text = node.text.replaceAll('\n', ' ');
    if (text.isNotEmpty) {
      delta.insert(text, attributes.isEmpty ? null : attributes);
    }
    return;
  }
  final element = node as md.Element;
  if (element.tag == richMarkdownFootnoteEmbedType) {
    delta.insert({
      richMarkdownFootnoteEmbedType: jsonEncode(element.attributes),
    }, attributes.isEmpty ? null : attributes);
    return;
  }
  if (element.tag == 'br') {
    delta.insert('\u2028');
    return;
  }
  final next = {...attributes};
  switch (element.tag) {
    case 'strong':
      next['bold'] = true;
    case 'em':
      next['italic'] = true;
    case 'del':
    case 's':
      next['strike'] = true;
    case 'code':
      next['code'] = true;
    case 'u':
      next['underline'] = true;
    case 'mark':
      next['background'] = '#fff59d';
    case 'a':
      next['link'] = element.attributes['href'] ?? '';
      if (element.attributes['title'] != null) {
        next[_linkTitle] = element.attributes['title'];
      }
    default:
      throw _UnsupportedMarkdown();
  }
  for (final child in element.children ?? <md.Node>[]) {
    _appendInline(child, delta, next);
  }
}

class _FootnoteSyntax extends md.InlineSyntax {
  _FootnoteSyntax() : super(r'\[\^([^\]\s]+)\]');
  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(
      md.Element.empty(richMarkdownFootnoteEmbedType)
        ..attributes.addAll({'raw': match[0]!, 'id': match[1]!}),
    );
    return true;
  }
}

class _HtmlStyleSyntax extends md.InlineSyntax {
  _HtmlStyleSyntax() : super(r'<(u|mark)>([\s\S]*?)</\1>');
  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(
      md.Element(match[1]!, _markdownDocument().parseInline(match[2]!)),
    );
    return true;
  }
}

class _BreakSyntax extends md.InlineSyntax {
  _BreakSyntax() : super(r'<br\s*/?>');
  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(md.Element.empty('br'));
    return true;
  }
}

String _plainText(Delta delta) => delta
    .toList()
    .map((op) => op.data is String ? op.data as String : '')
    .join();
String _escape(String text) => text
    .replaceAllMapped(
      RegExp(r'[\\`*_\[\]<>!#~|+=\-]'),
      (match) => '\\${match[0]}',
    )
    .replaceAll('\u2028', '<br>');

String _encodeLine(_Line line) {
  final body = _encodeInline(line.content);
  if (line.hasSource) return body;
  final attrs = line.attributes;
  final indent = '  ' * ((attrs['indent'] as num?)?.toInt() ?? 0).clamp(0, 12);
  if (attrs['header'] is num) {
    return '${'#' * (attrs['header'] as num).toInt().clamp(1, 6)} $body';
  }
  if (attrs['blockquote'] == true) return '> $body';
  return switch (attrs['list']) {
    'bullet' => '$indent- $body',
    'ordered' => '$indent${attrs[_listNumber] ?? 1}. $body',
    'checked' => '$indent- [x] $body',
    'unchecked' => '$indent- [ ] $body',
    _ => body.replaceFirstMapped(
      RegExp(r'^( {0,3}\d+)([.)])(\s)'),
      (match) => '${match[1]}\\${match[2]}${match[3]}',
    ),
  };
}

String _encodeListLines(List<_Line> lines) {
  final output = StringBuffer();
  final contentColumns = <int, int>{};
  var endsWithNewline = false;
  var endsWithBlankLine = false;
  void write(String value) {
    output.write(value);
    if (value.isEmpty) return;
    endsWithBlankLine =
        value.endsWith('\n\n') || (value == '\n' && endsWithNewline);
    endsWithNewline = value.endsWith('\n');
  }

  void blankLine() {
    if (output.isNotEmpty && !endsWithBlankLine) write('\n');
  }

  var index = 0;
  while (index < lines.length) {
    final line = lines[index];
    final attributes = line.attributes;
    final kind = attributes['list'];
    if (kind != null) {
      final depth = (attributes['indent'] as num?)?.toInt() ?? 0;
      final column = depth == 0 ? 0 : contentColumns[depth - 1] ?? depth * 2;
      final prefix = ' ' * column;
      final number = attributes[_listNumber] ?? 1;
      final marker = switch (kind) {
        'ordered' => '$number. ',
        'checked' => '- [x] ',
        'unchecked' => '- [ ] ',
        _ => '- ',
      };
      contentColumns.removeWhere((key, _) => key > depth);
      contentColumns[depth] =
          column + (kind == 'ordered' ? '$number. '.length : 2);
      final previous = index > 0 ? lines[index - 1].attributes : null;
      final followsLooseParent =
          previous?['list'] != null &&
          previous?[_listLoose] == true &&
          depth > ((previous?['indent'] as num?)?.toInt() ?? 0);
      if (attributes[_listLoose] == true || followsLooseParent) blankLine();
      write('$prefix$marker${_encodeInline(line.content)}\n');
      index++;
      continue;
    }
    final ownerDepth = (attributes[_listContinuation] as num).toInt();
    final column = contentColumns[ownerDepth] ?? (ownerDepth + 1) * 2;
    final prefix = ' ' * column;
    blankLine();
    if (attributes['code-block'] == true) {
      final code = <String>[];
      final language = attributes[_codeLanguage] as String? ?? '';
      while (index < lines.length &&
          lines[index].attributes['code-block'] == true &&
          lines[index].attributes[_listContinuation] == ownerDepth) {
        code.add(_plainText(lines[index++].content));
      }
      final longest = RegExp(r'`+')
          .allMatches(code.join('\n'))
          .fold<int>(
            2,
            (length, match) =>
                match[0]!.length > length ? match[0]!.length : length,
          );
      final fence = '`' * (longest + 1);
      write('$prefix$fence$language\n');
      for (final value in code) {
        write('$prefix$value\n');
      }
      write('$prefix$fence\n');
    } else {
      write('$prefix${_encodeInline(line.content)}\n');
      index++;
    }
  }
  return output.toString();
}

class _Delimiter {
  const _Delimiter(this.open, this.close);
  final String open;
  final String close;
  @override
  bool operator ==(Object other) =>
      other is _Delimiter && open == other.open && close == other.close;
  @override
  int get hashCode => Object.hash(open, close);
}

List<_Delimiter> _delimiters(Map<String, dynamic> attrs) {
  final result = <_Delimiter>[];
  if (attrs['link'] is String) {
    final url = (attrs['link'] as String).replaceAll('>', '%3E');
    final title = attrs[_linkTitle] is String
        ? ' "${(attrs[_linkTitle] as String).replaceAll('"', '&quot;')}"'
        : '';
    result.add(_Delimiter('[', '](<$url>$title)'));
  }
  if (attrs['bold'] == true) result.add(const _Delimiter('**', '**'));
  if (attrs['italic'] == true) result.add(const _Delimiter('*', '*'));
  if (attrs['strike'] == true) result.add(const _Delimiter('~~', '~~'));
  if (attrs['underline'] == true) result.add(const _Delimiter('<u>', '</u>'));
  if (attrs['background'] != null) {
    result.add(const _Delimiter('<mark>', '</mark>'));
  }
  return result;
}

String _encodeInline(Delta delta) {
  final out = StringBuffer();
  var active = <_Delimiter>[];
  List<_Delimiter> commonPrefix(List<_Delimiter> left, List<_Delimiter> right) {
    var count = 0;
    while (count < left.length &&
        count < right.length &&
        left[count] == right[count]) {
      count++;
    }
    return left.sublist(0, count);
  }

  void transition(List<_Delimiter> next) {
    final common = commonPrefix(active, next).length;
    for (var i = active.length - 1; i >= common; i--) {
      out.write(active[i].close);
    }
    for (var i = common; i < next.length; i++) {
      out.write(next[i].open);
    }
    active = next;
  }

  final operations = delta.toList();
  for (var index = 0; index < operations.length; index++) {
    final operation = operations[index];
    final data = operation.data;
    if (data is Map) {
      transition([]);
      final type = data.keys.single.toString();
      if (type == richMarkdownSourceEmbedType ||
          type == richMarkdownFootnoteEmbedType) {
        final payload = jsonDecode(data[type] as String) as Map;
        out.write(payload['raw'] as String);
      } else if (type == 'image') {
        out.write('![](<${data[type].toString().replaceAll('>', '%3E')}>)');
      } else {
        out.write(
          '<!-- akribos-embed ${base64Url.encode(utf8.encode(jsonEncode(data)))} -->',
        );
      }
      continue;
    }
    if (data is! String) continue;
    final attrs = operation.attributes ?? {};
    final next = _delimiters(attrs);
    if (attrs['code'] == true) {
      transition(next);
      final longest = RegExp(r'`+')
          .allMatches(data)
          .fold<int>(
            0,
            (length, match) =>
                match[0]!.length > length ? match[0]!.length : length,
          );
      final fence = '`' * (longest + 1);
      final padding =
          data.startsWith('`') ||
              data.endsWith('`') ||
              (data.startsWith(' ') && data.endsWith(' '))
          ? ' '
          : '';
      out.write('$fence$padding$data$padding$fence');
      continue;
    }
    final whitespace = RegExp(r'^([ \t]*)([\s\S]*?)([ \t]*)$')
        .firstMatch(data)!;
    final leading = whitespace[1]!;
    final text = whitespace[2]!;
    final trailing = whitespace[3]!;
    if (leading.isNotEmpty) {
      transition(commonPrefix(active, next));
      out.write(leading);
    }
    if (text.isNotEmpty) {
      transition(next);
      out.write(_escape(text));
    }
    if (trailing.isNotEmpty) {
      final following =
          index + 1 < operations.length && operations[index + 1].data is String
          ? _delimiters(operations[index + 1].attributes ?? {})
          : <_Delimiter>[];
      transition(commonPrefix(next, following));
      out.write(trailing);
    }
  }
  transition([]);
  return out.toString();
}
