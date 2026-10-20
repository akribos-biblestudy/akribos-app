import 'package:akribos_app/features/reader/verse_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'unchanged flow content retains shaped text and uses the latest actions',
    (tester) async {
      final calls = <String>[];
      const segments = <dynamic>[
        {'kind': 'w', 'text': 'Wort', 'strong': 'G3056'},
        {'kind': 'note', 'marker': '1', 'text': 'Eine Erklärung.'},
        ' bleibt sichtbar.',
      ];
      Widget reader(int generation) => MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 350,
            child: VerseText(
              segments: const [],
              selectable: false,
              passages: [
                for (var verse = 1; verse <= 2; verse++)
                  VersePassage(
                    segments: segments,
                    number: '$verse',
                    // Reader rebuilds these wrappers on tab/position changes.
                    highlights: [
                      {'start': 0, 'end': 1, 'color': '#facc15'},
                    ],
                    onOpen: () => calls.add('$generation:verse:$verse'),
                    onWord: (word, position) =>
                        calls.add('$generation:word:$verse:$position'),
                  ),
              ],
            ),
          ),
        ),
      );

      await tester.pumpWidget(reader(0));
      final state = tester.state<VerseTextState>(find.byType(VerseText));
      final before = state.paragraph!.text;
      final paintBefore = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((paint) => paint.foregroundPainter)
          .whereType<VerseNotePainter>()
          .single;
      final overlayBefore = paintBefore.textPainter.text;

      await tester.pumpWidget(reader(1));
      expect(state.paragraph!.text, same(before));
      final paintAfter = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((paint) => paint.foregroundPainter)
          .whereType<VerseNotePainter>()
          .single;
      expect(paintAfter, same(paintBefore));
      expect(paintAfter.textPainter.text, same(overlayBefore));

      Future<void> tapText(String text, {bool last = false}) async {
        final paragraph = state.paragraph!;
        final plain = paragraph.text.toPlainText(includeSemanticsLabels: false);
        final start = last ? plain.lastIndexOf(text) : plain.indexOf(text);
        final box = paragraph
            .getBoxesForSelection(
              TextSelection(
                baseOffset: start,
                extentOffset: start + text.length,
              ),
            )
            .first;
        await tester.tapAt(paragraph.localToGlobal(box.toRect().center));
        await tester.pump();
      }

      await tapText('1');
      await tapText('Wort');
      await tapText('2');
      await tapText('Wort', last: true);
      expect(calls, ['1:verse:1', '1:word:1:0', '1:verse:2', '1:word:2:0']);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('presentation changes invalidate cached verse content', (
    tester,
  ) async {
    const original = <dynamic>['Das Wort bleibt.'];
    Widget reader({
      List<dynamic> segments = original,
      double fontSize = 19,
      double scale = 1,
      Color seed = Colors.green,
      String highlight = '#facc15',
      List<String> needles = const [],
    }) => MaterialApp(
      theme: ThemeData(colorSchemeSeed: seed),
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: Scaffold(
          body: VerseText(
            segments: segments,
            fontSize: fontSize,
            needles: needles,
            selectable: false,
            highlights: [
              {'start': 0, 'end': 1, 'color': highlight},
            ],
          ),
        ),
      ),
    );

    await tester.pumpWidget(reader());
    final state = tester.state<VerseTextState>(find.byType(VerseText));
    final paint = find.descendant(
      of: find.byType(VerseText),
      matching: find.byType(CustomPaint),
    );
    var previous = tester.widget<CustomPaint>(paint);
    for (final changed in [
      reader(fontSize: 23),
      reader(fontSize: 23, scale: 1.6),
      reader(seed: Colors.blue),
      reader(highlight: '#ff0000'),
      reader(needles: ['Wort']),
      reader(segments: ['Ein neuer Text.']),
    ]) {
      await tester.pumpWidget(changed);
      final current = tester.widget<CustomPaint>(paint);
      expect(current, isNot(same(previous)));
      previous = current;
    }
    expect(state.paragraph!.text.toPlainText(), 'Ein neuer Text.');
    expect(tester.takeException(), isNull);
  });
}
