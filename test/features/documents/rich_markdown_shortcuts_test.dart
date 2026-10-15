// ignore_for_file: experimental_member_use
import 'package:akribos_app/features/documents/rich_markdown_controller.dart';
import 'package:akribos_app/features/documents/rich_markdown_editor.dart';
import 'package:akribos_app/features/documents/rich_markdown_shortcuts.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart' as q;
import 'package:flutter_test/flutter_test.dart';

class _Editor extends StatefulWidget {
  const _Editor({required this.rich, this.readOnly = false});
  final RichMarkdownController rich;
  final bool readOnly;
  @override
  State<_Editor> createState() => _EditorState();
}

class _EditorState extends State<_Editor> {
  final focus = FocusNode();
  final editorKey = GlobalKey<q.EditorState>();
  final scroll = ScrollController();
  late final shortcuts = RichMarkdownShortcuts(
    controller: widget.rich.quill,
    editorKey: editorKey,
    focusNode: focus,
  );
  @override
  void dispose() {
    shortcuts.dispose();
    focus.dispose();
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    widget.rich.quill.readOnly = widget.readOnly;
    return q.QuillEditor(
      controller: widget.rich.quill,
      focusNode: focus,
      scrollController: scroll,
      config: q.QuillEditorConfig(
        editorKey: editorKey,
        expands: true,
        spaceShortcutEvents: shortcuts.spaceEvents,
      ),
    );
  }
}

Widget _app(RichMarkdownController rich, {bool readOnly = false}) =>
    MaterialApp(
      localizationsDelegates: const [q.FlutterQuillLocalizations.delegate],
      home: Scaffold(
        body: _Editor(rich: rich, readOnly: readOnly),
      ),
    );

Future<void> _mount(WidgetTester tester, RichMarkdownController rich) async {
  await tester.pumpWidget(_app(rich));
  await tester.pumpAndSettle();
  tester.state<_EditorState>(find.byType(_Editor)).focus.requestFocus();
  await tester.pumpAndSettle();
}

Future<void> _type(
  WidgetTester tester,
  String text, {
  TextRange composing = TextRange.empty,
}) async {
  final state = tester.state<q.QuillRawEditorState>(
    find.byType(q.QuillRawEditor),
  );
  final old = state.currentTextEditingValue!;
  final start = old.selection.start;
  tester.testTextInput.updateEditingValue(
    TextEditingValue(
      text: old.text.replaceRange(start, old.selection.end, text),
      selection: TextSelection.collapsed(offset: start + text.length),
      composing: composing,
    ),
  );
  await tester.pump();
}

Future<void> _clean(WidgetTester tester, RichMarkdownController rich) async {
  await tester.pumpWidget(const SizedBox());
  rich.dispose();
}

void main() {
  final cases = <String, (String, Object)>{
    for (var level = 1; level <= 6; level++) '#' * level: ('header', level),
    '-': ('list', 'bullet'),
    '*': ('list', 'bullet'),
    '+': ('list', 'bullet'),
    '1.': ('list', 'ordered'),
    '>': ('blockquote', true),
  };
  for (final entry in cases.entries) {
    testWidgets(
      'native keyboard converts ${entry.key} only on the following space',
      (tester) async {
        final rich = RichMarkdownController(markdown: '');
        await _mount(tester, rich);
        for (final char in entry.key.characters) {
          await _type(tester, char);
        }
        expect(rich.quill.document.toPlainText(), '${entry.key}\n');
        expect(
          rich.quill.getSelectionStyle().attributes[entry.value.$1],
          isNull,
        );
        await _type(tester, ' ');
        expect(rich.quill.document.toPlainText(), '\n');
        expect(rich.quill.selection.baseOffset, 0);
        expect(
          rich.quill.document.toDelta().last.attributes?[entry.value.$1],
          entry.value.$2,
        );
        await _type(tester, 'Gedanke');
        expect(rich.quill.document.toPlainText(), 'Gedanke\n');
        final reopened = RichMarkdownController(markdown: rich.markdown);
        expect(reopened.quill.document.toPlainText(), 'Gedanke\n');
        expect(
          reopened.quill.document.toDelta().last.attributes?[entry.value.$1],
          entry.value.$2,
        );
        reopened.dispose();
        expect(tester.takeException(), isNull);
        await _clean(tester, rich);
      },
    );
  }

  testWidgets(
    'hardware space converts the current paragraph and preserves earlier text',
    (tester) async {
      final rich = RichMarkdownController(markdown: 'Vorher\n\n');
      await _mount(tester, rich);
      rich.quill.updateSelection(
        TextSelection.collapsed(offset: rich.quill.document.length - 1),
        q.ChangeSource.local,
      );
      await _type(tester, '\n');
      await _type(tester, '#');
      await _type(tester, '#');
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(rich.quill.document.toPlainText(), 'Vorher\n\n');
      expect(rich.quill.selection.baseOffset, 7);
      expect(rich.quill.document.toDelta().last.attributes?['header'], 2);
      expect(rich.markdown, startsWith('Vorher'));
      await _clean(tester, rich);
    },
  );

  testWidgets(
    'conversion undo restores the literal marker and redo restores its block',
    (tester) async {
      final rich = RichMarkdownController(markdown: '');
      await _mount(tester, rich);
      await _type(tester, '-');
      await _type(tester, ' ');
      rich.quill.undo();
      await tester.pump();
      expect(rich.quill.document.toPlainText(), '- \n');
      expect(rich.quill.getSelectionStyle().attributes['list'], isNull);
      expect(rich.quill.selection.baseOffset, 2);
      rich.quill.redo();
      await tester.pump();
      expect(rich.quill.document.toPlainText(), '\n');
      expect(
        rich.quill.getSelectionStyle().attributes['list']?.value,
        'bullet',
      );
      expect(rich.quill.selection.baseOffset, 0);
      await _type(tester, 'Text');
      rich.quill.undo();
      await tester.pump();
      expect(rich.quill.document.toPlainText(), '\n');
      expect(
        rich.quill.getSelectionStyle().attributes['list']?.value,
        'bullet',
      );
      await _clean(tester, rich);
    },
  );

  testWidgets(
    'escaped, indented, non-prefix and seven hash input remains literal',
    (tester) async {
      for (final prefix in [r'\-', ' -', 'Text -', '#######', '-1']) {
        final rich = RichMarkdownController(markdown: '');
        await _mount(tester, rich);
        for (final char in prefix.characters) {
          await _type(tester, char);
        }
        await _type(tester, ' ');
        expect(rich.quill.document.toPlainText(), '$prefix \n');
        expect(rich.quill.getSelectionStyle().attributes['list'], isNull);
        expect(rich.quill.getSelectionStyle().attributes['header'], isNull);
        await _clean(tester, rich);
      }
    },
  );

  testWidgets(
    'bulk paste and programmatic changes never trigger typing shortcuts',
    (tester) async {
      final rich = RichMarkdownController(markdown: '');
      await _mount(tester, rich);
      await _type(tester, '- ');
      expect(rich.quill.document.toPlainText(), '- \n');
      expect(rich.quill.getSelectionStyle().attributes['list'], isNull);
      rich.setMarkdown('');
      await tester.pump();
      rich.quill.replaceText(
        0,
        0,
        '#',
        const TextSelection.collapsed(offset: 1),
      );
      rich.quill.replaceText(
        1,
        0,
        ' ',
        const TextSelection.collapsed(offset: 2),
      );
      await tester.pump();
      expect(rich.quill.document.toPlainText(), '# \n');
      expect(rich.quill.getSelectionStyle().attributes['header'], isNull);
      rich.setMarkdown('## ');
      await tester.pump();
      expect(rich.markdown, '## ');
      await _clean(tester, rich);
    },
  );

  testWidgets(
    'active IME composition stays literal, committed space can convert',
    (tester) async {
      final rich = RichMarkdownController(markdown: '');
      await _mount(tester, rich);
      await _type(tester, '-', composing: const TextRange(start: 0, end: 1));
      await _type(tester, ' ', composing: const TextRange(start: 0, end: 2));
      expect(rich.quill.document.toPlainText(), '- \n');
      expect(rich.quill.getSelectionStyle().attributes['list'], isNull);
      final state = tester.state<q.QuillRawEditorState>(
        find.byType(q.QuillRawEditor),
      );
      tester.testTextInput.updateEditingValue(
        state.currentTextEditingValue!.copyWith(composing: TextRange.empty),
      );
      await tester.pump();
      expect(rich.quill.document.toPlainText(), '- \n');
      rich.setMarkdown('');
      await tester.pump();
      await _type(tester, '-', composing: const TextRange(start: 0, end: 1));
      await _type(tester, ' ');
      expect(rich.quill.document.toPlainText(), '\n');
      expect(
        rich.quill.getSelectionStyle().attributes['list']?.value,
        'bullet',
      );
      await _clean(tester, rich);
    },
  );

  testWidgets(
    'code blocks, inline code, selections and read-only mode do not convert',
    (tester) async {
      for (final attr in [q.Attribute.codeBlock, q.Attribute.inlineCode]) {
        final rich = RichMarkdownController(markdown: '');
        await _mount(tester, rich);
        rich.quill.formatSelection(attr);
        await tester.pump();
        await _type(tester, '-');
        await _type(tester, ' ');
        expect(rich.quill.document.toPlainText(), '- \n');
        expect(rich.quill.getSelectionStyle().attributes['list'], isNull);
        await _clean(tester, rich);
      }
      final rich = RichMarkdownController(markdown: '');
      await _mount(tester, rich);
      await _type(tester, '-');
      rich.quill.updateSelection(
        const TextSelection(baseOffset: 0, extentOffset: 1),
        q.ChangeSource.local,
      );
      await _type(tester, ' ');
      expect(rich.quill.document.toPlainText(), ' \n');
      rich.setMarkdown(r'\-');
      await tester.pump();
      rich.quill.updateSelection(
        const TextSelection.collapsed(offset: 1),
        q.ChangeSource.local,
      );
      await tester.pumpWidget(_app(rich, readOnly: true));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(rich.quill.document.toPlainText(), '-\n');
      expect(rich.markdown, r'\-');
      await _clean(tester, rich);
    },
  );

  test('adapter preserves an existing replacement guard and restores it on dispose', () {
    final rich = RichMarkdownController(markdown: r'\# Original');
    var calls = 0;
    bool original(int index, int length, Object? data) {
      calls++;
      return false;
    }

    rich.quill.onReplaceText = original;
    final focus = FocusNode();
    final shortcuts = RichMarkdownShortcuts(
      controller: rich.quill,
      editorKey: GlobalKey<q.EditorState>(),
      focusNode: focus,
    );
    expect(rich.markdown, r'\# Original');
    rich.quill.replaceText(0, 0, ' ', const TextSelection.collapsed(offset: 1));
    expect(calls, 1);
    expect(rich.markdown, r'\# Original');
    shortcuts.dispose();
    expect(rich.quill.onReplaceText, original);
    rich.quill.replaceText(0, 0, ' ', const TextSelection.collapsed(offset: 1));
    expect(calls, 2);
    focus.dispose();
    rich.dispose();
  });

  testWidgets('production RichMarkdownEditor wires native keyboard shortcuts', (
    tester,
  ) async {
    final rich = RichMarkdownController(markdown: '');
    final focus = FocusNode();
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [q.FlutterQuillLocalizations.delegate],
        home: Scaffold(
          body: RichMarkdownEditor(
            controller: rich,
            readOnly: false,
            focusNode: focus,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    focus.requestFocus();
    await tester.pumpAndSettle();
    await _type(tester, '#');
    await _type(tester, '#');
    await _type(tester, ' ');
    expect(rich.quill.document.toPlainText(), '\n');
    expect(rich.quill.document.toDelta().last.attributes?['header'], 2);
    await _type(tester, 'Überschrift');
    expect(rich.markdown.trim(), '## Überschrift');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    expect(rich.quill.onReplaceText, isNull);
    focus.dispose();
    rich.dispose();
  });
}
