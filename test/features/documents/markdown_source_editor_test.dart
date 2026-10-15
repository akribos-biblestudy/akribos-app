import 'package:akribos_app/features/documents/markdown_source_editor.dart';
import 'package:akribos_app/theme/akribos_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

const _source =
    '-   **Hoffnung**\n\n    -   Unterpunkt\n\n> Ein Zitat.\n\n'
    '| A | B |\n| --- | --- |\n| a | b |\n\n[^unused]: Unverändert.\n';

class _EditorFixture {
  _EditorFixture(String text)
    : controller = TextEditingController.fromValue(
        TextEditingValue(
          text: text,
          selection: const TextSelection.collapsed(offset: 0),
        ),
      );
  final TextEditingController controller;
  final undo = UndoHistoryController();
  final focus = FocusNode();
  final scroll = ScrollController();
  bool reading = false;
  late StateSetter redraw;

  Widget host({double scale = 1}) => MaterialApp(
    locale: const Locale('de'),
    supportedLocales: const [Locale('de')],
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    theme: buildAkribosTheme(Brightness.light),
    home: Scaffold(
      body: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: StatefulBuilder(
          builder: (context, setState) {
            redraw = setState;
            return IndexedStack(
              index: reading ? 1 : 0,
              sizing: StackFit.expand,
              children: [
                MarkdownSourceEditor(
                  controller: controller,
                  undoController: undo,
                  focusNode: focus,
                  scrollController: scroll,
                  readOnly: reading,
                ),
                const Text('Leseseite'),
              ],
            );
          },
        ),
      ),
    ),
  );

  Future<void> select(WidgetTester tester, int start, int end) async {
    focus.requestFocus();
    await tester.pump();
    controller.selection = TextSelection(baseOffset: start, extentOffset: end);
    await tester.pump();
    final state = tester.state<EditableTextState>(find.byType(EditableText));
    state.hideToolbar();
    state.toggleToolbar();
    await tester.pumpAndSettle();
  }

  void dispose() {
    controller.dispose();
    undo.dispose();
    focus.dispose();
    scroll.dispose();
  }
}

void main() {
  testWidgets(
    'native typing, IME, paste and selection preserve literal Markdown',
    (tester) async {
      final fixture = _EditorFixture(_source);
      addTearDown(fixture.dispose);
      await tester.pumpWidget(fixture.host());
      await tester.pumpAndSettle();
      expect(fixture.controller.text, _source);
      final decoration = tester
          .widget<InputDecorator>(
            find.descendant(
              of: find.byKey(const Key('markdown-source-field')),
              matching: find.byType(InputDecorator),
            ),
          )
          .decoration;
      expect(decoration.border, InputBorder.none);
      expect(decoration.enabledBorder, InputBorder.none);
      expect(decoration.focusedBorder, InputBorder.none);
      expect(decoration.disabledBorder, InputBorder.none);
      expect(
        decoration.contentPadding,
        const EdgeInsets.fromLTRB(4, 12, 4, 24),
      );
      await fixture.select(tester, 5, 14);
      expect(fixture.controller.text, _source);
      await tester.tap(find.byKey(const Key('markdown-source-field')));
      final composing = TextEditingValue(
        text: 'Gedank',
        selection: const TextSelection.collapsed(offset: 6),
        composing: const TextRange(start: 0, end: 6),
      );
      tester.testTextInput.updateEditingValue(composing);
      await tester.pump();
      expect(fixture.controller.value, composing);
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: '# ',
          selection: TextSelection.collapsed(offset: 2),
        ),
      );
      await tester.pump();
      expect(fixture.controller.text, '# ');
      await tester.enterText(find.byType(TextField), _source);
      await tester.pump();
      expect(fixture.controller.text, _source);
      await fixture.select(tester, 0, 0);
      expect(find.byTooltip('Fett'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'selection formatting uses native overflow and undo survives read toggle',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fixture = _EditorFixture('Hoffnung bleibt.');
      addTearDown(fixture.dispose);
      await tester.pumpWidget(fixture.host(scale: 2));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byTooltip('Fett'), findsNothing);
      await fixture.select(tester, 0, 8);
      expect(find.byTooltip('Fett'), findsOneWidget);
      await tester.tap(find.byTooltip('Mehr'));
      await tester.pumpAndSettle();
      expect(find.text('Kopieren').hitTestable(), findsOneWidget);
      expect(find.text('Ausschneiden').hitTestable(), findsOneWidget);
      await fixture.select(tester, 0, 8);
      await tester.tap(find.byTooltip('Fett'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 600));
      expect(fixture.controller.text, '**Hoffnung** bleibt.');
      expect(fixture.undo.value.canUndo, isTrue);
      final editable = tester.state<EditableTextState>(
        find.byType(EditableText),
      );
      fixture.redraw(() => fixture.reading = true);
      await tester.pumpAndSettle();
      expect(fixture.focus.hasFocus, isFalse);
      expect(tester.testTextInput.isVisible, isFalse);
      expect(find.byTooltip('Fett'), findsNothing);
      expect(fixture.controller.text, '**Hoffnung** bleibt.');
      fixture.redraw(() => fixture.reading = false);
      await tester.pumpAndSettle();
      expect(
        tester.state<EditableTextState>(find.byType(EditableText)),
        same(editable),
      );
      fixture.undo.undo();
      await tester.pumpAndSettle();
      expect(fixture.controller.text, 'Hoffnung bleibt.');
      fixture.undo.redo();
      await tester.pumpAndSettle();
      expect(fixture.controller.text, '**Hoffnung** bleibt.');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'more formatting and link dialogs apply only explicit selected source edits',
    (tester) async {
      final fixture = _EditorFixture('Hoffnung bleibt.');
      addTearDown(fixture.dispose);
      await tester.pumpWidget(fixture.host());
      await tester.pumpAndSettle();
      await fixture.select(tester, 0, 8);
      await tester.tap(find.byTooltip('Weitere Formatierung'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hervorheben'));
      await tester.pumpAndSettle();
      expect(fixture.controller.text, '<mark>Hoffnung</mark> bleibt.');
      fixture.controller.value = const TextEditingValue(
        text: 'Johannes bleibt.',
        selection: TextSelection.collapsed(offset: 0),
      );
      await fixture.select(tester, 0, 8);
      await tester.tap(find.byTooltip('Link einfügen'));
      await tester.pumpAndSettle();
      final address = find.widgetWithText(TextField, 'Adresse');
      await tester.enterText(address, 'javascript:alert(1)');
      await tester.tap(find.text('Einfügen'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Bitte eine Webadresse'), findsOneWidget);
      expect(fixture.controller.text, 'Johannes bleibt.');
      await tester.enterText(address, '/Joh3,16');
      await tester.tap(find.text('Einfügen'));
      await tester.pumpAndSettle();
      expect(fixture.controller.text, '[Johannes](/Joh3,16) bleibt.');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'a delayed link dialog never overwrites a recovered or read-only document',
    (tester) async {
      final fixture = _EditorFixture('Hoffnung bleibt.');
      addTearDown(fixture.dispose);
      await tester.pumpWidget(fixture.host());
      await tester.pumpAndSettle();
      await fixture.select(tester, 0, 8);
      await tester.tap(find.byTooltip('Link einfügen'));
      await tester.pumpAndSettle();
      fixture.controller.value = const TextEditingValue(
        text: 'Wiederhergestellter Entwurf',
        selection: TextSelection.collapsed(offset: 0),
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Adresse'),
        '/Joh1',
      );
      await tester.tap(find.text('Einfügen'));
      await tester.pumpAndSettle();
      expect(fixture.controller.text, 'Wiederhergestellter Entwurf');
      await fixture.select(tester, 0, 5);
      await tester.tap(find.byTooltip('Link einfügen'));
      await tester.pumpAndSettle();
      fixture.redraw(() => fixture.reading = true);
      await tester.pump();
      await tester.enterText(
        find.widgetWithText(TextField, 'Adresse'),
        '/Joh1',
      );
      await tester.tap(find.text('Einfügen'));
      await tester.pumpAndSettle();
      expect(fixture.controller.text, 'Wiederhergestellter Entwurf');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  test('explicit block operations retain untouched source and commit composition', () {
    final controller = TextEditingController.fromValue(
      TextEditingValue(
        text: 'Titel\n\n$_source',
        selection: const TextSelection.collapsed(offset: 5),
        composing: const TextRange(start: 0, end: 5),
      ),
    );
    addTearDown(controller.dispose);
    insertMarkdownBlock(controller, MarkdownInsertBlock.heading2);
    expect(controller.text, '## Titel\n\n$_source');
    expect(controller.value.composing, TextRange.empty);
    expect(controller.selection.baseOffset, 8);
    controller.selection = const TextSelection(baseOffset: 0, extentOffset: 8);
    insertMarkdownBlock(controller, MarkdownInsertBlock.paragraph);
    expect(controller.text, 'Titel\n\n$_source');
    final start = controller.text.indexOf('Unterpunkt');
    controller.selection = TextSelection.collapsed(offset: start + 4);
    insertMarkdownBlock(controller, MarkdownInsertBlock.numberedList);
    expect(
      controller.text,
      'Titel\n\n${_source.replaceFirst('    -   Unterpunkt', '    1. Unterpunkt')}',
    );
  });

  test(
    'footnotes choose unused identifiers without deleting selected content',
    () {
      final controller = TextEditingController.fromValue(
        const TextEditingValue(
          text: 'Wort[^1]\n\n[^1]: Vorhanden.\n',
          selection: TextSelection(baseOffset: 0, extentOffset: 4),
        ),
      );
      addTearDown(controller.dispose);
      insertMarkdownBlock(controller, MarkdownInsertBlock.footnote);
      expect(
        controller.text,
        'Wort[^2][^1]\n\n[^1]: Vorhanden.\n\n[^2]: Fußnotentext\n',
      );
      expect(controller.selection.textInside(controller.text), 'Fußnotentext');
    },
  );

  test(
    'code fences contain backticks and external inserted Markdown stays exact',
    () {
      final controller = TextEditingController.fromValue(
        const TextEditingValue(
          text: 'Text\n\n```\nCode\n```\n\nEnde',
          selection: TextSelection(baseOffset: 6, extentOffset: 18),
        ),
      );
      addTearDown(controller.dispose);
      final selected = controller.selection.textInside(controller.text);
      insertMarkdownBlock(controller, MarkdownInsertBlock.code);
      expect(controller.text, contains('````\n$selected\n````'));
      controller.selection = TextSelection.collapsed(
        offset: controller.text.length,
      );
      const addition = '\n\n> Joh3,16\n\n[Notiz](/notes/id)\n';
      final before = controller.text;
      insertMarkdownText(controller, addition);
      expect(controller.text, '$before$addition');
    },
  );
}
