import 'dart:async';

import 'package:akribos_app/core/api_client.dart';
import 'package:akribos_app/core/app_scope.dart';
import 'package:akribos_app/features/reader/reader_controller.dart';
import 'package:akribos_app/features/reader/verse_text.dart';
import 'package:akribos_app/features/search/search_screen.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_api.dart';

void main() {
  const first = ReaderSearchResource(
    id: 'FIRST',
    title: 'Erste Übersetzung (E1)',
    kind: 'bible',
  );
  const second = ReaderSearchResource(
    id: 'SECOND',
    title: 'Zweite Übersetzung (E2)',
    kind: 'bible',
    direction: 'rtl',
  );
  const lexicon = ReaderSearchResource(
    id: 'LEX',
    title: 'Gewähltes Lexikon',
    kind: 'lexicon',
  );
  late AppApi api;
  late FakeHttpAdapter adapter;
  final opened = <String>[];

  void setup(Future<ResponseBody> Function(CapturedRequest) response) {
    opened.clear();
    adapter = FakeHttpAdapter(response);
    api = AppApi(
      server: 'https://akribos.test',
      dio: Dio()..httpClientAdapter = adapter,
      cookies: CookieJar(),
    );
    addTearDown(api.dispose);
  }

  Widget host(
    ReaderSearchResource? resource, {
    String path = '/search?q=Liebe',
  }) => MaterialApp(
    home: AppScope(
      api: api,
      open: (path) async {
        opened.add(path);
      },
      refreshSession: () async {},
      setNavigationGuard: (_, _) {},
      setTheme: (_) {},
      themeMode: ThemeMode.system,
      child: Scaffold(
        body: SearchScreen(path: path, resource: resource),
      ),
    ),
  );
  Map<String, dynamic> result(String text, {String kind = 'scripture'}) => {
    'kind': kind,
    'query': 'Liebe',
    'total': 1,
    'page': 1,
    'pageCount': 1,
    'bookCounts': [
      {'book': 43, 'count': 1},
    ],
    'hits': [
      {
        'book': 43,
        'chapter': 3,
        'verse': 16,
        'segments': [text],
      },
    ],
  };

  testWidgets(
    'missing active resource never falls back to a saved workspace search',
    (tester) async {
      setup((_) async => jsonResponse(result('unexpected')));
      await tester.pumpWidget(host(null));
      await tester.pumpAndSettle();
      expect(find.text('Kein Werk geöffnet'), findsOneWidget);
      expect(find.textContaining('Öffne zunächst ein Werk'), findsOneWidget);
      expect(adapter.requests, isEmpty);
    },
  );

  testWidgets(
    'search has one explicit resource, labels every hit and respects RTL',
    (tester) async {
      setup((_) async => jsonResponse(result('בְּרֵאשִׁית')));
      await tester.pumpWidget(host(second));
      await tester.pumpAndSettle();
      final uri = adapter.requests.single.options.uri;
      expect(uri.path, '/api/reader/search');
      expect(uri.queryParameters, {'q': 'Liebe', 'resource': 'SECOND'});
      expect(find.text(second.title), findsNWidgets(2));
      expect(
        tester.widget<VerseText>(find.byType(VerseText)).direction,
        TextDirection.rtl,
      );
      await tester.tap(find.text('Joh3,16'));
      expect(opened, ['/Joh3,16']);
      await tester.pumpWidget(host(second));
      await tester.pumpAndSettle();
      expect(
        adapter.requests,
        hasLength(1),
        reason: 'The same retained resource must not reload.',
      );
    },
  );

  testWidgets(
    'a resource change reruns the retained query and discards a late old response',
    (tester) async {
      final oldResponse = Completer<ResponseBody>();
      setup(
        (request) async =>
            request.options.uri.queryParameters['resource'] == 'FIRST'
            ? oldResponse.future
            : jsonResponse(result('Aktueller Treffer')),
      );
      await tester.pumpWidget(host(first));
      for (
        var attempt = 0;
        attempt < 20 && adapter.requests.isEmpty;
        attempt++
      ) {
        await tester.pump(const Duration(milliseconds: 10));
      }
      expect(adapter.requests, hasLength(1));
      await tester.pumpWidget(host(second));
      await tester.pumpAndSettle();
      expect(
        adapter.requests.map((r) => r.options.uri.queryParameters['resource']),
        ['FIRST', 'SECOND'],
      );
      expect(adapter.requests.map((r) => r.options.uri.queryParameters['q']), [
        'Liebe',
        'Liebe',
      ]);
      expect(find.text(first.title), findsNothing);
      expect(
        find.textContaining('Aktueller Treffer', findRichText: true),
        findsOneWidget,
      );
      oldResponse.complete(jsonResponse(result('Veralteter Treffer')));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Veralteter Treffer', findRichText: true),
        findsNothing,
      );
      expect(
        find.textContaining('Aktueller Treffer', findRichText: true),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'Strong search stays within the selected translation and labels occurrences',
    (tester) async {
      setup(
        (_) async => jsonResponse({
          ...result('Liebe', kind: 'strong'),
          'strong': 'G26',
          'statistics': {'occurrences': 1, 'verseCount': 1},
          'glosses': [],
        }),
      );
      await tester.pumpWidget(
        host(first, path: '/search?q=G26&resource=FIRST'),
      );
      await tester.pumpAndSettle();
      expect(adapter.requests.single.options.uri.queryParameters, {
        'resource': 'FIRST',
        'q': 'G26',
      });
      expect(find.text(first.title), findsNWidgets(2));
      expect(
        find.text('In diesem Lexikon ist kein Eintrag vorhanden.'),
        findsNothing,
      );
      expect(
        tester.widget<VerseText>(find.byType(VerseText)).studiedStrong,
        'G26',
      );
    },
  );

  testWidgets(
    'dictionary words and related Strong entries use only the exact lexicon',
    (tester) async {
      setup(
        (_) async => jsonResponse({
          'resourceId': 'LEX',
          'query': 'agape',
          'entry': {
            'strong': 'G26',
            'lemma': 'ἀγάπη',
            'definitionHtml': '<p>Lexikondefinition</p>',
            'seeAlso': ['G25'],
          },
        }),
      );
      await tester.pumpWidget(
        host(lexicon, path: '/search?q=agape&resource=LEX'),
      );
      await tester.pumpAndSettle();
      expect(adapter.requests.single.options.uri.path, '/api/reader/lookup');
      expect(adapter.requests.single.options.uri.queryParameters, {
        'resource': 'LEX',
        'q': 'agape',
      });
      expect(find.text('Eintrag suchen in'), findsOneWidget);
      expect(find.text(lexicon.title), findsOneWidget);
      expect(find.textContaining('Vorkommen in'), findsNothing);
      await tester.tap(find.text('G25'));
      final target = Uri.parse(opened.single);
      expect(target.path, '/search');
      expect(target.queryParameters['resource'], 'LEX');
      expect(target.queryParameters['q'], 'G25');
    },
  );

  testWidgets(
    'commentary pagination and suggestions preserve the exact resource',
    (tester) async {
      const commentary = ReaderSearchResource(
        id: 'COMM',
        title: 'Mein Kommentar',
        kind: 'commentary',
      );
      setup(
        (_) async => jsonResponse({
          'kind': 'commentary',
          'total': 26,
          'page': 1,
          'pageCount': 2,
          'suggestion': 'lieben',
          'bookCounts': [
            {'book': 43, 'count': 26},
          ],
          'hits': [
            {
              'book': 43,
              'chapter': 3,
              'verseStart': 16,
              'bodyHtml': '<p>Kommentar zur Liebe.</p>',
            },
          ],
        }),
      );
      await tester.pumpWidget(
        host(commentary, path: '/search?q=Liebe&resource=COMM'),
      );
      await tester.pumpAndSettle();
      expect(
        adapter.requests.single.options.uri.queryParameters['resource'],
        'COMM',
      );
      expect(find.text(commentary.title), findsNWidgets(2));
      await tester.tap(find.byTooltip('Nächste Seite'));
      expect(Uri.parse(opened.last).queryParameters, {
        'q': 'Liebe',
        'resource': 'COMM',
        'page': '2',
      });
      await tester.tap(find.text('Meintest du „lieben“?'));
      expect(Uri.parse(opened.last).queryParameters, {
        'q': 'lieben',
        'resource': 'COMM',
        'page': '1',
      });
    },
  );

  testWidgets(
    'revoked resource reports failure without an alternative translation',
    (tester) async {
      setup(
        (_) async =>
            jsonResponse({'message': 'Unbekannte Ressource'}, status: 404),
      );
      await tester.pumpWidget(host(first));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Die Suche konnte nicht geladen werden'),
        findsOneWidget,
      );
      expect(find.byType(SearchHit), findsNothing);
      expect(adapter.requests, hasLength(1));
      expect(
        adapter.requests.single.options.uri.queryParameters['resource'],
        'FIRST',
      );
    },
  );

  test('detaching the reader drops its formerly private search selection', () {
    final controller = ReaderController();
    final owner = Object();
    controller.attach(owner, showTabs: () async {}, flush: () async => true);
    controller.update(
      tabCount: 1,
      activeTitle: first.title,
      activeResource: first,
    );
    expect(controller.activeResource, first);
    controller.detach(owner);
    expect(controller.activeResource, isNull);
    expect(controller.tabCount, 0);
    controller.dispose();
  });
}
