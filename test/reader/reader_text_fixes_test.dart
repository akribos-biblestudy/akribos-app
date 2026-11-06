import 'dart:ui' as ui;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:akribos_app/core/json.dart';
import 'package:akribos_app/features/reader/reader_screen.dart';
import 'package:akribos_app/features/reader/verse_text.dart';
import 'package:akribos_app/features/search/search_screen.dart';
import 'package:akribos_app/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'native_reader_test.dart' show ReaderApi, readerFixture, app;

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await (FontLoader('AkribosText')
          ..addFont(rootBundle.load('assets/fonts/akribos-text-regular.ttf')))
        .load();
  });

  testWidgets('first verse is underlined on the initial E-Ink frame', (
    tester,
  ) async {
    final boundary = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(highContrast: true),
          child: Scaffold(
            body: RepaintBoundary(
              key: boundary,
              child: const SizedBox(
                width: 600,
                child: VerseText(
                  segments: ['Am Anfang war das Wort.'],
                  verseNumber: '1',
                  selectable: false,
                  highlights: [
                    {'start': 0, 'end': 10000, 'color': '#facc15'},
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final marker = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((w) => w.painter)
        .whereType<VerseMarkerPainter>()
        .single;
    final rect = marker.rectangles(marker.ranges.single).single;
    expect(marker.highContrast, isTrue);
    final pixels = await tester.runAsync(() async {
      final image =
          await (boundary.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary)
              .toImage();
      final pixels = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final row = (rect.bottom - 1).floor(), width = image.width;
      final blackPixels = <int>[];
      for (var x = rect.left.ceil(); x < rect.right.floor(); x++) {
        final at = (row * width + x) * 4;
        if (pixels!.getUint8(at) < 100 && pixels.getUint8(at + 3) > 200) {
          blackPixels.add(x);
        }
      }
      image.dispose();
      return blackPixels.length;
    });
    expect(pixels, greaterThan(rect.width * .9));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a fresh reader starts with justified flow paragraphs', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({});
    final api = ReaderApi(readerFixture(), seedLocal: false);
    addTearDown(api.dispose);
    await tester.pumpWidget(
      app(api, ReaderScreen(path: '/Joh1', localStore: api.localStore)),
    );
    await tester.pumpAndSettle();
    final verse = tester.widget<VerseText>(find.byType(VerseText).first);
    expect(verse.passages, hasLength(30));
    expect(
      tester
          .state<VerseTextState>(find.byType(VerseText).first)
          .paragraph!
          .textAlign,
      TextAlign.justify,
    );
    expect((await api.localStore.read())?['versePerLine'], isFalse);
  });

  for (final eInk in [false, true]) {
    testWidgets('flow labels belong to their verses (E-Ink $eInk)', (
      tester,
    ) async {
      final data = readerFixture()..['versePerLine'] = false;
      final chapter = asMap(asMaps(data['columns']).first['initialChapter']);
      final rows = asMaps(asMap(chapter['chapter'])['rows']);
      for (var i = 0; i < rows.length; i++) {
        final cell = asMaps(rows[i]['cells']).first;
        cell['segments'] = ['Text für Vers ${i + 1}.'];
        if (i == 0) cell['heading'] = 'Abschnittsüberschrift';
      }
      chapter['highlights'] = [
        {'verse': 2, 'name': 'Wichtig', 'color': '#facc15'},
        {'verse': 2, 'name': 'Wichtig', 'color': '#facc15'},
        {'verse': 3, 'name': 'Trost', 'color': '#00ff00'},
      ];
      final api = ReaderApi(data);
      addTearDown(api.dispose);
      await tester.pumpWidget(
        app(api, const ReaderScreen(path: '/Joh1'), eInk: eInk),
      );
      await tester.pumpAndSettle();
      final text = tester
          .state<VerseTextState>(find.byType(VerseText).first)
          .paragraph!
          .text
          .toPlainText();
      if (eInk) {
        expect(
          text,
          contains(
            '2\u00a0Text für Vers 2. (Markiert: Wichtig) 3\u00a0Text für Vers 3. (Markiert: Trost)',
          ),
        );
        expect(text, isNot(contains('1\u00a0Text für Vers 1. (Markiert:')));
        expect(find.text('Markiert: Wichtig, Trost'), findsNothing);
        expect(find.text('Abschnittsüberschrift'), findsOneWidget);
      } else {
        expect(text, isNot(contains('Markiert:')));
      }
      expect(tester.takeException(), isNull);
    });
  }

  for (final versewise in [false, true]) {
    testWidgets(
      'E-Ink labels end consecutive styles across sections (versewise $versewise)',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final data = readerFixture()..['versePerLine'] = versewise;
        final column = asMaps(data['columns']).first;
        final chapter = asMap(column['initialChapter']);
        final rows = asMaps(asMap(chapter['chapter'])['rows']);
        rows.removeRange(7, rows.length);
        for (var i = 0; i < rows.length; i++) {
          final cell = asMaps(rows[i]['cells']).first;
          cell['segments'] = ['Versinhalt ${i + 1}.'];
          if (i == 2) cell['heading'] = 'Neuer Abschnitt';
        }
        asMaps(rows[5]['cells']).first['verseEnd'] = 7;
        rows.removeLast();
        (asMap(chapter['chapter'])['rows'] as List).removeRange(6, 30);
        chapter['highlights'] = [
          for (final verse in [1, 2, 3, 5])
            {'verse': verse, 'styleId': 'a', 'name': 'A', 'color': '#facc15'},
          {'verse': 4, 'styleId': 'b', 'name': 'B', 'color': '#00ff00'},
          {'verse': 7, 'styleId': 'd', 'name': 'D', 'color': '#0000ff'},
          {
            'verse': 1,
            'endVerse': 2,
            'resourceId': asMap(column['resource'])['id'],
            'styleId': 'c',
            'name': 'Teil',
            'color': '#ff0000',
            'startWord': 0,
            'endWord': 0,
          },
        ];
        final api = ReaderApi(data);
        addTearDown(api.dispose);
        await tester.pumpWidget(
          app(api, const ReaderScreen(path: '/Joh1'), eInk: true),
        );
        await tester.pumpAndSettle();
        final texts = tester
            .stateList<VerseTextState>(find.byType(VerseText))
            .map((state) => state.paragraph!.text.toPlainText())
            .join(' | ');
        expect(texts, isNot(contains('Versinhalt 1. (Markiert:')));
        expect(texts, contains('Versinhalt 2. (Markiert: Teil)'));
        expect(texts, contains('Versinhalt 3. (Markiert: A)'));
        expect(texts, contains('Versinhalt 4. (Markiert: B)'));
        expect(texts, contains('Versinhalt 5. (Markiert: A)'));
        expect(texts, contains('Versinhalt 6. (Markiert: D)'));
        expect(RegExp(r'Markiert: A').allMatches(texts), hasLength(2));
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final versewise in [false, true]) {
    testWidgets('labels survive an omitted end verse (versewise $versewise)', (
      tester,
    ) async {
      final data = readerFixture()..['versePerLine'] = versewise;
      final column = asMaps(data['columns']).first;
      final chapter = asMap(column['initialChapter']);
      final rows = asMaps(asMap(chapter['chapter'])['rows']);
      rows.removeAt(2);
      (asMap(chapter['chapter'])['rows'] as List).removeAt(2);
      for (final row in rows) {
        final cell = asMaps(row['cells']).first;
        cell['segments'] = ['Versinhalt ${cell['verse']}.'];
      }
      chapter['highlights'] = [
        // The server need not return records in verse order.
        for (final verse in [3, 2, 1])
          {'verse': verse, 'styleId': 'a', 'name': 'A', 'color': '#facc15'},
        {
          'verse': 1,
          'endVerse': 3,
          'resourceId': asMap(column['resource'])['id'],
          'styleId': 'b',
          'name': 'Teil',
          'color': '#ff0000',
          'startWord': 0,
          'endWord': 0,
        },
      ];
      final api = ReaderApi(data);
      addTearDown(api.dispose);
      await tester.pumpWidget(
        app(api, const ReaderScreen(path: '/Joh1'), eInk: true),
      );
      await tester.pumpAndSettle();
      final texts = tester
          .stateList<VerseTextState>(find.byType(VerseText))
          .map((state) => state.paragraph!.text.toPlainText())
          .join(' | ');
      expect(texts, isNot(contains('Versinhalt 1. (Markiert:')));
      expect(texts, contains('Versinhalt 2. (Markiert: A, Teil)'));
      expect(tester.takeException(), isNull);
    });
  }

  for (final scale in [1.0, 2.0]) {
    testWidgets('flow verse numbers stay with the first word at scale $scale', (
      tester,
    ) async {
      int? tappedPosition;
      for (final width in [220.0, 280.0, 350.0]) {
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: Scaffold(
                body: SizedBox(
                  width: width,
                  child: VerseText(
                    segments: const [],
                    selectable: false,
                    passages: List.generate(
                      20,
                      (i) => VersePassage(
                        number: '${i + 1}',
                        onWord: (_, position) => tappedPosition = position,
                        segments: const [
                          '  ',
                          {'kind': 'w', 'text': 'Anfang', 'strong': 'G746'},
                          ' war das Wort bei Gott.',
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        final paragraph = tester
            .state<VerseTextState>(find.byType(VerseText))
            .paragraph!;
        final text = paragraph.text.toPlainText();
        for (final match in RegExp(r'\d+\u00a0Anfang').allMatches(text)) {
          final number = paragraph
              .getBoxesForSelection(
                TextSelection(
                  baseOffset: match.start,
                  extentOffset: match.start + 1,
                ),
              )
              .single;
          final wordStart = match.end - 'Anfang'.length;
          final firstWord = paragraph.getBoxesForSelection(
            TextSelection(baseOffset: wordStart, extentOffset: match.end),
          );
          expect(firstWord, hasLength(1));
          expect(
            number.bottom,
            closeTo(firstWord.single.bottom, 12 * scale),
            reason:
                'width=$width verse=${match.group(0)} boxes=$firstWord number=$number',
          );
        }
        final firstWord = paragraph
            .getBoxesForSelection(
              TextSelection(
                baseOffset: text.indexOf('Anfang'),
                extentOffset: text.indexOf('Anfang') + 6,
              ),
            )
            .single
            .toRect();
        await tester.tapAt(paragraph.localToGlobal(firstWord.center));
        expect(tappedPosition, 0);
        expect(RegExp(r'\d+\u00a0Anfang').allMatches(text), hasLength(20));
        expect(tester.takeException(), isNull);
      }
    });
  }

  for (final eInk in [false, true]) {
    for (final versewise in [false, true]) {
      testWidgets(
        'first chapter verse retains nullable whole-verse highlight (E-Ink $eInk, versewise $versewise)',
        (tester) async {
          final data = readerFixture()..['versePerLine'] = versewise;
          final initial = asMap(
            asMaps(data['columns']).first['initialChapter'],
          );
          initial['highlights'] = [
            {
              'verse': 1,
              'endVerse': null,
              'startWord': null,
              'endWord': null,
              'resourceId': null,
              'color': '#facc15',
              'name': 'Wichtig',
            },
          ];
          final api = ReaderApi(data);
          addTearDown(api.dispose);
          await tester.pumpWidget(
            app(api, const ReaderScreen(path: '/Joh1'), eInk: eInk),
          );
          await tester.pumpAndSettle();
          final painter = tester
              .widgetList<CustomPaint>(
                find.descendant(
                  of: find.byType(VerseText).first,
                  matching: find.byType(CustomPaint),
                ),
              )
              .map((w) => w.painter)
              .whereType<VerseMarkerPainter>()
              .single;
          final range = painter.ranges.single;
          final text = painter.paragraph()!.text.toPlainText();
          expect(
            text.substring(range.start, range.end),
            'Ein längerer Beispielvers mit Liebe und Hoffnung für den neuen Tag.',
          );
          expect(painter.rectangles(range), isNotEmpty);
          expect(painter.highContrast, eInk);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  for (final scale in [70, 100, 200]) {
    testWidgets('commentary and lexicon content uses $scale percent', (
      tester,
    ) async {
      final data = readerFixture()..['readerFontScale'] = scale;
      asMaps(data['readerResources']).first['kind'] = 'commentary';
      final initial = asMap(asMaps(data['columns']).first['initialChapter']);
      initial['referenceResources'] = {
        'commentaries': [
          {
            'verseStart': 1,
            'title': 'Ein Kommentar',
            'bodyHtml': '<p>Kommentartext</p>',
          },
        ],
      };
      final api = ReaderApi(data);
      addTearDown(api.dispose);
      await tester.pumpWidget(app(api, const ReaderScreen(path: '/Joh1')));
      await tester.pumpAndSettle();
      final commentary = tester.widget<HtmlContent>(
        find.byWidgetPredicate(
          (w) => w is HtmlContent && w.html.contains('Kommentartext'),
        ),
      );
      expect(commentary.textStyle!.fontSize, closeTo(19 * scale / 100, .001));
      await tester.pumpWidget(
        app(
          api,
          const SingleChildScrollView(
            child: StrongDetails(
              data: {
                'entry': {
                  'strong': 'G3056',
                  'lemma': 'λόγος',
                  'definitionHtml': '<p>Lexikontext</p>',
                },
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final lexicon = tester.widget<HtmlContent>(
        find.byWidgetPredicate(
          (w) => w is HtmlContent && w.html.contains('Lexikontext'),
        ),
      );
      expect(lexicon.textStyle!.fontSize, closeTo(19 * scale / 100, .001));
      expect(tester.takeException(), isNull);
    });
  }
}
