import 'package:akribos_app/features/reader/offline_lexicon_search.dart';
import 'package:akribos_app/features/reader/offline_reader_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('normalizes accepted Strong forms and rejects out of range IDs', () {
    expect(normalizeOfflineStrongId(' g 0026 '), 'G26');
    expect(normalizeOfflineStrongId('h00430'), 'H430');
    expect(normalizeOfflineStrongId('G6021'), isNull);
    expect(normalizeOfflineStrongId('H0'), isNull);
  });

  test(
    'indexes Greek, Hebrew and Latin text independent of common accents',
    () {
      expect(normalizeOfflineLexiconText('ἀγάπη'), 'αγαπη');
      expect(normalizeOfflineLexiconText('a\u0301'), 'a');
      expect(normalizeOfflineLexiconText('שָׁלוֹם'), 'שלום');
      expect(normalizeOfflineLexiconText('Füße'), 'fusse');
      final result = buildOfflineLexiconSearchIndex([
        {
          'strong': 'G26',
          'lemma': 'ἀγάπη',
          'definitionHtml': '<p>Güte</p>',
          'germanTranslation': {'definitionHtml': '<p>Herz</p>'},
        },
      ]).single;
      expect(result, contains('αγαπη'));
      expect(result, contains('gute'));
      expect(result, contains('herz'));
      expect(result, isNot(contains('<p>')));
    },
  );

  testWidgets('normalizes Strong input, and searches unaccented words', (
    tester,
  ) async {
    final lexicon = {
      'version': 2,
      'owner': null,
      'resource': {'id': 'lex', 'name': 'Lexikon', 'kind': 'lexicon'},
      'entries': [
        {
          'strong': 'G26',
          'lemma': 'ἀγάπη',
          'definitionHtml': '<p>Güte</p>',
          'seeAlso': <String>[],
        },
        {'strong': 'G260', 'lemma': 'other', 'seeAlso': <String>[]},
      ],
    };
    await tester.pumpWidget(
      MaterialApp(home: OfflineReaderScreen(packages: [lexicon], eInk: false)),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'g0026');
    await tester.pumpAndSettle();
    expect(find.text('G26 · ἀγάπη'), findsOneWidget);
    expect(find.text('G260 · other'), findsNothing);
    await tester.enterText(find.byType(TextField), 'αγαπη');
    for (
      var i = 0;
      i < 100 && find.text('G26 · ἀγάπη').evaluate().isEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    expect(find.text('G26 · ἀγάπη'), findsOneWidget);
  });

  testWidgets('rebuilds the search index when a saved lexicon is replaced', (
    tester,
  ) async {
    Map<String, dynamic> lexicon(List<Map<String, dynamic>> entries) => {
      'version': 2,
      'owner': null,
      'resource': {'id': 'lex', 'name': 'Lexikon', 'kind': 'lexicon'},
      'entries': entries,
    };
    final first = lexicon([
      {'strong': 'G1', 'lemma': 'alpha', 'seeAlso': <String>[]},
    ]);
    await tester.pumpWidget(
      MaterialApp(home: OfflineReaderScreen(packages: [first], eInk: false)),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'alpha');
    for (
      var i = 0;
      i < 250 && find.text('G1 · alpha').evaluate().isEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(find.text('G1 · alpha'), findsOneWidget);
    final replacement = lexicon([
      {'strong': 'G2', 'lemma': 'beta', 'seeAlso': <String>[]},
      {'strong': 'G3', 'lemma': 'betamax', 'seeAlso': <String>[]},
    ]);
    await tester.pumpWidget(
      MaterialApp(
        home: OfflineReaderScreen(packages: [replacement], eInk: false),
      ),
    );
    await tester.enterText(find.byType(TextField), 'beta');
    for (var i = 0; i < 250 && find.text('G2 · beta').evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(find.text('G2 · beta'), findsOneWidget);
    expect(find.text('G3 · betamax'), findsOneWidget);
    expect(find.text('G1 · alpha'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
