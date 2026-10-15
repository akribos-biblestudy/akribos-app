import 'dart:async';

import 'package:akribos_app/core/api_client.dart';
import 'package:akribos_app/core/app_scope.dart';
import 'package:akribos_app/features/reader/reader_controller.dart';
import 'package:akribos_app/features/reader/reader_lexicon_sheet.dart';
import 'package:akribos_app/features/reader/reader_screen.dart';
import 'package:akribos_app/features/reader/reader_state.dart';
import 'package:akribos_app/features/reader/verse_text.dart';
import 'package:akribos_app/features/search/search_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'native_reader_test.dart' show ReaderApi, app, readerFixture;

class LexiconApi extends ReaderApi {
  LexiconApi(super.data);
  final gets = <String>[];
  bool fail = false;
  Completer<void>? relatedArticle;
  @override
  Future<dynamic> get(String path) async {
    gets.add(path);
    if (!path.startsWith('/api/strong/')) return super.get(path);
    if (fail) throw const ApiException('Lexikon derzeit nicht erreichbar');
    final strong = Uri.parse(path).pathSegments.last;
    if (strong == 'G25') await relatedArticle?.future;
    return {
      'strong': strong,
      'entry': {
        'strong': strong,
        'lemma': 'ἀγάπη',
        'definitionHtml': '<p>Liebe und Zuwendung.</p>',
        'seeAlso': ['G25'],
      },
      'occurrences': {
        'occurrences': [
          {
            'book': 43,
            'chapter': 3,
            'verse': 16,
            'segments': ['Denn also hat Gott die Welt geliebt.'],
          },
        ],
        'total': 1,
        'page': 1,
        'pageCount': 1,
      },
    };
  }
}

Future<void> openWord(WidgetTester tester, {int position = 0}) async {
  final verse = tester.widget<VerseText>(find.byType(VerseText).first);
  verse.onWord!({'kind': 'w', 'text': 'Liebe', 'strong': 'G26'}, position);
  await tester.pumpAndSettle();
}

void phoneSize(WidgetTester tester, {double width = 390}) {
  tester.view.physicalSize = Size(width, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets(
    'word lookup is read-only and system back preserves Bible tab and pixel offset',
    (tester) async {
      phoneSize(tester);
      final api = LexiconApi(readerFixture());
      final controller = ReaderController();
      await tester.pumpWidget(
        app(api, ReaderScreen(path: '/Joh1', controller: controller)),
      );
      await tester.pumpAndSettle();
      final stream = tester.widget<CustomScrollView>(
        find.byType(CustomScrollView),
      );
      stream.controller!.jumpTo(320);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1000));
      await tester.pumpAndSettle();
      final offset = stream.controller!.offset;
      final previousWrites = api.requests.length;
      final readerState = await api.localStore.read();
      await openWord(tester, position: 13);
      final query = Uri.parse(api.gets.single).queryParameters;
      expect(query['resource'], 'BIBLE0');
      expect(query['word'], 'Liebe');
      expect(query['wordPosition'], '13');
      expect(query['ref'], startsWith('Joh1,'));
      expect(find.text('Lexikon · G26'), findsOneWidget);
      expect(
        tester.getSize(find.byType(DraggableScrollableSheet)).height,
        greaterThan(700),
      );
      expect(controller.tabCount, 1);
      expect(api.actions, isEmpty);
      expect(api.requests.length, previousWrites);
      expect(await api.localStore.read(), readerState);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(DraggableScrollableSheet), findsNothing);
      final restored = tester.widget<CustomScrollView>(
        find.byType(CustomScrollView),
      );
      expect(identical(restored.controller, stream.controller), isTrue);
      expect(restored.controller!.offset, offset);
      expect(controller.tabCount, 1);
      expect(api.pages, hasLength(1));
      final page = Uri.parse(api.pages.single);
      expect(page.path, '/Joh1');
      expect(page.queryParameters['tab'], '1.1:BIBLE0:A:Joh1');
      expect(page.queryParameters['workspaceDetached'], 'true');
      expect(page.queryParameters.keys, isNot(contains('workspaceId')));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('the sheet can be dismissed by dragging its content down', (
    tester,
  ) async {
    phoneSize(tester);
    final api = LexiconApi(readerFixture());
    await tester.pumpWidget(app(api, const ReaderScreen(path: '/Joh1')));
    await tester.pumpAndSettle();
    await openWord(tester);
    final content = find.descendant(
      of: find.byType(LexiconStudy),
      matching: find.byType(ListView),
    );
    await tester.fling(content, const Offset(0, 720), 1400);
    await tester.pumpAndSettle();
    expect(find.byType(DraggableScrollableSheet), findsNothing);
    expect(api.actions, isEmpty);
    expect(find.byType(CustomScrollView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'related Strong articles stay in the sheet and clear positional assignment context',
    (tester) async {
      phoneSize(tester);
      final api = LexiconApi(readerFixture());
      await tester.pumpWidget(app(api, const ReaderScreen(path: '/Joh1')));
      await tester.pumpAndSettle();
      await openWord(tester, position: 7);
      api.relatedArticle = Completer<void>();
      await tester.tap(find.widgetWithText(ActionChip, 'G25'));
      await tester.pump();
      expect(find.text('Lexikon · G25'), findsOneWidget);
      expect(find.byType(StrongDetails), findsNothing);
      api.relatedArticle!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Lexikon · G25'), findsOneWidget);
      final request = Uri.parse(api.gets.last);
      expect(request.path, '/api/strong/G25');
      expect(request.queryParameters['resource'], 'BIBLE0');
      expect(request.queryParameters.containsKey('wordPosition'), isFalse);
      expect(request.queryParameters.containsKey('word'), isFalse);
      expect(api.actions, isEmpty);
      expect(api.pages, hasLength(1));
      final page = Uri.parse(api.pages.single);
      expect(page.path, '/Joh1');
      expect(page.queryParameters['tab'], '1.1:BIBLE0:A:Joh1');
      expect(page.queryParameters['workspaceDetached'], 'true');
      expect(page.queryParameters.keys, isNot(contains('workspaceId')));
      await tester.tap(find.byTooltip('Lexikon schließen'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'an explicit occurrence closes the sheet before navigating the Bible',
    (tester) async {
      phoneSize(tester);
      final api = LexiconApi(readerFixture());
      await tester.pumpWidget(app(api, const ReaderScreen(path: '/Joh1')));
      await tester.pumpAndSettle();
      await openWord(tester);
      final study = tester.widget<LexiconStudy>(find.byType(LexiconStudy));
      study.onOpen({'book': 43, 'chapter': 3, 'verse': 16});
      await tester.pumpAndSettle();
      expect(find.byType(DraggableScrollableSheet), findsNothing);
      expect(api.actions.single['action'], 'openBibleReference');
      expect(asMap(api.actions.single['fields'])['reference'], 'Joh3,16');
      expect(asMap(api.actions.single['fields'])['linkSet'], 'A');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'retry and close remain reachable on narrow large-text e-ink screens',
    (tester) async {
      phoneSize(tester, width: 320);
      final api = LexiconApi(readerFixture())..fail = true;
      await tester.pumpWidget(
        app(api, const ReaderScreen(path: '/Joh1'), textScale: 2, eInk: true),
      );
      await tester.pumpAndSettle();
      await openWord(tester);
      expect(find.textContaining('Erneut versuchen:'), findsOneWidget);
      api.fail = false;
      await tester.tap(find.textContaining('Erneut versuchen:'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Erneut versuchen:'), findsNothing);
      expect(api.gets.length, 2);
      await tester.tap(find.byTooltip('Lexikon schließen'));
      await tester.pumpAndSettle();
      expect(find.byType(DraggableScrollableSheet), findsNothing);
      expect(api.actions, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'non-lexicon links remove the sheet before opening another area',
    (tester) async {
      phoneSize(tester);
      final api = LexiconApi(readerFixture());
      final opened = <String>[];
      bool? sheetAbsentWhenNavigating;
      await tester.pumpWidget(
        app(
          api,
          const ReaderScreen(path: '/Joh1'),
          open: (path) async {
            sheetAbsentWhenNavigating = find
                .byType(DraggableScrollableSheet)
                .evaluate()
                .isEmpty;
            opened.add(path);
          },
        ),
      );
      await tester.pumpAndSettle();
      await openWord(tester);
      await AppScope.of(tester.element(find.byType(LexiconStudy)))
          .open('/notes');
      await tester.pumpAndSettle();
      expect(opened, ['/notes']);
      expect(sheetAbsentWhenNavigating, isTrue);
      expect(api.actions, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('an explicitly opened lexicon remains a normal resource tab', (
    tester,
  ) async {
    phoneSize(tester);
    final fixture = readerFixture();
    asMap((fixture['readerResources'] as List).first).addAll({
      'kind': 'lexicon',
      'language': 'grc',
      'name': 'Griechisches Lexikon',
      'tabTitle': 'Lexikon',
    });
    final workspace = asMap(fixture['workspace']);
    asMaps(asMaps(workspace['tiles']).first['tabs']).first['lookup'] = 'G26';
    fixture['readerState'] = encodeReaderState(workspace, {}, '');
    final api = LexiconApi(fixture);
    await tester.pumpWidget(app(api, const ReaderScreen(path: '/Joh1')));
    await tester.pumpAndSettle();
    expect(find.byType(LexiconStudy), findsOneWidget);
    expect(find.byType(DraggableScrollableSheet), findsNothing);
    expect(find.text('Lexikon · Joh1'), findsOneWidget);
    expect(Uri.parse(api.gets.single).queryParameters['lexicon'], 'BIBLE0');
    expect(api.actions, isEmpty);
    expect(tester.takeException(), isNull);
  });

  test('dictionary choice respects source group, language and independent-tile ownership', () {
    final resources = <Json>[
      {'id': 'greek', 'kind': 'lexicon', 'language': 'grc'},
      {'id': 'hebrew', 'kind': 'lexicon', 'language': 'hbo'},
      {'id': 'other', 'kind': 'lexicon', 'language': 'grc'},
    ];
    final workspace = <String, dynamic>{
      'tiles': [
        {
          'id': 'one',
          'tabs': [
            {'resourceId': 'other', 'linkSet': null},
            {'resourceId': 'hebrew', 'linkSet': 'A'},
          ],
        },
        {
          'id': 'two',
          'tabs': [
            {'resourceId': 'greek', 'linkSet': 'A'},
          ],
        },
      ],
    };
    String pick(Json source, String strong) => preferredReaderLexicon(
      workspace: workspace,
      resources: resources,
      sourceTileId: 'two',
      sourceTab: source,
      strong: strong,
    );
    expect(pick({'linkSet': 'A'}, 'G26'), 'greek');
    expect(pick({'linkSet': 'A'}, 'H1'), 'hebrew');
    expect(pick({'linkSet': 'B'}, 'G26'), '');
    expect(pick({'linkSet': null}, 'G26'), '');
  });
}
