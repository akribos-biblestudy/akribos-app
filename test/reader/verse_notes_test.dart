import 'dart:ui' as ui;

import 'package:akribos_app/features/reader/verse_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

VerseNotePainter notePainter(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .map((widget) => widget.foregroundPainter)
    .whereType<VerseNotePainter>()
    .single;

Rect markerRect(WidgetTester tester, [int index = 0]) {
  final painter = notePainter(tester);
  return painter
      .rectangles(painter.notes[index])
      .single
      .shift(painter.paragraph()!.localToGlobal(Offset.zero));
}

class _NoteRecordingCanvas extends TestRecordingCanvas {
  @override
  Rect getLocalClipBounds() => Rect.largest;
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await (FontLoader('AkribosText')
          ..addFont(rootBundle.load('assets/fonts/akribos-text-regular.ttf')))
        .load();
    await (FontLoader('NotoSansHebrew')..addFont(
          rootBundle.load(
            'assets/fonts/noto-sans-hebrew-hebrew-400-normal.ttf',
          ),
        ))
        .load();
  });

  test('source indentation before br does not add a second line break', () {
    final segments = <dynamic>[
      {'kind': 'w', 'text': 'Rühmt', 'strong': 'H1984'},
      {'kind': 'note', 'marker': 'a', 'text': 'Erste Anmerkung'},
      ' seinen Namen!\n  ',
      {'kind': 'br'},
      {'kind': 'w', 'text': 'Freut', 'strong': 'H8055'},
      {'kind': 'note', 'marker': 'b', 'text': 'Zweite Anmerkung'},
      '.',
    ];
    final runs = verseRuns(segments);
    expect(
      runs.where((run) => run.note == null).map((run) => run.text).join(),
      'Rühmt seinen Namen!\nFreut.',
    );
    final words = runs.where((run) => run.word != null).toList();
    expect(words.map((run) => run.position), [0, 1]);
    expect(words.map((run) => run.wordIndex), [0, 3]);
    expect(words.map((run) => strongNumbers(run.word!)), [
      ['H1984'],
      ['H8055'],
    ]);
    expect(runs.where((run) => run.note != null).map((run) => run.note), [
      'Erste Anmerkung',
      'Zweite Anmerkung',
    ]);
    expect(segments[2], ' seinen Namen!\n  ');
  });

  test('distinct explicit line breaks remain distinct', () {
    expect(
      verseRuns([
        'Erste Zeile\n  ',
        {'kind': 'br'},
        '  \n',
        {'kind': 'br'},
        'Dritte Zeile',
      ]).map((run) => run.text).join(),
      'Erste Zeile\n\nDritte Zeile',
    );
    expect(
      verseRuns([
        'Erste Zeile',
        {'kind': 'br'},
        'Zweite Zeile',
      ]).map((run) => run.text).join(),
      'Erste Zeile\nZweite Zeile',
    );
  });

  test('source line breaks without br stay unchanged', () {
    expect(
      verseRuns(['Zeile eins\n  Zeile zwei']).map((run) => run.text).join(),
      'Zeile eins\n  Zeile zwei',
    );
  });

  test(
    'verse notes merge with final word notes without changing source positions',
    () {
      final first = {'kind': 'w', 'text': 'Anfang', 'strong': 'G746'};
      final last = {'kind': 'w', 'text': 'Wort', 'strong': 'G3056'};
      final segments = [
        {'kind': 'note', 'marker': '', 'text': '1,1: Siehe auch 1Mo 1,1.'},
        'Im ',
        first,
        {'kind': 'note', 'marker': '1', 'text': 'Beginn.'},
        ' war das ',
        {
          'kind': 'nd',
          'children': [
            last,
            {'kind': 'note', 'marker': '2', 'text': 'Griechisch: Logos.'},
          ],
        },
        '.',
      ];
      final runs = verseRuns(segments);
      expect(runs.where((run) => run.word != null).map((run) => run.position), [
        0,
        1,
      ]);
      expect(
        runs.where((run) => run.word != null).map((run) => run.wordIndex),
        [1, 4],
      );
      expect(
        runs.where((run) => run.note == null).map((run) => run.text).join(),
        'Im Anfang war das Wort.',
      );
      final notes = runs.where((run) => run.note != null).toList();
      expect(notes, hasLength(2));
      expect(notes.first.text, '1');
      expect(runs.last, same(notes.last));
      expect(notes.last.text, '*, 2');
      expect(
        notes.last.note,
        '*: 1,1: Siehe auch 1Mo 1,1.\n\n2: Griechisch: Logos.',
      );
      expect(segments.first, {
        'kind': 'note',
        'marker': '',
        'text': '1,1: Siehe auch 1Mo 1,1.',
      });
      expect(versePlainText(segments), 'Im Anfang war das Wort.');
    },
  );

  test(
    'assignment warnings remain word bound and separate from verse notes',
    () {
      final runs = verseRuns([
        {'kind': 'note', 'marker': '', 'text': 'Vershinweis'},
        {'kind': 'w', 'text': 'Wort', 'strong': 'G3056'},
        {'kind': 'note', 'marker': '', 'text': assignmentNote},
        '.',
      ], studiedStrong: 'G3056');
      expect(runs.where((run) => run.note != null), hasLength(2));
      expect(runs[1].assignment, isTrue);
      expect(runs.last.note, 'Vershinweis');
    },
  );

  testWidgets(
    'source markers attach directly above the baseline and open combined text',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 250,
              child: VerseText(
                selectable: false,
                fontSize: 24,
                segments: [
                  {'kind': 'note', 'marker': '', 'text': 'Vershinweis'},
                  'Das Wort ',
                  {'kind': 'note', 'marker': '17', 'text': 'Worterklärung'},
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final paragraph = tester
          .state<VerseTextState>(find.byType(VerseText))
          .paragraph!;
      expect(
        paragraph.text.toPlainText(includeSemanticsLabels: false),
        'Das Wort\u2060*,\u00a017 ',
      );
      final box = paragraph
          .getBoxesForSelection(
            const TextSelection(baseOffset: 4, extentOffset: 8),
          )
          .single;
      final marker = markerRect(tester);
      final word = box.toRect().shift(paragraph.localToGlobal(Offset.zero));
      expect(marker.left, closeTo(word.right, .5));
      expect(marker.bottom, lessThan(word.bottom - 2));
      await tester.tapAt(marker.center);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('*: Vershinweis\n\n17: Worterklärung'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('superscript markers never wrap away from their word', (
    tester,
  ) async {
    for (var width = 100.0; width < 160; width += 3) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: width,
                child: const VerseText(
                  selectable: false,
                  segments: [
                    'Am Anfang war Wort',
                    {'kind': 'note', 'marker': '7', 'text': 'Hinweis'},
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      final paragraph = tester
          .state<VerseTextState>(find.byType(VerseText))
          .paragraph!;
      final word = paragraph
          .getBoxesForSelection(
            const TextSelection(baseOffset: 14, extentOffset: 18),
          )
          .single
          .toRect()
          .shift(paragraph.localToGlobal(Offset.zero));
      final marker = markerRect(tester);
      expect(marker.left, closeTo(word.right, .5), reason: 'width $width');
      expect(marker.top, lessThan(word.bottom), reason: 'width $width');
    }
  });
  testWidgets('later verses keep scroll/action offsets after note markers', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 170,
            child: VerseText(
              segments: [],
              selectable: false,
              passages: [
                VersePassage(
                  number: '1',
                  segments: [
                    'Am Anfang stand das Wort.',
                    {'kind': 'note', 'marker': '17', 'text': 'Erklärung'},
                  ],
                ),
                VersePassage(
                  number: '2',
                  segments: ['Später kam ein weiterer Vers.'],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    final state = tester.state<VerseTextState>(find.byType(VerseText));
    final paragraph = state.paragraph!;
    final text = paragraph.text.toPlainText(includeSemanticsLabels: false);
    final offset = text.indexOf('Später');
    final box = paragraph
        .getBoxesForSelection(
          TextSelection(baseOffset: offset, extentOffset: offset + 6),
        )
        .single;
    expect(state.passageAt(box.toRect().center), 1);
    final numberStart = text.lastIndexOf('2\u00a0');
    final number = paragraph
        .getBoxesForSelection(
          TextSelection(baseOffset: numberStart, extentOffset: numberStart + 1),
        )
        .single;
    expect(
      number.top,
      greaterThan(box.top),
      reason: 'The smaller number must not define the scrolling crop.',
    );
    expect(state.passageTop(1), greaterThan(0));
    expect(state.passageTop(1), lessThanOrEqualTo(box.top));
    expect(tester.takeException(), isNull);
  });
  testWidgets('superscripts scale once with accessibility text size', (
    tester,
  ) async {
    final widths = <double>[];
    for (final scale in [1.0, 2.0]) {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: const Scaffold(
              body: VerseText(
                selectable: false,
                segments: [
                  'Wort',
                  {'kind': 'note', 'marker': '7', 'text': 'Erklärung'},
                ],
              ),
            ),
          ),
        ),
      );
      widths.add(markerRect(tester).width);
    }
    expect(widths.last, closeTo(widths.first * 2, .1));
    expect(tester.takeException(), isNull);
  });
  testWidgets('justified verse endings keep punctuation and markers together', (
    tester,
  ) async {
    for (final scale in [1.0, 2.0]) {
      for (var width = 280.0; width <= 400; width += 10) {
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
                    passages: [
                      for (var verse = 1; verse <= 7; verse++)
                        VersePassage(
                          number: '$verse',
                          segments: [
                            {
                              'kind': 'note',
                              'text': 'Ein Hinweis zum ganzen Absatz.',
                            },
                            'Dieser längere Beispieltext verbindet mehrere Absätze. ',
                            {'kind': 'w', 'text': 'Menschen', 'strong': 'G444'},
                            '.',
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        final painter = notePainter(tester);
        for (final note in painter.notes) {
          final previous = painter
              .paragraph()!
              .getBoxesForSelection(
                TextSelection(
                  baseOffset: note.start - 2,
                  extentOffset: note.start - 1,
                ),
              )
              .single;
          final marker = painter.rectangles(note).single;
          expect(
            marker.top,
            lessThan(previous.bottom),
            reason: 'width=$width scale=$scale note=${note.start}',
          );
          expect(
            marker.left,
            closeTo(previous.right, .5),
            reason: 'width=$width scale=$scale',
          );
        }
      }
    }
  });

  testWidgets('painted markers retain paragraph bidi shaping and every line', (
    tester,
  ) async {
    for (final direction in TextDirection.values) {
      for (final scale in [1.0, 2.0]) {
        for (final marker in [
          '17, א',
          'א, 17',
          '١٢, *',
          'a, 17',
          '17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28',
        ]) {
          await tester.pumpWidget(
            MaterialApp(
              home: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                child: Scaffold(
                  body: SizedBox(
                    width: 180,
                    child: VerseText(
                      selectable: false,
                      direction: direction,
                      segments: [
                        direction == TextDirection.rtl
                            ? 'דבר Word.'
                            : 'Ein דבר.',
                        {'kind': 'note', 'marker': marker, 'text': 'Hinweis'},
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
          final painter = notePainter(tester);
          final native = painter.paragraph()!;
          final canvas = _NoteRecordingCanvas();
          painter.paint(canvas, native.size);
          final draw = canvas.invocations
              .map((entry) => entry.invocation)
              .where((entry) => entry.memberName == #drawParagraph)
              .single;
          final painted = draw.positionalArguments[0] as ui.Paragraph;
          final origin = draw.positionalArguments[1] as Offset;
          final note = painter.notes.single;
          for (
            var index = note.start;
            index < note.start + note.text.length;
            index++
          ) {
            final expected = native.getBoxesForSelection(
              TextSelection(baseOffset: index, extentOffset: index + 1),
            );
            final actual = painted.getBoxesForRange(index, index + 1);
            final reason =
                '$direction scale=$scale marker=$marker index=$index';
            expect(actual, hasLength(expected.length), reason: reason);
            for (var box = 0; box < expected.length; box++) {
              final position = actual[box].toRect().shift(origin);
              final target = expected[box].toRect().shift(
                Offset(0, -painter.lift),
              );
              expect(position.left, closeTo(target.left, .01), reason: reason);
              expect(position.top, closeTo(target.top, .01), reason: reason);
              expect(
                position.right,
                closeTo(target.right, .01),
                reason: reason,
              );
              expect(
                position.bottom,
                closeTo(target.bottom, .01),
                reason: reason,
              );
            }
          }
          if (marker == '17, א' && scale == 1) {
            for (final rect in painter.rectangles(note)) {
              await tester.tapAt(
                rect.center + native.localToGlobal(Offset.zero),
              );
              await tester.pumpAndSettle();
              expect(find.byType(AlertDialog), findsOneWidget);
              expect(find.text('Hinweis'), findsOneWidget);
              await tester.tap(find.text('Schließen'));
              await tester.pumpAndSettle();
            }
          }
          expect(tester.takeException(), isNull);
        }
      }
    }
  });

  for (final selectable in [false, true]) {
    testWidgets(
      'raised note top and center are tappable, selectable=$selectable',
      (tester) async {
        final semantics = tester.ensureSemantics();
        try {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: VerseText(
                  selectable: selectable,
                  segments: const [
                    'Wort.',
                    {'kind': 'note', 'marker': '7', 'text': 'Hinweisinhalt'},
                  ],
                ),
              ),
            ),
          );
          for (final atTop in [true, false]) {
            final marker = markerRect(tester);
            await tester.tapAt(
              atTop ? marker.topCenter + const Offset(0, .5) : marker.center,
            );
            await tester.pumpAndSettle();
            expect(find.byType(AlertDialog), findsOneWidget);
            expect(find.text('Hinweisinhalt'), findsOneWidget);
            await tester.tap(find.text('Schließen'));
            await tester.pumpAndSettle();
          }
          final note = find.semantics
              .byLabel('Hinweis 7 öffnen')
              .evaluate()
              .single;
          expect(
            note.getSemanticsData().hasAction(ui.SemanticsAction.tap),
            isTrue,
          );
          expect(tester.takeException(), isNull);
        } finally {
          semantics.dispose();
        }
      },
    );
  }
}
