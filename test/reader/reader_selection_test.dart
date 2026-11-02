import 'package:akribos_app/core/api_client.dart';
import 'package:akribos_app/features/reader/reader_screen.dart';
import 'package:akribos_app/features/reader/verse_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'native_reader_test.dart' show ReaderApi, app, readerFixture;

class SelectionApi extends ReaderApi {
  SelectionApi(super.data, {this.failAt});
  final int? failAt;
  int writes = 0;
  static const documentId = '11111111-1111-4111-8111-111111111111';

  @override
  Future<Json> page(String path) async {
    if (path == '/notes/$documentId') {
      return {
        'document': {'revision': 1},
      };
    }
    return super.page(path);
  }

  @override
  Future<ApiResult> action(String path, String action, Json fields) async {
    actions.add({'path': path, 'action': action, 'fields': fields});
    writes++;
    if (writes == failAt) {
      return const ApiResult(
        type: 'failure',
        status: 500,
        data: {'message': 'Fehler'},
      );
    }
    return ApiResult(
      type: 'success',
      status: 200,
      data: {
        if (action == 'addToList')
          'listId': fields['listId'] == '' ? 'new-list' : fields['listId'],
        if (action == 'create') 'documentId': documentId,
        if (action == 'addPassage') 'revision': asInt(fields['revision']) + 1,
      },
    );
  }
}

Future<void> selectVerse(
  WidgetTester tester,
  int verse, {
  bool longPress = false,
  bool flow = false,
}) async {
  final finder = flow
      ? find.byType(VerseText).first
      : find.byWidgetPredicate(
          (w) =>
              w is VerseText &&
              (w.verseNumber == '$verse' ||
                  (w.verseNumber?.startsWith('$verse–') ?? false)),
        );
  final paragraph = tester.state<VerseTextState>(finder).paragraph!;
  final text = paragraph.text.toPlainText(includeSemanticsLabels: false);
  final start = flow ? text.indexOf('$verse\u00a0') : 0;
  final rect = paragraph
      .getBoxesForSelection(
        TextSelection(baseOffset: start, extentOffset: start + 1),
      )
      .first
      .toRect();
  final point = paragraph.localToGlobal(rect.center);
  if (longPress) {
    await tester.longPressAt(point);
  } else {
    await tester.tapAt(point);
  }
  await tester.pumpAndSettle();
}

void main() {
  for (final flow in [false, true]) {
    testWidgets(
      'long press and tap toggle independent verses in ${flow ? 'flow' : 'versewise'}',
      (tester) async {
        tester.view.physicalSize = const Size(500, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final api = SelectionApi(readerFixture()..['versePerLine'] = !flow);
        addTearDown(api.dispose);
        await tester.pumpWidget(app(api, const ReaderScreen(path: '/Joh1')));
        await tester.pumpAndSettle();
        await selectVerse(tester, 1, longPress: true, flow: flow);
        expect(find.byTooltip('Auswahl markieren'), findsOneWidget);
        await selectVerse(tester, 3, flow: flow);
        if (flow) {
          final passages = tester
              .widget<VerseText>(find.byType(VerseText).first)
              .passages!;
          expect(passages.take(3).map((p) => p.selected), [true, false, true]);
        } else {
          expect(
            tester
                .widget<VerseText>(
                  find.byWidgetPredicate(
                    (w) => w is VerseText && w.verseNumber == '1',
                  ),
                )
                .selected,
            isTrue,
          );
          expect(
            tester
                .widget<VerseText>(
                  find.byWidgetPredicate(
                    (w) => w is VerseText && w.verseNumber == '2',
                  ),
                )
                .selected,
            isFalse,
          );
          expect(
            tester
                .widget<VerseText>(
                  find.byWidgetPredicate(
                    (w) => w is VerseText && w.verseNumber == '3',
                  ),
                )
                .selected,
            isTrue,
          );
        }
        await selectVerse(tester, 3, flow: flow);
        expect(find.byTooltip('Auswahl aufheben'), findsOneWidget);
        await selectVerse(tester, 1, flow: flow);
        expect(find.byTooltip('Auswahl aufheben'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('verse menu exposes an accessible selection entry', (
    tester,
  ) async {
    final api = SelectionApi(readerFixture());
    addTearDown(api.dispose);
    await tester.pumpWidget(app(api, const ReaderScreen(path: '/Joh1')));
    await tester.pumpAndSettle();
    tester.widget<VerseText>(find.byType(VerseText).first).onVerseNumber!();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Vers auswählen'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Auswahl aufheben'), findsOneWidget);
    expect(
      tester.widget<VerseText>(find.byType(VerseText).first).selected,
      isTrue,
    );
  });

  testWidgets(
    'noncontiguous selection sends separate writes and retains unconfirmed verses',
    (tester) async {
      tester.view.physicalSize = const Size(500, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = SelectionApi(readerFixture(), failAt: 2);
      addTearDown(api.dispose);
      await tester.pumpWidget(app(api, const ReaderScreen(path: '/Joh1')));
      await tester.pumpAndSettle();
      await selectVerse(tester, 1, longPress: true);
      await selectVerse(tester, 3);
      await tester.tap(find.byTooltip('Auswahl markieren'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Verheißung').last);
      await tester.pumpAndSettle();
      expect(api.actions.map((a) => asMap(a['fields'])['reference']), [
        'Joh1,1',
        'Joh1,3',
      ]);
      expect(find.textContaining('1 von 2 Versen bestätigt'), findsOneWidget);
      expect(
        tester
            .widget<VerseText>(
              find.byWidgetPredicate(
                (w) => w is VerseText && w.verseNumber == '3',
              ),
            )
            .selected,
        isTrue,
      );
      expect(
        tester
            .widget<VerseText>(
              find.byWidgetPredicate(
                (w) => w is VerseText && w.verseNumber == '1',
              ),
            )
            .selected,
        isFalse,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('note links disjoint verses with successive revisions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(500, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = SelectionApi(readerFixture());
    addTearDown(api.dispose);
    String? opened;
    await tester.pumpWidget(
      app(
        api,
        const ReaderScreen(path: '/Joh1'),
        open: (path) async {
          opened = path;
        },
      ),
    );
    await tester.pumpAndSettle();
    await selectVerse(tester, 1, longPress: true);
    await selectVerse(tester, 3);
    await tester.tap(find.byTooltip('Notiz zur Auswahl'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Meine Notiz');
    await tester.tap(find.text('Übernehmen'));
    await tester.pumpAndSettle();
    expect(api.actions.map((a) => a['action']), ['create', 'addPassage']);
    expect(asMap(api.actions[0]['fields']), containsPair('passage', 'Joh1,1'));
    expect(asMap(api.actions[1]['fields']), containsPair('passage', 'Joh1,3'));
    expect(asMap(api.actions[1]['fields']), containsPair('revision', 1));
    expect(opened, '/notes/${SelectionApi.documentId}?returnTo=%2F');
    expect(tester.takeException(), isNull);
  });

  testWidgets('note conflict stops later writes and offers the created note', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(500, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = SelectionApi(readerFixture(), failAt: 2);
    addTearDown(api.dispose);
    String? opened;
    await tester.pumpWidget(
      app(
        api,
        const ReaderScreen(path: '/Joh1'),
        open: (path) async {
          opened = path;
        },
      ),
    );
    await tester.pumpAndSettle();
    await selectVerse(tester, 1, longPress: true);
    await selectVerse(tester, 2);
    await selectVerse(tester, 3);
    await tester.tap(find.byTooltip('Notiz zur Auswahl'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Meine Notiz');
    await tester.tap(find.text('Übernehmen'));
    await tester.pumpAndSettle();
    expect(api.actions.map((a) => a['action']), ['create', 'addPassage']);
    expect(find.textContaining('1 von 3 Stellen bestätigt'), findsOneWidget);
    await tester.tap(find.text('Notiz öffnen'));
    await tester.pumpAndSettle();
    expect(opened, '/notes/${SelectionApi.documentId}?returnTo=%2F');
    expect(tester.takeException(), isNull);
  });

  testWidgets('new collection reuses returned id for subsequent verses', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(500, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final data = readerFixture();
    final chapter = asMap(asMaps(data['columns']).first['initialChapter']);
    final rows = asMap(chapter['chapter'])['rows'] as List;
    asMap((asMap(rows.first)['cells'] as List).first)['verseEnd'] = 2;
    rows.removeAt(1);
    final api = SelectionApi(data);
    addTearDown(api.dispose);
    await tester.pumpWidget(app(api, const ReaderScreen(path: '/Joh1')));
    await tester.pumpAndSettle();
    await selectVerse(tester, 1, longPress: true);
    await selectVerse(tester, 3);
    await tester.tap(find.byTooltip('Auswahl zu Sammlungen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Neue Sammlung mit diesen Versen'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Meine Sammlung');
    await tester.tap(find.text('Übernehmen'));
    await tester.pumpAndSettle();
    expect(api.actions.map((a) => a['action']), [
      'addToList',
      'addToList',
      'addToList',
    ]);
    expect(asMap(api.actions[0]['fields']), containsPair('listId', ''));
    expect(asMap(api.actions[1]['fields']), containsPair('listId', 'new-list'));
    expect(
      asMap(api.actions[1]['fields']),
      containsPair('reference', 'Joh1,2'),
    );
    expect(
      asMap(api.actions[2]['fields']),
      containsPair('reference', 'Joh1,3'),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'partial merged block stays selected and names the created collection',
    (tester) async {
      tester.view.physicalSize = const Size(500, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final data = readerFixture();
      final chapter = asMap(asMaps(data['columns']).first['initialChapter']);
      final rows = asMap(chapter['chapter'])['rows'] as List;
      asMap((asMap(rows.first)['cells'] as List).first)['verseEnd'] = 2;
      rows.removeAt(1);
      final api = SelectionApi(data, failAt: 2);
      addTearDown(api.dispose);
      await tester.pumpWidget(app(api, const ReaderScreen(path: '/Joh1')));
      await tester.pumpAndSettle();
      await selectVerse(tester, 1, longPress: true);
      await selectVerse(tester, 3);
      await tester.tap(find.byTooltip('Auswahl zu Sammlungen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Neue Sammlung mit diesen Versen'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Meine Sammlung');
      await tester.tap(find.text('Übernehmen'));
      await tester.pumpAndSettle();
      expect(api.actions.map((a) => asMap(a['fields'])['reference']), [
        'Joh1,1',
        'Joh1,2',
      ]);
      expect(find.textContaining('1 von 3 Versen bestätigt'), findsOneWidget);
      expect(find.textContaining('Sammlungsübersicht'), findsOneWidget);
      expect(
        tester
            .widget<VerseText>(
              find.byWidgetPredicate(
                (w) => w is VerseText && w.verseNumber == '1–2',
              ),
            )
            .selected,
        isTrue,
      );
      expect(
        tester
            .widget<VerseText>(
              find.byWidgetPredicate(
                (w) => w is VerseText && w.verseNumber == '3',
              ),
            )
            .selected,
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final allPresent in [false, true]) {
    testWidgets(
      'collection selection ${allPresent ? 'removes all present' : 'adds only missing verses'}',
      (tester) async {
        tester.view.physicalSize = const Size(500, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final data = readerFixture();
        data['lists'] = [
          {'id': 'list0', 'title': 'Meine Sammlung'},
        ];
        final chapter = asMap(asMaps(data['columns']).first['initialChapter']);
        chapter['markedVerses'] = [
          {'listId': 'list0', 'verse': 1},
          if (allPresent) {'listId': 'list0', 'verse': 3},
        ];
        final api = SelectionApi(data);
        addTearDown(api.dispose);
        await tester.pumpWidget(app(api, const ReaderScreen(path: '/Joh1')));
        await tester.pumpAndSettle();
        await selectVerse(tester, 1, longPress: true);
        await selectVerse(tester, 3);
        await tester.tap(find.byTooltip('Auswahl zu Sammlungen'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Meine Sammlung'));
        await tester.pumpAndSettle();
        expect(
          api.actions.map((a) => a['action']),
          allPresent ? ['removeFromList', 'removeFromList'] : ['addToList'],
        );
        expect(
          api.actions.map((a) => asMap(a['fields'])['reference']),
          allPresent ? ['Joh1,1', 'Joh1,3'] : ['Joh1,3'],
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
