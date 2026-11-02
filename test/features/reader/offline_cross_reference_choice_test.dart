import 'package:akribos_app/features/reader/offline_reader_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'offline_reader_screen_test.dart' show chapter, package;

void main() {
  testWidgets('asks for the Bible when no translation has been selected', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: OfflineReaderScreen(
          packages: [
            package('Erste Bibel', 'bible', [chapter(43, 3, verses: 30)]),
            package('Zweite Bibel', 'bible', [chapter(43, 3, verses: 30)]),
            package('Parallelstellen', 'xrefs', [chapter(1, 1, kind: 'xrefs')]),
          ],
          initialResourceId: 'Parallelstellen',
          eInk: false,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vers 1 → Joh3,16'));
    await tester.pumpAndSettle();
    expect(find.text('Bibel für die Parallelstelle auswählen'), findsOneWidget);
    await tester.tap(find.text('Zweite Bibel'));
    await tester.pumpAndSettle();
    expect(find.text('Zweite Bibel'), findsOneWidget);
    expect(find.text('Erste Bibel'), findsNothing);
  });
}
