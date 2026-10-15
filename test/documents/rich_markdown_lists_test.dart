import 'package:akribos_app/features/documents/rich_markdown_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown/markdown.dart' as md;

String rendered(String value) =>
    md.markdownToHtml(value, extensionSet: md.ExtensionSet.gitHubFlavored);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('blank lines keep Turndown sublists attached to their parent', () {
    const source =
        '-   **Oberpunkt**\n\n    -   λόγος\n\n    -   Trost\n\n-   Schluss\n';
    final editor = RichMarkdownController(markdown: source);
    addTearDown(editor.dispose);
    expect(editor.markdown, source);
    final operations = editor.quill.document.toDelta().toList();
    expect(operations.any((op) => op.attributes?['code-block'] == true), false);
    expect(
      operations
          .where((op) => op.attributes?['list'] == 'bullet')
          .map((op) => op.attributes?['indent'] ?? 0),
      [0, 1, 1, 0],
    );
    final at = editor.quill.document.toPlainText().indexOf('Trost');
    expect(at, greaterThanOrEqualTo(0));
    editor.quill.replaceText(at, 5, 'Frieden', null);
    expect(
      rendered(editor.markdown),
      rendered(source.replaceFirst('Trost', 'Frieden')),
    );
  });

  test('mixed nested lists retain ordered marker widths and numbering on export', () {
    const source =
        '10. Elternpunkt\n\n    - Kind\n\n      3. Enkel\n      4. Wiederholung\n\n11. Weiter\n';
    final editor = RichMarkdownController(markdown: source);
    addTearDown(editor.dispose);
    final at = editor.quill.document.toPlainText().indexOf('Enkel');
    expect(at, greaterThanOrEqualTo(0));
    editor.quill.replaceText(at, 5, 'Nachkomme', null);
    expect(
      rendered(editor.markdown),
      rendered(source.replaceFirst('Enkel', 'Nachkomme')),
    );
  });

  test('continuation paragraphs stay within their item before and after a sublist', () {
    const source =
        '- Parent\n\n  Zweiter **Absatz**.\n\n  - Kind\n\n  Fortsetzung nach Kind.\n\n- Ende\n';
    final editor = RichMarkdownController(markdown: source);
    addTearDown(editor.dispose);
    final plain = editor.quill.document.toPlainText();
    expect(
      plain,
      contains('Parent\nZweiter Absatz.\nKind\nFortsetzung nach Kind.\nEnde'),
    );
    final at = plain.indexOf('Fortsetzung');
    editor.quill.replaceText(at, 'Fortsetzung'.length, 'Weiterlesen', null);
    expect(
      rendered(editor.markdown),
      rendered(source.replaceFirst('Fortsetzung', 'Weiterlesen')),
    );
  });

  test('real indented and fenced code never becomes a nested list', () {
    const source =
        '    - echter Code\n\n```text\n- ebenfalls Code\n```\n\nSchluss.\n';
    final editor = RichMarkdownController(markdown: source);
    addTearDown(editor.dispose);
    expect(
      editor.quill.document.toDelta().toList().any(
        (op) => op.attributes?['list'] != null,
      ),
      false,
    );
    expect(editor.quill.document.toPlainText(), contains('- echter Code'));
    final at = editor.quill.document.toPlainText().indexOf('Schluss');
    editor.quill.replaceText(at, 7, 'Ende', null);
    expect(editor.markdown, source.replaceFirst('Schluss', 'Ende'));
  });

  test(
    'a real code block inside a list retains its code semantics on edit',
    () {
      const source = '- Parent\n\n      - echter Code\n\n- Ende\n';
      final editor = RichMarkdownController(markdown: source);
      addTearDown(editor.dispose);
      final plain = editor.quill.document.toPlainText();
      expect(plain, contains('- echter Code'));
      final at = plain.indexOf('echter');
      editor.quill.replaceText(at, 6, 'bleibender', null);
      expect(
        rendered(editor.markdown),
        rendered(source.replaceFirst('echter', 'bleibender')),
      );
    },
  );
}
