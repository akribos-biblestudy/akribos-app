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
      'Erste Zeile',
      {'kind': 'br'},
      'zweite Zeile',
    ];
    cells[2]['segments'] = [
      {
        'kind': 'wj',
        'children': [
          'Nächster Vers',
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
    expect(texts[1].text.toPlainText(), '2\u00a0Erste Zeile\nzweite Zeile');
    expect(texts[2].text.toPlainText(), '3\u00a0Nächster Vers\nzweite Zeile');
    expect(texts[1].textAlign, TextAlign.start);
    expect(texts[2].textAlign, TextAlign.start);
    expect(texts[3].textAlign, TextAlign.justify);
    expect(
      texts[3].text.toPlainText(),
      contains('4\u00a0Fortsetzung. 5\u00a0Weitere Fortsetzung.'),
    );
  });
}
