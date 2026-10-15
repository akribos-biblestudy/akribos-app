import 'package:akribos_app/core/api_client.dart';
import 'package:akribos_app/core/app_scope.dart';
import 'package:akribos_app/features/documents/rich_markdown_controller.dart';
import 'package:akribos_app/features/documents/rich_markdown_editor.dart';
import 'package:akribos_app/theme/akribos_theme.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart' as q;
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_api.dart';

void main() {
  late AppApi api;
  late FakeHttpAdapter adapter;
  final opened = <String>[];
  setUp(() {
    opened.clear();
    adapter = FakeHttpAdapter((_) async => success());
    api = AppApi(
      server: 'https://akribos.test',
      dio: Dio()..httpClientAdapter = adapter,
      cookies: CookieJar(),
    );
  });
  tearDown(() => api.dispose());
  Widget host(Widget child, {double textScale = 1}) => AppScope(
    api: api,
    open: (path) async => opened.add(path),
    refreshSession: () async {},
    setNavigationGuard: (_, _) {},
    setTheme: (_) {},
    themeMode: ThemeMode.light,
    child: MaterialApp(
      locale: const Locale('de'),
      localizationsDelegates: const [
        q.FlutterQuillLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: const [Locale('de')],
      theme: buildAkribosTheme(Brightness.light),
      home: Scaffold(
        body: MediaQuery(
          data: MediaQueryData(
            size: const Size(320, 780),
            textScaler: TextScaler.linear(textScale),
          ),
          child: child,
        ),
      ),
    ),
  );

  testWidgets(
    'phone rich text formatting appears only for selection and read mode keeps document history',
    (tester) async {
      tester.view.physicalSize = const Size(320, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final rich = RichMarkdownController(
        markdown:
            'Meine Gedanken bleiben hier.\n\n${List.generate(35, (i) => 'Absatz $i bleibt im Skript.\n\n').join()}',
      );
      final focus = FocusNode();
      final scroll = ScrollController();
      addTearDown(rich.dispose);
      addTearDown(focus.dispose);
      addTearDown(scroll.dispose);
      var readOnly = false;
      late StateSetter redraw;
      await tester.pumpWidget(
        host(
          StatefulBuilder(
            builder: (context, setState) {
              redraw = setState;
              return RichMarkdownEditor(
                controller: rich,
                readOnly: readOnly,
                focusNode: focus,
                scrollController: scroll,
              );
            },
          ),
          textScale: 1.4,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('Fett'), findsNothing);
      expect(tester.takeException(), isNull);
      focus.requestFocus();
      rich.quill.updateSelection(
        const TextSelection(baseOffset: 0, extentOffset: 5),
        q.ChangeSource.local,
      );
      await tester.pumpAndSettle();
      final state = tester.state<q.QuillRawEditorState>(
        find.byType(q.QuillRawEditor),
      );
      state.showToolbar();
      await tester.pumpAndSettle();
      expect(find.byTooltip('Fett'), findsOneWidget);
      await tester.tap(find.byTooltip('Fett'));
      await tester.pumpAndSettle();
      expect(rich.markdown, contains('**Meine**'));
      final document = rich.quill.document;
      scroll.jumpTo(600);
      await tester.pump();
      final readingPosition = scroll.offset;
      expect(rich.quill.hasUndo, isTrue);
      redraw(() => readOnly = true);
      await tester.pumpAndSettle();
      expect(identical(document, rich.quill.document), isTrue);
      expect(scroll.offset, readingPosition);
      expect(rich.quill.readOnly, isTrue);
      expect(focus.hasFocus, isFalse);
      expect(find.byTooltip('Fett'), findsNothing);
      expect(rich.quill.hasUndo, isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'read mode footnotes open formatted content and return without navigation or external image requests',
    (tester) async {
      final rich = RichMarkdownController(
        markdown: 'Lesetext[^a] und wieder[^a].\n\n[^a]: **Eine Erklärung** mit [Quelle](https://example.test).\n\n![Extern](https://example.test/pixel.png)\n',
      );
      addTearDown(rich.dispose);
      await tester.pumpWidget(
        host(RichMarkdownEditor(controller: rich, readOnly: true)),
      );
      await tester.pumpAndSettle();
      final original = rich.markdown;
      var contentChanges = 0;
      rich.addListener(() => contentChanges++);
      expect(find.text('[1]'), findsNWidgets(2));
      await tester.tap(find.text('[1]').first);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Eine Erklärung', findRichText: true),
        findsWidgets,
      );
      expect(find.byTooltip('Zurück zum Text'), findsOneWidget);
      await tester.tap(find.byTooltip('Zurück zum Text'));
      await tester.pumpAndSettle();
      expect(opened, isEmpty);
      expect(adapter.requests, isEmpty);
      expect(rich.markdown, original);
      expect(contentChanges, 0);
      expect(tester.testTextInput.isVisible, isFalse);
      expect(find.byTooltip('Fett'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'table cells edit as rich text while unchanged aligned Markdown stays exact',
    (tester) async {
      const source =
          'Text davor.\n\n| Wort | Erklärung |\n| :--- | ---: |\n| **Anfang** | bleibt |\n\nText danach.\n';
      final rich = RichMarkdownController(markdown: source);
      addTearDown(rich.dispose);
      await tester.pumpWidget(
        host(RichMarkdownEditor(controller: rich, readOnly: false)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Tabelle bearbeiten'));
      await tester.pumpAndSettle();
      expect(find.text('Tabelle bearbeiten'), findsOneWidget);
      await tester.tap(find.text('Übernehmen'));
      await tester.pumpAndSettle();
      expect(rich.markdown, source);
      await tester.tap(find.byTooltip('Tabelle bearbeiten'));
      await tester.pumpAndSettle();
      final cell = find.text('bleibt', findRichText: true).last;
      await tester.tapAt(tester.getTopLeft(cell) + const Offset(15, 8));
      await tester.pumpAndSettle();
      expect(find.text('Zeile 2, Spalte 2'), findsOneWidget);
      final childEditor = tester.widget<q.QuillEditor>(
        find.byType(q.QuillEditor).last,
      );
      childEditor.controller.replaceText(
        0,
        6,
        'Neu',
        const TextSelection.collapsed(offset: 3),
      );
      await tester.pump();
      await tester.tap(find.text('Übernehmen').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Übernehmen'));
      await tester.pumpAndSettle();
      expect(rich.markdown, contains('| **Anfang** | Neu |'));
      expect(rich.markdown, contains('| :--- | ---: |'));
      expect(rich.markdown, startsWith('Text davor.\n\n'));
      expect(rich.markdown, endsWith('\n\nText danach.\n'));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'block insertion works at a collapsed cursor without a formatting toolbar',
    (tester) async {
      final rich = RichMarkdownController(markdown: 'Absatz\n');
      addTearDown(rich.dispose);
      late BuildContext editorContext;
      await tester.pumpWidget(
        host(
          Builder(
            builder: (context) {
              editorContext = context;
              return RichMarkdownEditor(controller: rich, readOnly: false);
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      rich.quill.updateSelection(
        const TextSelection.collapsed(offset: 2),
        q.ChangeSource.local,
      );
      await insertRichMarkdownBlock(
        editorContext,
        rich,
        RichMarkdownBlock.heading2,
      );
      await tester.pumpAndSettle();
      expect(rich.markdown, contains('## Absatz'));
      expect(find.byTooltip('Fett'), findsNothing);
      await insertRichMarkdownBlock(
        editorContext,
        rich,
        RichMarkdownBlock.bulletedList,
      );
      await tester.pumpAndSettle();
      expect(rich.markdown, contains('- Absatz'));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
