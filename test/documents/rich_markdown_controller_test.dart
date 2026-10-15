// Quill clipboard configuration is experimental in the pinned upstream version.
// ignore_for_file: experimental_member_use

import 'dart:convert';

import 'package:akribos_app/features/documents/rich_markdown_controller.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart' as q;
import 'package:flutter_quill/quill_delta.dart';
import 'package:flutter_test/flutter_test.dart';

List<Map<String, dynamic>> embeds(RichMarkdownController editor, String type) =>
    editor.quill.document
        .toDelta()
        .toList()
        .where(
          (operation) =>
              operation.data is Map &&
              (operation.data as Map).containsKey(type),
        )
        .map(
          (operation) => Map<String, dynamic>.from(
            jsonDecode((operation.data as Map)[type] as String) as Map,
          ),
        )
        .toList();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('source separators remain byte exact without adding visible empty paragraphs', () {
    const source =
        '# Titel\r\n\r\nErster Absatz.\r\n\r\n\r\nZweiter Absatz.\r\n';
    final editor = RichMarkdownController(markdown: source);
    addTearDown(editor.dispose);
    expect(
      editor.quill.document.toPlainText(),
      'Titel\nErster Absatz.\nZweiter Absatz.\n',
    );
    expect(editor.markdown, source);
    final at = editor.quill.document.toPlainText().indexOf('Erster');
    editor.quill.replaceText(at, 6, 'Neuer', null);
    expect(
      editor.markdown,
      '# Titel\r\n\r\nNeuer Absatz.\n\r\n\r\nZweiter Absatz.\r\n',
    );
  });

  test(
    'enter creates a Markdown paragraph and retains original paragraph gaps',
    () {
      final editor = RichMarkdownController(
        markdown: 'Erster zweiter.\n\nDanach.\n',
      );
      addTearDown(editor.dispose);
      editor.quill.replaceText(7, 0, '\n', null);
      final reopened = RichMarkdownController(markdown: editor.markdown);
      addTearDown(reopened.dispose);
      expect(
        reopened.quill.document.toPlainText(),
        'Erster\nzweiter.\nDanach.\n',
      );
    },
  );

  test('undo restores the original empty source without adding a newline', () {
    final editor = RichMarkdownController(markdown: '');
    addTearDown(editor.dispose);
    editor.quill.replaceText(0, 0, 'Text', null);
    expect(editor.markdown, isNotEmpty);
    editor.quill.undo();
    expect(editor.markdown, '');
  });

  test('same-paragraph edits retain inline footnote identity and rich definitions', () {
    const source =
        'Wort[^a] und Wort[^a].\n\n[^a]: **Erklärung**\n\n    Noch ein Absatz.\n';
    final editor = RichMarkdownController(markdown: source);
    addTearDown(editor.dispose);
    expect(embeds(editor, richMarkdownFootnoteEmbedType).map((e) => e['id']), [
      'a',
      'a',
    ]);
    editor.quill.replaceText(0, 4, 'λόγος', null);
    expect(editor.markdown, startsWith('λόγος[^a] und Wort[^a].'));
    expect(
      editor.markdown,
      contains('[^a]: **Erklärung**\n\n    Noch ein Absatz.'),
    );
  });

  test(
    'immediate export does not consume an asynchronous change notification',
    () async {
      final editor = RichMarkdownController(markdown: 'Alt.\n');
      addTearDown(editor.dispose);
      var changes = 0;
      editor.addListener(() => changes++);
      editor.quill.document.compose(
        Delta()..insert('Neu: '),
        q.ChangeSource.local,
      );
      expect(editor.markdown, 'Neu: Alt.\n');
      await Future<void>.delayed(Duration.zero);
      expect(changes, 1);
    },
  );

  test(
    'save snapshots stay immutable while a later edit is being serialized',
    () {
      final editor = RichMarkdownController(markdown: 'Anfang.\n');
      addTearDown(editor.dispose);
      editor.quill.replaceText(0, 0, '1 ', null);
      final inFlight = editor.markdown;
      editor.quill.replaceText(0, 0, '2 ', null);
      expect(inFlight, '1 Anfang.\n');
      expect(editor.markdown, '2 1 Anfang.\n');
    },
  );

  test(
    'recovery is silent, retains the controller and ignores obsolete events',
    () async {
      final editor = RichMarkdownController(markdown: 'Alt.\n');
      addTearDown(editor.dispose);
      final quill = editor.quill;
      var changes = 0;
      editor.addListener(() => changes++);
      editor.quill.document.compose(
        Delta()..insert('Ausstehend '),
        q.ChangeSource.local,
      );
      editor.setMarkdown('Wiederhergestellt.\r\n');
      await Future<void>.delayed(Duration.zero);
      expect(editor.quill, same(quill));
      expect(editor.markdown, 'Wiederhergestellt.\r\n');
      expect(changes, 0);
      editor.setMarkdown('Ausdrücklich neu.', notify: true);
      expect(changes, 1);
    },
  );

  test(
    'insertion replaces the selected text using Quill offsets and styles',
    () {
      final editor = RichMarkdownController(markdown: 'Hallo Welt.\n');
      addTearDown(editor.dispose);
      editor.quill.updateSelection(
        const TextSelection(baseOffset: 6, extentOffset: 10),
        q.ChangeSource.local,
      );
      editor.insertMarkdown('**λόγος**');
      expect(editor.markdown, 'Hallo **λόγος**.\n');
    },
  );

  test(
    'inserting a source block does not swallow its surrounding paragraphs',
    () {
      final editor = RichMarkdownController(markdown: 'Vorne hinten.');
      addTearDown(editor.dispose);
      editor.quill.updateSelection(
        const TextSelection.collapsed(offset: 6),
        q.ChangeSource.local,
      );
      editor.insertMarkdown('| A | B |\n| --- | --- |\n| x | y |');
      expect(
        editor.markdown,
        contains('Vorne \n| A | B |\n| --- | --- |\n| x | y |\nhinten.'),
      );
    },
  );

  test('footnote creation is one undo step and uses an unused identifier', () {
    final editor = RichMarkdownController(
      markdown: 'Text[^1].\n\n[^1]: Alt.\n',
    );
    addTearDown(editor.dispose);
    editor.quill.updateSelection(
      const TextSelection.collapsed(offset: 4),
      q.ChangeSource.local,
    );
    final before = editor.markdown;
    editor.insertFootnote(content: 'Neue **Fußnote**.');
    expect(editor.markdown, contains('[^2]'));
    expect(editor.markdown, contains('[^2]: Neue **Fußnote**.'));
    expect(embeds(editor, richMarkdownFootnoteEmbedType).map((e) => e['id']), [
      '2',
      '1',
    ]);
    editor.quill.undo();
    expect(editor.markdown, before);
  });

  test('source replacement changes exactly one table and preserves other raw blocks', () {
    const source =
        'Einleitung.\r\n\r\n| A | B |\r\n| --- | --- |\r\n| x | y |\r\n\r\nSchluss.\r\n';
    final editor = RichMarkdownController(markdown: source);
    addTearDown(editor.dispose);
    var offset = 0;
    for (final op in editor.quill.document.toDelta().toList()) {
      if (op.data is Map &&
          (op.data as Map).containsKey(richMarkdownSourceEmbedType)) {
        break;
      }
      offset += op.length!;
    }
    editor.quill.replaceText(
      offset,
      1,
      q.Embeddable(
        richMarkdownSourceEmbedType,
        jsonEncode({
          'raw': '| Neu |\n| --- |\n| Inhalt |\n',
          'kind': 'table',
          'label': 'Tabelle',
        }),
      ),
      null,
    );
    expect(editor.markdown, startsWith('Einleitung.\r\n\r\n| Neu |'));
    expect(editor.markdown, endsWith('\r\nSchluss.\r\n'));
    expect(editor.markdown, isNot(contains('| x | y |')));
  });

  test('images and unknown HTML remain source embeds without image providers', () {
    const source =
        '![Alt](https://example.invalid/private.png)\n\n<div data-x="keep">Text</div>\n\nEnde.';
    final editor = RichMarkdownController(markdown: source);
    addTearDown(editor.dispose);
    expect(embeds(editor, richMarkdownSourceEmbedType).map((e) => e['kind']), [
      'image',
      'html',
    ]);
    final at = editor.quill.document.toPlainText().indexOf('Ende.');
    editor.quill.replaceText(at, 0, 'Neues ', null);
    expect(
      editor.markdown,
      startsWith(source.substring(0, source.indexOf('Ende.'))),
    );
    expect(editor.quill.config.clipboardConfig!.enableExternalRichPaste, false);
  });

  test('literal list markers remain literal after editing their paragraph', () {
    const source = r'\- kein Listeneintrag und 1\. normal. Schluss.';
    final editor = RichMarkdownController(markdown: source);
    addTearDown(editor.dispose);
    final at = editor.quill.document.toPlainText().indexOf('Schluss');
    editor.quill.replaceText(at, 7, 'Ende', null);
    final restored = RichMarkdownController(markdown: editor.markdown);
    addTearDown(restored.dispose);
    expect(
      restored.quill.document.toPlainText(),
      '- kein Listeneintrag und 1. normal. Ende.\n',
    );
    expect(
      restored.quill.document.toDelta().toList().any(
        (op) => op.attributes?['list'] != null,
      ),
      false,
    );
  });

  test('headings lists quotes and fenced code are natively editable', () {
    const source =
        '# Titel\n\n- Eins\n- Zwei\n\n3. Drei\n4. Vier\n\n> Zitat\n\n```dart\nprint(1);\n```\n';
    final editor = RichMarkdownController(markdown: source);
    addTearDown(editor.dispose);
    expect(embeds(editor, richMarkdownSourceEmbedType), isEmpty);
    final at = editor.quill.document.toPlainText().indexOf('print(1)');
    editor.quill.replaceText(at, 'print(1)'.length, 'print(2)', null);
    expect(editor.markdown, contains('```dart\nprint(2);\n```'));
    expect(
      editor.markdown,
      startsWith('# Titel\n\n- Eins\n- Zwei\n\n3. Drei\n4. Vier\n\n> Zitat\n'),
    );
  });
}
