import 'package:akribos_app/core/json.dart';
import 'package:akribos_app/features/reader/reader_screen.dart';
import 'package:akribos_app/features/reader/verse_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'native_reader_test.dart' show ReaderApi, readerFixture, app;

void main() {
  testWidgets('source line breaks separate verse blocks in flow text', (
    tester,
  ) async {
    final data = readerFixture()..['versePerLine'] = false;
    final chapter = asMap(asMaps(data['columns']).first['initialChapter']);
    final rows = asMap(chapter['chapter'])['rows'] as List;
    rows.removeRange(5, rows.length);
    final cells = [for (final row in rows) asMaps(asMap(row)['cells']).first];
    cells[0]['segments'] = ['Einleitung.'];
    cells[1]['segments'] = [
      'Erste Zeile,\n  ',
      {'kind': 'br'},
      'zweite Zeile',
    ];
    cells[2]['segments'] = [
      {
        'kind': 'wj',
        'children': [
          'Nächster Vers,\n  ',
          {'kind': 'br'},
          'zweite Zeile',
        ],
      },
    ];
    cells[3]['segments'] = ['Fortsetzung.'];
    cells[4]['segments'] = ['Weitere Fortsetzung.'];
    final api = ReaderApi(data);
    addTearDown(api.dispose);
    await tester.pumpWidget(app(api, const ReaderScreen(path: '/Joh1')));
    await tester.pumpAndSettle();
    final texts = tester
        .stateList<VerseTextState>(find.byType(VerseText))
        .map((s) => s.paragraph!)
        .toList();
    expect(texts, hasLength(4));
    expect(texts[1].text.toPlainText(), '2\u00a0Erste Zeile,\nzweite Zeile');
    expect(texts[2].text.toPlainText(), '3\u00a0Nächster Vers,\nzweite Zeile');
    final endOfFirstVerse =
        texts[1].localToGlobal(Offset.zero).dy + texts[1].size.height;
    final startOfNextVerse = texts[2].localToGlobal(Offset.zero).dy;
    expect(startOfNextVerse - endOfFirstVerse, closeTo(0, 0.1));
    expect(texts[1].textAlign, TextAlign.start);
    expect(texts[2].textAlign, TextAlign.start);
    expect(texts[3].textAlign, TextAlign.justify);
    expect(
      texts[3].text.toPlainText(),
      contains('4\u00a0Fortsetzung. 5\u00a0Weitere Fortsetzung.'),
    );
  });

  testWidgets('versewise poetry uses normal line spacing between verses', (
    tester,
  ) async {
    final data = readerFixture()..['versePerLine'] = true;
    final chapter = asMap(asMaps(data['columns']).first['initialChapter']);
    final rows = asMap(chapter['chapter'])['rows'] as List;
    rows.removeRange(2, rows.length);
    final cells = [for (final row in rows) asMaps(asMap(row)['cells']).first];
    cells[0]['segments'] = [
      'Erste Zeile,',
      {'kind': 'br'},
      'zweite Zeile',
    ];
    cells[1]['segments'] = [
      'Dritte Zeile,',
      {'kind': 'br'},
      'vierte Zeile',
    ];
    final api = ReaderApi(data);
    addTearDown(api.dispose);
    await tester.pumpWidget(app(api, const ReaderScreen(path: '/Joh1')));
    await tester.pumpAndSettle();
    final texts = tester
        .stateList<VerseTextState>(find.byType(VerseText))
        .map((state) => state.paragraph!)
        .toList();
    expect(texts, hasLength(2));
    expect(texts[0].text.toPlainText(), '1\u00a0Erste Zeile,\nzweite Zeile');
    expect(texts[1].text.toPlainText(), '2\u00a0Dritte Zeile,\nvierte Zeile');

    double topOfText(int index, String text) {
      final paragraph = texts[index];
      final start = paragraph.text.toPlainText().indexOf(text);
      expect(start, greaterThanOrEqualTo(0));
      final box = paragraph
          .getBoxesForSelection(
            TextSelection(baseOffset: start, extentOffset: start + 1),
          )
          .single;
      return paragraph.localToGlobal(Offset(box.left, box.top)).dy;
    }

    final lineSpacing = topOfText(0, 'zweite') - topOfText(0, 'Erste');
    expect(
      topOfText(1, 'Dritte') - topOfText(0, 'zweite'),
      closeTo(lineSpacing, 0.1),
    );
    expect(
      topOfText(1, 'vierte') - topOfText(1, 'Dritte'),
      closeTo(lineSpacing, 0.1),
    );
  });
}
