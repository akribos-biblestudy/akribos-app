import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:markdown/markdown.dart' as md;

import '../../core/app_scope.dart';
import '../../theme/akribos_theme.dart';
import '../../widgets/common.dart';

/// Read-only native rendering. The caller may supply server HTML only when it
/// belongs to exactly [markdown]. No rendering result is ever written to a draft.
class MarkdownDocumentReader extends StatefulWidget {
  const MarkdownDocumentReader({
    super.key,
    required this.markdown,
    this.renderedHtml,
    this.scrollController,
    this.fontScale = 1,
    this.padding = const EdgeInsets.fromLTRB(20, 12, 20, 80),
  });

  final String markdown;
  final String? renderedHtml;
  final ScrollController? scrollController;
  final double fontScale;
  final EdgeInsetsGeometry padding;

  @override
  State<MarkdownDocumentReader> createState() => _MarkdownDocumentReaderState();
}

class _MarkdownDocumentReaderState extends State<MarkdownDocumentReader> {
  late String _html;
  Map<String, String> _notes = {};
  String? _error;

  @override
  void initState() {
    super.initState();
    _render();
  }

  @override
  void didUpdateWidget(MarkdownDocumentReader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.markdown != oldWidget.markdown ||
        widget.renderedHtml != oldWidget.renderedHtml) {
      _render();
    }
  }

  void _render() {
    try {
      final rendered = renderDocumentMarkdown(
        widget.markdown,
        renderedHtml: widget.renderedHtml,
      );
      _html = rendered;
      _notes = {
        for (final note
            in html_parser
                .parseFragment(rendered)
                .querySelectorAll('[data-footnote-id]'))
          note.attributes['data-footnote-id']!: _footnoteSheetHtml(
            note.innerHtml,
          ),
      };
      _error = null;
    } catch (_) {
      _html = '';
      _notes = {};
      _error =
          'Die formatierte Ansicht ist nicht verfügbar. '
          'Der vollständige Markdown-Text bleibt erhalten.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AkribosThemeTokens.of(context);
    final style = TextStyle(
      fontFamily: 'AkribosText',
      fontFamilyFallback: const ['NotoSansHebrew'],
      fontSize: 19 * widget.fontScale.clamp(.7, 2),
      fontWeight: FontWeight.w400,
      height: 1.6,
      color: Theme.of(context).colorScheme.onSurface,
    );
    return SingleChildScrollView(
      key: const PageStorageKey('markdown-document-reader'),
      controller: widget.scrollController,
      padding: widget.padding,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 840),
          child: SizedBox(
            width: double.infinity,
            child: SelectionArea(
              child: _error != null
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_error!),
                        const SizedBox(height: 16),
                        Text(widget.markdown, style: style),
                      ],
                    )
                  : HtmlContent(
                      html: _html,
                      scalableListMarkers: true,
                      textStyle: style,
                      customStylesBuilder: (element) =>
                          documentReadingStyles(element, tokens),
                      customWidgetBuilder: (element) {
                        final id = element.attributes['data-footnote-ref'];
                        final note = _notes[id];
                        if (id == null || note == null) return null;
                        return InlineCustomWidget(
                          child: Semantics(
                            button: true,
                            label: 'Fußnote ${element.text} öffnen',
                            child: InkWell(
                              onTap: () => _showFootnote(
                                context,
                                element.text,
                                note,
                                style,
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                  vertical: 2,
                                ),
                                child: Text(
                                  element.text,
                                  style: style.copyWith(
                                    color: tokens.accent,
                                    fontSize: style.fontSize! * .8,
                                    decoration: TextDecoration.underline,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showFootnote(
    BuildContext context,
    String number,
    String html,
    TextStyle style,
  ) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    sheetAnimationStyle: AppScope.of(context).eInk
        ? AnimationStyle.noAnimation
        : null,
    builder: (context) => ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .8,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 20, right: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Fußnote $number',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: 'Schließen',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              child: SelectionArea(
                child: HtmlContent(
                  html: html,
                  scalableListMarkers: true,
                  textStyle: style,
                  customStylesBuilder: (element) => documentReadingStyles(
                    element,
                    AkribosThemeTokens.of(context),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

String _cssColor(Color color) =>
    '#${color.toARGB32().toRadixString(16).substring(2)}';

/// Styling is shared by the full document and the read-only footnote sheet.
Map<String, String>? documentReadingStyles(
  dom.Element element,
  AkribosThemeTokens tokens,
) => switch (element.localName) {
  'p' => {
    'margin': element.parent?.localName == 'li' ? '0 0 .4em' : '0 0 .8em',
  },
  'ul' || 'ol' => {
    'padding-left': '1.5em',
    'margin': '.35em 0 .7em',
    if (element.localName == 'ul') 'list-style-type': 'disc',
  },
  'li' => {'margin': '0 0 .2em'},
  'blockquote' => {
    'margin': '.5em 0 .7em',
    'padding-left': '.8em',
    'border-left': '3px solid ${_cssColor(tokens.accent)}',
  },
  'table' => {'border-collapse': 'collapse', 'margin': '.6em 0'},
  'td' || 'th' => {
    'border': '1px solid ${_cssColor(tokens.line)}',
    'padding': '.35em .5em',
  },
  'pre' => {
    'padding': '.6em',
    'background-color': _cssColor(tokens.paperDeep),
    'white-space': 'pre-wrap',
  },
  'mark' => {
    'color': _cssColor(tokens.accent),
    'background-color': _cssColor(tokens.accentSoft),
    if (tokens.eInk) 'text-decoration': 'underline',
  },
  'a' => {'color': _cssColor(tokens.accent)},
  'h1' ||
  'h2' ||
  'h3' ||
  'h4' ||
  'h5' ||
  'h6' => {'margin': '.7em 0 .35em', 'line-height': '1.25'},
  _ => null,
};

/// Render a complete source, preserving Markdown container context. Server HTML
/// gives exact Akribos semantics. Offline rendering uses GFM plus the bounded
/// footnote fix below; it never normalizes or serializes the authored Markdown.
String renderDocumentMarkdown(String markdown, {String? renderedHtml}) {
  String html;
  if (renderedHtml != null &&
      (renderedHtml.isNotEmpty || markdown.trim().isEmpty)) {
    html = renderedHtml;
  } else {
    final footnotes = _SafeFootnoteDefinition();
    final document = md.Document(
      extensionSet: md.ExtensionSet(
        md.ExtensionSet.gitHubFlavored.blockSyntaxes
            .map(
              (syntax) => syntax is md.FootnoteDefSyntax ? footnotes : syntax,
            )
            .toList(),
        md.ExtensionSet.gitHubFlavored.inlineSyntaxes,
      ),
    );
    final nodes = document.parse(markdown);
    // GFM hides unreferenced notes. Akribos preserves them; display those parsed
    // definitions too, without manufacturing references or changing the source.
    final unused = footnotes.definitions.entries
        .where((entry) => document.footnoteReferences[entry.key] == 0)
        .map((entry) => entry.value)
        .toList();
    if (unused.isNotEmpty) {
      nodes.add(
        md.Element('section', [
          md.Element('ol', unused)
            ..attributes['start'] = '${document.footnoteLabels.length + 1}',
        ])..attributes['class'] = 'footnotes',
      );
    }
    html = md.renderToHtml(nodes);
  }
  return _prepareDocumentHtml(html);
}

/// markdown 7.3.1 appends backlink Text nodes to the last block's children.
/// A trailing list has a covariant `List<Element>`, causing a runtime TypeError;
/// a trailing code block would receive backlink content. Put those links in a
/// separate paragraph. This changes display AST only, never authored content.
class _SafeFootnoteDefinition extends md.FootnoteDefSyntax {
  final definitions = <String, md.Element>{};

  @override
  md.Node? parse(md.BlockParser parser) {
    final node = super.parse(parser) as md.Element;
    final children = node.children!;
    if (children.isNotEmpty &&
        (children.last is! md.Element ||
            (children.last as md.Element).tag != 'p')) {
      children.add(md.Element('p', <md.Node>[]));
    }
    definitions[node.footnoteLabel!] = node;
    return node;
  }
}

String _prepareDocumentHtml(String html) {
  final fragment = html_parser.parseFragment(html);
  const allowed = {
    'p',
    'h1',
    'h2',
    'h3',
    'h4',
    'h5',
    'h6',
    'strong',
    'b',
    'em',
    'i',
    's',
    'del',
    'u',
    'mark',
    'ul',
    'ol',
    'li',
    'blockquote',
    'code',
    'pre',
    'hr',
    'br',
    'a',
    'sup',
    'sub',
    'table',
    'thead',
    'tbody',
    'tr',
    'th',
    'td',
    'div',
    'span',
    'section',
    'img',
  };
  for (final checkbox in fragment.querySelectorAll('input[type="checkbox"]')) {
    checkbox.replaceWith(
      dom.Element.tag('span')
        ..text = checkbox.attributes.containsKey('checked') ? '☑ ' : '☐ ',
    );
  }
  for (final element in fragment.querySelectorAll('*').toList()) {
    if (!allowed.contains(element.localName)) {
      if (const {
        'script',
        'style',
        'iframe',
        'object',
        'img',
        'video',
        'audio',
      }.contains(element.localName)) {
        element.remove();
      } else {
        element.replaceWith(dom.Text(element.text));
      }
      continue;
    }
    element.attributes.removeWhere(
      (key, _) => !const {
        'id',
        'href',
        'title',
        'class',
        'start',
        'align',
        'data-footnotes',
        'data-footnote-id',
        'data-footnote-ref',
        'src',
        'alt',
        'width',
        'height',
        'colspan',
        'rowspan',
      }.contains(key),
    );
    final href = element.attributes['href'];
    if (href != null) {
      final uri = Uri.tryParse(href);
      if (uri == null ||
          uri.userInfo.isNotEmpty ||
          (uri.hasScheme &&
              !const {'https', 'http', 'mailto'}.contains(uri.scheme))) {
        element.attributes.remove('href');
      }
    }
  }
  for (final element in fragment.querySelectorAll('.footnotes > ol')) {
    element.attributes['data-footnotes'] = 'true';
    for (final note in element.children) {
      final id = note.id;
      if (id.startsWith('fn-')) {
        note.attributes['data-footnote-id'] = Uri.decodeComponent(
          id.substring(3),
        );
      }
    }
  }
  for (final note in fragment.querySelectorAll('[data-footnote-id]')) {
    note.attributes['id'] =
        'fn-${Uri.encodeComponent(note.attributes['data-footnote-id']!)}';
  }
  for (final reference in fragment.querySelectorAll('sup')) {
    final href = reference.querySelector('a')?.attributes['href'];
    if (href != null && href.startsWith('#fn-')) {
      reference.attributes['data-footnote-ref'] = Uri.decodeComponent(
        href.substring(4),
      );
    }
  }
  return fragment.outerHtml;
}

String _footnoteSheetHtml(String html) {
  final fragment = html_parser.parseFragment(html);
  for (final backlink in fragment.querySelectorAll('.footnote-backref')) {
    backlink.remove();
  }
  return fragment.outerHtml;
}
