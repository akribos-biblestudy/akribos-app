import 'package:akribos_app/features/reader/offline_reader_screen.dart';
import 'package:akribos_app/features/reader/verse_text.dart';
import 'package:akribos_app/theme/akribos_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> chapter(
  int book,
  int chapter, {
  String kind = 'bible',
  int verses = 1,
}) => {
  'reference': {'book': book, 'chapter': chapter},
  'fullTitle': '${book == 43 ? 'Johannes' : '1.Mose'} $chapter',
  'chapter': {
    'rows': [
      for (var i = 1; i <= verses; i++)
        {
          'verse': i,
          'cells': [
            {
              'verse': i,
              'segments': ['Text $chapter:$i'],
              'heading': i == 1 ? 'Abschnitt' : null,
            },
          ],
        },
    ],
  },
  'referenceResources': {
    'commentaries': kind == 'commentary'
        ? [
            {
              'verseStart': 1,
              'title': 'Erklärung',
              'bodyHtml': '<p>Lokaler Kommentar</p>',
            },
          ]
        : [],
    'crossReferences': kind == 'xrefs'
        ? [
            {'fromVerse': 1, 'toBook': 43, 'toChapter': 3, 'toVerse': 16},
          ]
        : [],
  },
};

Map<String, dynamic> package(
  String id,
  String kind,
  List<Map<String, dynamic>> chapters,
) => {
  'version': 1,
  'owner': null,
  'resource': {'id': id, 'name': id, 'kind': kind, 'direction': 'ltr'},
  'chapters': chapters,
};

void main() {
  testWidgets('offline poetry ignores source line breaks before explicit br', (
    tester,
  ) async {
    final source = chapter(43, 3, verses: 3);
    final rows = (source['chapter'] as Map)['rows'] as List;
    final cells = [
      for (final row in rows) ((row as Map)['cells'] as List).first,
    ];
    cells[0]['segments'] = [
      'Erste Zeile',
      {'kind': 'br'},
      'zweite Zeile',
    ];
    cells[1]['segments'] = [
      'Dritte Zeile,\n  ',
      {'kind': 'br'},
      'vierte Zeile',
    ];
    cells[2]['segments'] = [
      'Fünfte Zeile,\n  ',
      {'kind': 'br'},
      'sechste Zeile',
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: OfflineReaderScreen(
          packages: [
            package('Bibel', 'bible', [source]),
          ],
          eInk: false,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final paragraphs = tester
        .stateList<VerseTextState>(find.byType(VerseText))
        .map((state) => state.paragraph!)
        .toList();
    expect(paragraphs, hasLength(3));

    double topOfText(int paragraphIndex, String text) {
      final paragraph = paragraphs[paragraphIndex];
      final start = paragraph.text.toPlainText().indexOf(text);
      expect(start, greaterThanOrEqualTo(0));
      final box = paragraph
          .getBoxesForSelection(
            TextSelection(baseOffset: start, extentOffset: start + 1),
          )
          .single;
      return paragraph.localToGlobal(Offset(box.left, box.top)).dy;
    }

    final ordinaryLineSpacing = topOfText(0, 'zweite') - topOfText(0, 'Erste');
    expect(
      topOfText(1, 'vierte') - topOfText(1, 'Dritte'),
      closeTo(ordinaryLineSpacing, 0.1),
    );
    expect(
      topOfText(2, 'sechste') - topOfText(2, 'Fünfte'),
      closeTo(ordinaryLineSpacing, 0.1),
    );
    expect(
      topOfText(2, 'Fünfte') - topOfText(1, 'vierte'),
      closeTo(ordinaryLineSpacing, 0.1),
    );
  });

  testWidgets('offline flow separates verses with source line breaks', (
    tester,
  ) async {
    final source = chapter(43, 3, verses: 4);
    final rows = (source['chapter'] as Map)['rows'] as List;
    ((rows[1] as Map)['cells'] as List).first['segments'] = [
      'Erste Zeile',
      {'kind': 'br'},
      'zweite Zeile',
    ];
    ((rows[2] as Map)['cells'] as List).first['segments'] = [
      {
        'kind': 'nd',
        'children': [
          'Dritte Zeile',
          {'kind': 'br'},
          'vierte Zeile',
        ],
      },
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: OfflineReaderScreen(
          packages: [
            package('Bibel', 'bible', [source]),
          ],
          eInk: false,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final paragraphs = tester
        .stateList<VerseTextState>(find.byType(VerseText))
        .map((state) => state.paragraph!)
        .toList();
    expect(paragraphs, hasLength(4));
    expect(paragraphs[1].textAlign, TextAlign.start);
    expect(
      paragraphs[1].text.toPlainText(),
      '2\u00a0Erste Zeile\nzweite Zeile',
    );
    expect(paragraphs[2].textAlign, TextAlign.start);
    expect(
      paragraphs[2].text.toPlainText(),
      '3\u00a0DRITTE ZEILE\nVIERTE ZEILE',
    );
  });
  testWidgets('restores and reports the visible verse in an offline chapter', (
    tester,
  ) async {
    final changes = <Map<String, dynamic>>[];
    final work = package('Bibel', 'bible', [chapter(43, 3, verses: 100)]);
    await tester.pumpWidget(
      MaterialApp(
        home: OfflineReaderScreen(
          packages: [work],
          eInk: false,
          initialReference: const {'book': 43, 'chapter': 3, 'verse': 30},
          onPositionChanged: (_, ref) => changes.add(ref),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final scroll = tester
        .widget<CustomScrollView>(find.byType(CustomScrollView))
        .controller!;
    expect(scroll.offset, greaterThan(0));
    expect(changes.last['verse'], greaterThan(1));
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -500));
    await tester.pumpAndSettle();
    final saved = Map<String, dynamic>.from(changes.last);
    expect(saved['verse'], greaterThan(1));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      MaterialApp(
        home: OfflineReaderScreen(
          packages: [work],
          eInk: false,
          initialReference: saved,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<CustomScrollView>(find.byType(CustomScrollView))
          .controller!
          .offset,
      greaterThan(0),
    );
  });

  testWidgets(
    'does not silently change Bible when a cross-reference verse is missing',
    (tester) async {
      final books = [
        package('Erste Bibel', 'bible', [chapter(43, 3, verses: 30)]),
        package('Zweite Bibel', 'bible', [chapter(43, 3, verses: 2)]),
        package('Parallelstellen', 'xrefs', [chapter(1, 1, kind: 'xrefs')]),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: OfflineReaderScreen(
            packages: books,
            eInk: false,
            initialResourceId: 'Zweite Bibel',
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Parallelstellen').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Vers 1 → Joh3,16'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Dieser Vers ist in der gewählten Bibel offline nicht verfügbar.',
        ),
        findsOneWidget,
      );
      expect(find.text('Parallelstellen'), findsOneWidget);
      expect(find.text('Erste Bibel'), findsNothing);
    },
  );

  testWidgets('opens a cross-reference in the last selected Bible', (
    tester,
  ) async {
    final books = [
      package('Erste Bibel', 'bible', [chapter(43, 3, verses: 30)]),
      package('Zweite Bibel', 'bible', [chapter(43, 3, verses: 30)]),
      package('Parallelstellen', 'xrefs', [chapter(1, 1, kind: 'xrefs')]),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: OfflineReaderScreen(
          packages: books,
          eInk: false,
          initialResourceId: 'Zweite Bibel',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Parallelstellen').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vers 1 → Joh3,16'));
    await tester.pumpAndSettle();
    expect(find.text('Zweite Bibel'), findsOneWidget);
    expect(find.text('Erste Bibel'), findsNothing);
  });
  for (final versePerLine in [false, true]) {
    testWidgets(
      'opens a saved Strong entry without leaving the Bible (versePerLine=$versePerLine)',
      (tester) async {
        final sourceChapter = chapter(43, 3);
        final rows = (sourceChapter['chapter'] as Map)['rows'] as List;
        ((rows.first as Map)['cells'] as List).first['segments'] = [
          {'kind': 'w', 'text': 'Liebe', 'strong': 'G26'},
          {'kind': 'note', 'text': assignmentNote, 'marker': ''},
          ' ',
          {'kind': 'w', 'text': 'Liebe', 'strong': 'G26'},
        ];
        final lexicon = {
          'version': 2,
          'owner': null,
          'resource': {'id': 'lex', 'name': 'Lexikon', 'kind': 'lexicon'},
          'entries': [
            {
              'strong': 'G26',
              'language': 'grc',
              'lemma': 'ἀγάπη',
              'definitionHtml': '<p>Liebe erklärt</p>',
              'seeAlso': <String>[],
            },
          ],
        };
        await tester.pumpWidget(
          MaterialApp(
            home: OfflineReaderScreen(
              packages: [
                package('Bibel', 'bible', [sourceChapter]),
                lexicon,
              ],
              eInk: false,
              versePerLine: versePerLine,
            ),
          ),
        );
        await tester.pumpAndSettle();
        final verse = tester.widget<VerseText>(find.byType(VerseText).first);
        final word = {'kind': 'w', 'text': 'Liebe', 'strong': 'G26'};
        if (versePerLine) {
          verse.onWord!(word, 0);
        } else {
          verse.passages!.first.onWord!(word, 0);
        }
        await tester.pumpAndSettle();
        expect(
          find.textContaining('Liebe erklärt', findRichText: true),
          findsWidgets,
        );
        expect(
          find.textContaining('fachlich noch nicht bestätigt'),
          findsOneWidget,
        );
        expect(find.text('Johannes 3', skipOffstage: false), findsOneWidget);
        Navigator.of(tester.element(find.text('Zur Trefferliste'))).pop();
        await tester.pumpAndSettle();
        expect(find.text('Johannes 3'), findsOneWidget);
        if (versePerLine) {
          verse.onWord!(word, 1);
        } else {
          verse.passages!.first.onWord!(word, 1);
        }
        await tester.pumpAndSettle();
        expect(
          find.textContaining('fachlich noch nicht bestätigt'),
          findsNothing,
        );
      },
    );
  }
  testWidgets(
    'searches a saved lexicon by Strong number, word and definition without media',
    (tester) async {
      final lexicon = {
        'version': 2,
        'owner': null,
        'resource': {'id': 'lex', 'name': 'Lexikon', 'kind': 'lexicon'},
        'entries': [
          {
            'strong': 'G26',
            'language': 'grc',
            'lemma': 'ἀγάπη',
            'transliteration': 'agape',
            'definitionHtml': '<p>Love</p>',
            'germanTranslation': {
              'machineTranslated': true,
              'definitionHtml':
                  '<p>Liebe <img src="https://example.test/external.png"></p>',
            },
            'seeAlso': ['G25'],
          },
          {
            'strong': 'G25',
            'language': 'grc',
            'lemma': 'ἀγαπάω',
            'transliteration': 'agapao',
            'definitionHtml': '<p>lieben</p>',
            'seeAlso': <String>[],
          },
        ],
      };
      await tester.pumpWidget(
        MaterialApp(home: OfflineReaderScreen(packages: [lexicon], eInk: true)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Lexikon durchsuchen'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'G26');
      await tester.pumpAndSettle();
      expect(find.text('G26 · ἀγάπη'), findsOneWidget);
      expect(find.text('G25 · ἀγαπάω'), findsNothing);
      await tester.tap(find.text('G26 · ἀγάπη'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Liebe', findRichText: true), findsWidgets);
      expect(
        find.text('Maschinell übersetzter Lexikonartikel'),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate(
          (widget) => widget is Image && widget.image is NetworkImage,
        ),
        findsNothing,
      );
      await tester.tap(find.text('G25'));
      await tester.pumpAndSettle();
      expect(find.text('G25 · ἀγαπάω'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Liebe');
      // The full-text index runs in an isolate. Let real asynchronous work
      // finish instead of waiting on the animated progress indicator.
      for (
        var i = 0;
        i < 250 && find.text('G26 · ἀγάπη').evaluate().isEmpty;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      expect(find.text('G26 · ἀγάπη'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'agapao');
      await tester.pumpAndSettle();
      expect(find.text('G25 · ἀγαπάω'), findsOneWidget);
    },
  );
  testWidgets('reads Bible content and selects only saved books and chapters', (
    tester,
  ) async {
    final changes = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAkribosTheme(Brightness.light, eInk: true),
        home: OfflineReaderScreen(
          packages: [
            package('Bibel', 'bible', [
              chapter(1, 1),
              chapter(43, 3, verses: 60),
              chapter(43, 5),
            ]),
            package('Andere Bibel', 'bible', [chapter(43, 4)]),
          ],
          eInk: true,
          initialReference: const {'book': 43, 'chapter': 3, 'verse': 12},
          onPositionChanged: (id, ref) => changes.add(
            '$id:${ref['book']}:${ref['chapter']}:${ref['verse'] ?? '-'}',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Offline lesen'), findsOneWidget);
    expect(find.byType(DropdownButtonFormField<int>), findsNothing);
    final chapterThree = find.byKey(const ValueKey('passage-chapter-3'));
    final chapterFive = find.byKey(const ValueKey('passage-chapter-5'));
    await tester.tap(find.text('Buch und Kapitel · Joh3'));
    await tester.pumpAndSettle();
    expect(tester.widget<Semantics>(chapterThree).properties.selected, isTrue);
    expect(chapterFive, findsOneWidget);
    expect(find.byKey(const ValueKey('passage-chapter-4')), findsNothing);
    await tester.tap(chapterFive);
    await tester.pumpAndSettle();
    expect(find.text('Johannes 5'), findsOneWidget);
    expect(changes, contains('Bibel:43:5:-'));
    await tester.tap(find.text('Buch und Kapitel · Joh5'));
    await tester.pumpAndSettle();
    expect(tester.widget<Semantics>(chapterFive).properties.selected, isTrue);
  });

  testWidgets('scrolls across chapters in both directions', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: OfflineReaderScreen(
          packages: [
            package('Bibel', 'bible', [
              chapter(43, 2, verses: 30),
              chapter(43, 3, verses: 30),
              chapter(43, 4, verses: 30),
            ]),
          ],
          initialReference: const {'book': 43, 'chapter': 3},
          eInk: false,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Johannes 3'), findsOneWidget);
    final previousCaption = find.text('Buch und Kapitel · Joh3');
    await tester.drag(find.byType(CustomScrollView), const Offset(0, 700));
    // Paint the new position and tap before the pending caption rebuild.
    await tester.pump();
    expect(find.text('Johannes 2'), findsOneWidget);
    expect(previousCaption, findsOneWidget);
    await tester.tap(previousCaption);
    await tester.pumpAndSettle();
    final chapterTwo = find.byKey(const ValueKey('passage-chapter-2'));
    expect(tester.widget<Semantics>(chapterTwo).properties.selected, isTrue);
    Navigator.of(tester.element(chapterTwo)).pop();
    await tester.pumpAndSettle();
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -700));
    await tester.pumpAndSettle();
    expect(find.text('Johannes 3'), findsOneWidget);
  });

  testWidgets('shows saved commentary and opens a saved cross reference', (
    tester,
  ) async {
    final data = [
      package('Bibel', 'bible', [chapter(43, 3, verses: 30)]),
      package('Kommentar', 'commentary', [chapter(43, 3, kind: 'commentary')]),
      package('Parallelstellen', 'xrefs', [chapter(1, 1, kind: 'xrefs')]),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: OfflineReaderScreen(
          packages: data,
          eInk: false,
          initialResourceId: 'Kommentar',
          versePerLine: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Erklärung'), findsOneWidget);
    expect(find.text('Lokaler Kommentar', findRichText: true), findsOneWidget);
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Parallelstellen').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vers 1 → Joh3,16'));
    await tester.pumpAndSettle();
    expect(find.text('Bibel'), findsOneWidget);
    expect(
      tester
          .widget<CustomScrollView>(find.byType(CustomScrollView))
          .controller!
          .offset,
      greaterThan(0),
    );
  });

  testWidgets('shows an empty state and handles a small landscape window', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(640, 360);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(640, 360),
            textScaler: TextScaler.linear(1.7),
          ),
          child: OfflineReaderScreen(
            packages: [
              package('Bibel', 'bible', [chapter(43, 3)]),
            ],
            eInk: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Buch und Kapitel · Joh3'));
    await tester.pumpAndSettle();
    final chapterThree = find.byKey(const ValueKey('passage-chapter-3'));
    expect(chapterThree.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(chapterThree);
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      const MaterialApp(home: OfflineReaderScreen(packages: [], eInk: true)),
    );
    expect(find.text('Keine Offline-Werke verfügbar.'), findsOneWidget);
  });
}
