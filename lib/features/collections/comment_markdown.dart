import 'package:html2md/html2md.dart' as html2md;
import 'package:markdown/markdown.dart' as md;

bool _rulesRegistered = false;

/// Standard formatting becomes editable Markdown. Underlining has no Markdown
/// equivalent, so retain its original HTML token instead of dropping it.
String commentToMarkdown(String html) {
  if (!_rulesRegistered) {
    html2md.Rule.addRules([
      html2md.Rule(
        'akribos-comment-underline',
        filters: ['u'],
        replacement: (_, node) => node.outerHTML,
      ),
      html2md.Rule(
        'akribos-comment-div',
        filters: ['div'],
        replacement: (content, _) => '\n\n$content\n\n',
      ),
    ]);
    _rulesRegistered = true;
  }
  final protectedText = html
      .replaceAll(
        RegExp(r'&(?:lt|#0*60|#x0*3c);', caseSensitive: false),
        '&amp;lt;',
      )
      .replaceAll(
        RegExp(r'&(?:gt|#0*62|#x0*3e);', caseSensitive: false),
        '&amp;gt;',
      );
  return html2md.convert(
    protectedText,
    styleOptions: {
      'headingStyle': 'atx',
      'bulletListMarker': '-',
      'emDelimiter': '*',
    },
  );
}

class _CommentLineBreak extends md.InlineSyntax {
  _CommentLineBreak() : super(r'\n');
  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(md.Element.empty('br'));
    return true;
  }
}

String commentFromMarkdown(
  String markdown, {
  String? originalHtml,
  String? initialMarkdown,
}) {
  if (originalHtml != null && markdown == initialMarkdown) return originalHtml;
  var html = md.markdownToHtml(
    markdown,
    extensionSet: md.ExtensionSet.gitHubFlavored,
    inlineSyntaxes: [_CommentLineBreak()],
  );
  // The existing comment contract deliberately permits no attributes or links.
  // Keep link destinations readable instead of silently losing them or showing
  // escaped <a href=...> source in the saved comment.
  html = html.replaceAllMapped(
    RegExp(r'<a href="([^"]*)"[^>]*>(.*?)</a>', dotAll: true),
    (match) => '${match[2]} (${match[1]})',
  );
  html = html.replaceAll('<del>', '<s>').replaceAll('</del>', '</s>');
  html = html.replaceAllMapped(
    RegExp(r'<(/?)h([1456])>'),
    (match) => '<${match[1]}${match[2] == '1' ? 'h2' : 'h3'}>',
  );
  // The legacy sanitizer recognizes named &lt;...&gt; as supported tags. Numeric
  // entities preserve genuinely literal angle brackets through that contract.
  html = html.replaceAll('&lt;', '&#60;').replaceAll('&gt;', '&#62;');
  return sanitizeCommentPreview(html);
}

/// Mirrors the narrow existing server contract for an honest native preview.
/// The backend remains the authority and sanitizes the submitted HTML again.
String sanitizeCommentPreview(String html) {
  final escaped = html
      .replaceAllMapped(
        RegExp(
          r'&(?!(?:[a-zA-Z][a-zA-Z0-9]{1,10}|#\d{1,6}|#x[0-9a-fA-F]{1,6});)',
        ),
        (_) => '&amp;',
      )
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
  return escaped
      .replaceAllMapped(
        RegExp(
          r'&lt;(/?)(p|div|br|strong|b|em|i|u|s|code|h2|h3|ul|ol|li|blockquote)\s*/?&gt;',
          caseSensitive: false,
        ),
        (match) => '<${match[1]}${match[2]!.toLowerCase()}>',
      )
      .replaceAll(RegExp(r'<p>\s*</p>'), '')
      .trim();
}
