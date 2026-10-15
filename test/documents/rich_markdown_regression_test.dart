import 'package:akribos_app/features/documents/rich_markdown_controller.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart' as q;
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown/markdown.dart' as md;

const _complex = r'''# Gedanken zu Johannes

Ein **starker _innerer_** Gedanke mit \*Sternen\*, `a*b` und [Studie](/notes/123?kind=note#abschnitt).

| Ausdruck | Bedeutung |
| :--- | ---: |
| λόγος | **Wort** mit \| Zeichen |
| שָׁלוֹם | Frieden[^f1] |

Ein Gedanke[^f1] und ein zweiter Verweis[^f1].

[^f1]: Eine **formatierte** Fußnote mit [Joh 1,1](/Joh1,1).

    Zweiter Absatz der Fußnote.

    - Erster Punkt
    - Zweiter Punkt

[^unbenutzt]: Auch diese unreferenzierte Notiz bleibt erhalten.

Endsatz.
''';

List<md.Element> _elements(String source, String tag) {
  final result = <md.Element>[];
  void visit(md.Node node) {
    if (node is! md.Element) return;
    if (node.tag == tag) result.add(node);
    for (final child in node.children ?? <md.Node>[]) {
      visit(child);
    }
  }

  final nodes = md.Document(extensionSet: md.ExtensionSet.gitHubFlavored)
      .parseLines(source.split('\n'));
  nodes.forEach(visit);
  return result;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'selection and reading mode preserve original Markdown without changes',
    () {
      final editor = RichMarkdownController(markdown: _complex);
      addTearDown(editor.dispose);
      final controller = editor.quill;
      var changes = 0;
      editor.addListener(() => changes++);
      editor.quill.updateSelection(
        const TextSelection(baseOffset: 0, extentOffset: 8),
        q.ChangeSource.local,
      );
      editor.quill.readOnly = true;
      editor.quill.readOnly = false;
      expect(editor.markdown, _complex);
      expect(editor.quill, same(controller));
      expect(changes, 0);
    },
  );

  test('editing a paragraph preserves original tables and every footnote', () {
    final editor = RichMarkdownController(markdown: _complex);
    addTearDown(editor.dispose);
    final at = editor.quill.document.toPlainText().indexOf('Endsatz.');
    expect(at, greaterThanOrEqualTo(0));
    editor.quill.replaceText(at, 'Endsatz.'.length, 'Neuer Schluss.', null);
    final result = editor.markdown;
    final table = _complex.substring(
      _complex.indexOf('| Ausdruck'),
      _complex.indexOf('\n\nEin Gedanke'),
    );
    expect(result, contains(table));
    expect(result, contains('Ein Gedanke[^f1] und ein zweiter Verweis[^f1].'));
    expect(result, contains('[^f1]: Eine **formatierte** Fußnote'));
    expect(result, contains('    Zweiter Absatz der Fußnote.'));
    expect(result, contains('    - Erster Punkt\n    - Zweiter Punkt'));
    expect(
      result,
      contains(
        '[^unbenutzt]: Auch diese unreferenzierte Notiz bleibt erhalten.',
      ),
    );
    expect(result, contains('Neuer Schluss.'));
    expect(result, isNot(contains('Endsatz.')));
  });

  test('formatting text keeps nested emphasis, escaped stars, code and local links', () {
    const source = r'''Ein **starker _innerer_** Gedanke mit \*Sternen\*, `a*b` und [Studie](/notes/123?kind=note#abschnitt). Schluss.
''';
    final editor = RichMarkdownController(markdown: source);
    addTearDown(editor.dispose);
    final at = editor.quill.document.toPlainText().indexOf('Schluss');
    expect(at, greaterThanOrEqualTo(0));
    editor.quill.updateSelection(
      TextSelection(baseOffset: at, extentOffset: at + 7),
      q.ChangeSource.local,
    );
    editor.quill.formatSelection(q.Attribute.bold);
    final result = editor.markdown;
    expect(
      _elements(result, 'strong').map((e) => e.textContent),
      contains('Schluss'),
    );
    expect(
      _elements(result, 'strong').map((e) => e.textContent),
      contains('starker innerer'),
    );
    expect(
      _elements(result, 'em').map((e) => e.textContent),
      contains('innerer'),
    );
    expect(
      _elements(result, 'em').map((e) => e.textContent),
      isNot(contains('Sternen')),
    );
    expect(
      _elements(result, 'code').map((e) => e.textContent),
      contains('a*b'),
    );
    expect(
      _elements(result, 'a').single.attributes['href'],
      '/notes/123?kind=note#abschnitt',
    );
  });

  test(
    'editing beside underline and highlight retains their semantic markup',
    () {
      const source =
          '<u>Unterstrichen</u> und <mark>markiert</mark> neben Schluss.\n';
      final editor = RichMarkdownController(markdown: source);
      addTearDown(editor.dispose);
      final at = editor.quill.document.toPlainText().indexOf('Schluss');
      expect(at, greaterThanOrEqualTo(0));
      editor.quill.replaceText(at, 7, 'Anfang', null);
      expect(editor.markdown, contains('<u>Unterstrichen</u>'));
      expect(editor.markdown, contains('<mark>markiert</mark>'));
      expect(editor.markdown, contains('Anfang'));
    },
  );

  test(
    'unmodified code, hard breaks and unsupported source survive nearby typing',
    () {
      const source = r'''Erste Zeile\
zweite Zeile.

```dart
final text = "**kein Fett**";
```

> Ein Zitat mit [Verweis](/Joh3,16).
>
> - Erster Gedanke
> - Zweiter Gedanke

<aside data-original="bleibt">Besonderer Quellinhalt</aside>

Endsatz.
''';
      final editor = RichMarkdownController(markdown: source);
      addTearDown(editor.dispose);
      final at = editor.quill.document.toPlainText().indexOf('Endsatz.');
      expect(at, greaterThanOrEqualTo(0));
      editor.quill.replaceText(at, 0, 'Ein neuer ', null);
      expect(
        editor.markdown,
        contains(source.substring(0, source.indexOf('Endsatz.'))),
      );
      expect(editor.markdown, contains('Ein neuer Endsatz.'));
    },
  );

  test(
    'read mode preserves undo and a fresh controller reopens the saved change',
    () {
      const source = 'λόγος und שָׁלוֹם.\n';
      final editor = RichMarkdownController(markdown: source);
      addTearDown(editor.dispose);
      editor.quill.replaceText(0, 0, 'Studie: ', null);
      final updated = editor.markdown;
      editor.quill.readOnly = true;
      editor.quill.readOnly = false;
      final restored = RichMarkdownController(markdown: updated);
      addTearDown(restored.dispose);
      expect(
        restored.quill.document.toPlainText(),
        contains('Studie: λόγος und שָׁלוֹם.'),
      );
      editor.quill.undo();
      expect(editor.markdown, source);
    },
  );
}
