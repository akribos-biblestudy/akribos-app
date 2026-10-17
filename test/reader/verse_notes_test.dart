import 'package:akribos_app/features/reader/verse_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await (FontLoader('AkribosText')
          ..addFont(rootBundle.load('assets/fonts/akribos-text-regular.ttf')))
        .load();
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
      expect(paragraph.text.toPlainText(), 'Das Wort\u2060\ufffc ');
      final box = paragraph
          .getBoxesForSelection(
            const TextSelection(baseOffset: 4, extentOffset: 8),
          )
          .single;
      final marker = tester.getRect(find.text('*, 17'));
      final word = box.toRect().shift(paragraph.localToGlobal(Offset.zero));
      expect(marker.left, closeTo(word.right, .5));
      expect(marker.bottom, lessThan(word.bottom - 2));
      await tester.tap(find.text('*, 17'));
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
      final marker = tester.getRect(find.text('7'));
      expect(marker.left, closeTo(word.right, .5), reason: 'width $width');
      expect(marker.top, lessThan(word.bottom), reason: 'width $width');
    }
  });
  testWidgets(
    'later verses keep scroll/action offsets after note placeholders',
    (tester) async {
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
      final text = paragraph.text.toPlainText();
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
            TextSelection(
              baseOffset: numberStart,
              extentOffset: numberStart + 1,
            ),
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
    },
  );
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
      widths.add(tester.getRect(find.text('7')).width);
    }
    expect(widths.last, closeTo(widths.first * 2, .1));
    expect(tester.takeException(), isNull);
  });
}
