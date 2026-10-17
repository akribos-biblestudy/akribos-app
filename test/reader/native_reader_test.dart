import 'dart:convert';

import 'package:akribos_app/core/api_client.dart';
import 'package:akribos_app/core/app_scope.dart';
import 'package:akribos_app/features/reader/reader_screen.dart';
import 'package:akribos_app/features/reader/reader_notes.dart';
import 'package:akribos_app/features/reader/reader_state.dart';
import 'package:akribos_app/features/reader/verse_text.dart';
import 'package:akribos_app/features/reader/reader_local_store.dart';
import 'package:akribos_app/features/reader/books.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:akribos_app/features/search/search_screen.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Json readerFixture({int tiles = 1}) {
  final resources = List.generate(
    tiles,
    (index) => <String, dynamic>{
      'id': 'BIBLE$index',
      'kind': 'bible',
      'name': 'Bibelübersetzung $index',
      'tabTitle': 'Bibel $index',
      'language': 'de',
      'direction': 'ltr',
    },
  );
  final workspace = <String, dynamic>{
    'layout': tiles == 1 ? 'single' : 'columns-$tiles',
    'focusedTileId': 'tile0',
    'layoutSizes': {},
    'tiles': List.generate(
      tiles,
      (index) => <String, dynamic>{
        'id': 'tile$index',
        'activeTabId': 'tab$index',
        'tabs': [
          {
            'id': 'tab$index',
            'resourceId': 'BIBLE$index',
            'linkSet': 'A',
            'reference': {'book': 43, 'chapter': 1},
          },
        ],
      },
    ),
  };
  return {
    'user': {'id': 'reader'},
    'readerResources': resources,
    'bibles': resources,
    'activeSavedWorkspaceId': 'saved',
    'activeSavedWorkspaceVersion': 4,
    'activeSavedWorkspaceContentVersion': 12,
    'reference': {'book': 43, 'chapter': 1},
    'workspace': workspace,
    'readerState': encodeReaderState(workspace, {}, ''),
    'readerFontScale': 100,
    'columns': List.generate(
      tiles,
      (index) => {
        'tileId': 'tile$index',
        'resource': resources[index],
        'initialChapter': {
          'reference': {'book': 43, 'chapter': 1},
          'fullTitle': 'Johannes 1',
          'chapter': {
            'rows': List.generate(
              30,
              (verse) => {
                'verse': verse + 1,
                'cells': [
                  {
                    'verse': verse + 1,
                    'segments': [
                      'Ein längerer Beispielvers mit ',
                      {'kind': 'w', 'text': 'Liebe', 'strong': 'G26'},
                      ' und Hoffnung für den neuen Tag.',
                    ],
                  },
                ],
              },
            ),
          },
          'highlights': [
            {
              'verse': 1,
              'endVerse': 1,
              'styleId': 'yellow',
              'name': 'Verheißung',
              'color': '#facc15',
            },
          ],
          'referenceResources': {},
          'navigation': {},
        },
      },
    ),
    'highlightStyles': [
      {'id': 'yellow', 'name': 'Verheißung', 'color': '#facc15'},
    ],
  };
}

class ReaderApi extends AppApi {
  ReaderApi(this.data, {bool seedLocal = true})
    : super(server: 'https://example.test', cookies: CookieJar()) {
    bootstrap = asMap(jsonDecode(jsonEncode(data)));
    if (seedLocal) {
      FlutterSecureStorage.setMockInitialValues({
        localStore.storageKey: jsonEncode({
          'version': 1,
          'versePerLine': data['versePerLine'] ?? true,
          'path': readerPath(
            asMap(data['workspace']),
            asString(data['readerState']),
          ),
          'layoutSizes': asMap(asMap(data['workspace'])['layoutSizes']),
        }),
      });
    }
  }
  final Json data;
  final actions = <Json>[], requests = <Json>[];
  final pages = <String>[], reads = <String>[];
  ReaderLocalStore get localStore => ReaderLocalStore(
    origin: origin,
    userId: asString(asMap(bootstrap['user'])['id']),
  );

  // Model only the supplied public URL. Returning the old server fixture here
  // would silently undo local tab/position restoration and hide real regressions.
  Json pageData(String path) {
    final result = asMap(jsonDecode(jsonEncode(data)));
    final uri = Uri.parse(path),
        parameters = Uri.parse(path).queryParametersAll;
    final workspace = asMap(result['workspace']);
    final tiles = asMaps(workspace['tiles']);
    final originals = [for (final tile in tiles) ...asMaps(tile['tabs'])];
    final values = parameters['tab'];
    if (values != null) {
      for (final tile in tiles) {
        tile['tabs'] = <Json>[];
        tile['activeTabId'] = null;
      }
      for (final value in values) {
        final parts = value.split(':');
        final coordinate = parts[0].split('.').map(int.parse).toList();
        while (tiles.length < coordinate[0]) {
          tiles.add({
            'id': 'tile${tiles.length}',
            'tabs': <Json>[],
            'activeTabId': null,
          });
        }
        final original = originals.firstWhere(
          (tab) => tab['resourceId'] == parts[1],
          orElse: () => {'id': 'tab${coordinate.join('_')}'},
        );
        final tab = <String, dynamic>{
          ...original,
          'resourceId': parts[1],
          'linkSet': parts[2] == '-' ? null : parts[2],
          'reference': parseFixtureReference(parts[3]),
        };
        (tiles[coordinate[0] - 1]['tabs'] as List).add(tab);
      }
      workspace['tiles'] = tiles;
      workspace['layout'] = parameters['layout']!.single;
      workspace['focusedTileId'] =
          tiles[int.parse(parameters['focus']?.single ?? '1') - 1]['id'];
      for (final tile in tiles) {
        tile['activeTabId'] = asMaps(tile['tabs']).firstOrNull?['id'];
      }
      for (final value in parameters['active'] ?? <String>[]) {
        final coordinate = value.split('.').map(int.parse).toList();
        final tile = tiles[coordinate[0] - 1];
        tile['activeTabId'] = asMaps(tile['tabs'])[coordinate[1] - 1]['id'];
      }
      final searches = <String, dynamic>{};
      for (final value in parameters['search'] ?? <String>[]) {
        final separator = value.indexOf(':');
        final coordinate = value
            .substring(0, separator)
            .split('.')
            .map(int.parse)
            .toList();
        final tab = asMaps(tiles[coordinate[0] - 1]['tabs'])[coordinate[1] - 1];
        searches[asString(tab['id'])] = value.substring(separator + 1);
      }
      result['searchQueries'] = searches;
    }
    final focused = tiles.firstWhere(
      (tile) => tile['id'] == workspace['focusedTileId'],
    );
    if (uri.path != '/' && asMaps(focused['tabs']).isNotEmpty) {
      updateReadingPosition(
        workspace,
        asString(focused['id']),
        asString(activeTab(focused)['id']),
        parseFixtureReference(uri.path.substring(1)),
      );
    }
    final initialColumns = asMaps(result['columns']);
    result['columns'] = [
      for (final tile in tiles)
        if (asMaps(tile['tabs']).isNotEmpty)
          (() {
            final tab = activeTab(tile);
            final source = initialColumns
                .where(
                  (column) =>
                      asMap(column['resource'])['id'] == tab['resourceId'],
                )
                .firstOrNull;
            final column = asMap(
              jsonDecode(jsonEncode(source ?? initialColumns.first)),
            );
            column['tileId'] = tile['id'];
            column['resource'] = asMaps(result['readerResources'])
                .firstWhere((resource) => resource['id'] == tab['resourceId']);
            asMap(column['initialChapter'])['reference'] = {
              ...asMap(tab['reference']),
            };
            return column;
          })(),
    ];
    result['readerState'] = encodeReaderState(
      workspace,
      asMap(result['searchQueries']),
      uri.query,
    );
    result['_path'] = readerPath(workspace, asString(result['readerState']));
    result['readerWorkspaceDetached'] = true;
    return result;
  }

  @override
  Future<Json> page(String path) async {
    pages.add(path);
    return pageData(path);
  }

  @override
  Future<dynamic> get(String path) async {
    reads.add(path);
    return {};
  }

  @override
  Future<dynamic> send(String method, String path, {dynamic data}) async {
    requests.add({'method': method, 'path': path, 'data': data});
    throw StateError('Unexpected remote Reader write: $method $path');
  }

  @override
  Future<ApiResult> action(String path, String action, Json fields) async {
    actions.add({'path': path, 'action': action, 'fields': fields});
    final result = pageData(path);
    final workspace = asMap(result['workspace']);
    final tile = asMaps(workspace['tiles']).firstWhere(
      (tile) => tile['id'] == (fields['tileId'] ?? workspace['focusedTileId']),
    );
    final tab = asMaps(tile['tabs']).firstWhere(
      (tab) => tab['id'] == (fields['tabId'] ?? tile['activeTabId']),
    );
    if (action == 'setTabLinkSet') {
      tab['linkSet'] = fields['linkSet'];
    } else if (action == 'setTabReference' || action == 'openBibleReference') {
      updateReadingPosition(
        workspace,
        asString(tile['id']),
        asString(tab['id']),
        parseFixtureReference(asString(fields['reference'])),
      );
    } else {
      throw StateError('Unexpected Reader action: $action');
    }
    final state = encodeReaderState(
      workspace,
      asMap(result['searchQueries']),
      Uri.parse(path).query,
    );
    return ApiResult(
      type: 'success',
      status: 200,
      data: {
        'readerState': state,
        'path': Uri.parse(readerPath(workspace, state)).path,
      },
    );
  }
}

Json parseFixtureReference(String value) {
  for (final book in [
    ...bibleBooks,
  ]..sort((a, b) => b.abbreviation.length.compareTo(a.abbreviation.length))) {
    if (!value.startsWith(book.abbreviation)) continue;
    final parts = value.substring(book.abbreviation.length).split(',');
    final chapter = int.tryParse(parts.first);
    if (chapter == null) continue;
    return {
      'book': book.id,
      'chapter': chapter,
      if (parts.length > 1) 'verse': int.parse(parts[1]),
    };
  }
  throw FormatException('Unsupported test reference: $value');
}

Widget app(
  ReaderApi api,
  Widget child, {
  double textScale = 1,
  bool eInk = false,
  Future<void> Function(String)? open,
}) => MaterialApp(
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(
      textScaler: TextScaler.linear(textScale),
      disableAnimations: eInk,
      highContrast: eInk,
    ),
    child: child!,
  ),
  home: AppScope(
    api: api,
    open: open ?? (_) async {},
    refreshSession: () async {},
    setNavigationGuard: (_, _) {},
    setTheme: (_) {},
    themeMode: ThemeMode.light,
    eInk: eInk,
    child: Scaffold(body: child),
  ),
);

void main() {
  testWidgets('notes search actions wrap on a narrow phone with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = ReaderApi(readerFixture());
    await tester.pumpWidget(
      app(
        api,
        ReaderNotes(
          reference: 'Joh1,1',
          resourceId: 'BIBLE0',
          initialState: Uri(
            queryParameters: {
              'notesQuery': 'Hoffnung',
              'notesTag': 'Ein langes persönliches Schlagwort',
            },
          ).query,
          onFilters: (_, _, _) {},
          onOpen: (_) {},
          onCreate: () {},
        ),
        textScale: 1.7,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Neue Notiz'), findsOneWidget);
    expect(find.text('Suche zurücksetzen'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Suche zurücksetzen')).dy,
      greaterThan(tester.getTopLeft(find.text('Neue Notiz')).dy),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'mobile tab selection stores local focus without a server activation',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = ReaderApi(readerFixture(tiles: 2));
      await tester.pumpWidget(app(api, const ReaderScreen(path: '/Joh1')));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(PageView), const Offset(-350, 0));
      await tester.pumpAndSettle();
      final saved = await api.localStore.read();
      expect(Uri.parse(asString(saved?['path'])).queryParameters['focus'], '2');
      expect(api.actions, isEmpty);
      expect(api.requests, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'tablet presents one tab without rewriting the browser layout or divider sizes',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fixture = readerFixture(tiles: 3);
      asMap(fixture['workspace'])['layoutSizes'] = {
        'columns-3': {
          'columns': [.2, .5, .3],
          'rows': [1.0],
        },
      };
      final original = jsonDecode(jsonEncode(fixture['workspace']));
      final api = ReaderApi(fixture);
      await tester.pumpWidget(app(api, const ReaderScreen(path: '/Joh1')));
      await tester.pumpAndSettle();
      expect(find.byType(PageView), findsOneWidget);
      expect(find.byType(CustomScrollView), findsOneWidget);
      expect(find.text('Johannes 1'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is MouseRegion &&
              [
                SystemMouseCursors.resizeColumn,
                SystemMouseCursors.resizeRow,
              ].contains(widget.cursor),
        ),
        findsNothing,
      );
      expect(find.byTooltip('In diesem Werk suchen'), findsNothing);
      await tester.tap(find.text('Tabs (3)'));
      await tester.pumpAndSettle();
      expect(find.text('Geöffnete Werke'), findsOneWidget);
      expect(find.byTooltip('Anordnung'), findsNothing);
      expect(find.text('Geteilter Bildschirm'), findsNothing);
      await tester.tap(find.byTooltip('Fertig'));
      await tester.pumpAndSettle();
      expect(api.data['workspace'], original);
      expect(api.actions, isEmpty);
      expect(
        api.requests.where((request) => request['method'] == 'PUT'),
        isEmpty,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'e-ink paging persists its visible position locally without workspace writes',
    (tester) async {
      tester.view.physicalSize = const Size(600, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = ReaderApi(readerFixture());
      await tester.pumpWidget(
        app(api, const ReaderScreen(path: '/Joh1'), eInk: true),
      );
      await tester.pumpAndSettle();
      expect(find.text('Markiert: Verheißung'), findsOneWidget);
      expect(find.byTooltip('Nächste Bildschirmseite'), findsOneWidget);
      await tester.tap(find.byTooltip('Nächste Bildschirmseite'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 900));
      await tester.pumpAndSettle();
      final saved = await api.localStore.read();
      final snapshot = Uri.parse(asString(saved?['path'])).queryParameters;
      expect(snapshot['tab'], matches(RegExp(r'Joh1,([2-9]|[12][0-9]|30)$')));
      expect(api.requests, isEmpty);
      expect(api.actions, isEmpty);
      expect(snapshot.keys, isNot(contains('workspaceVersion')));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'phone has one reading pane and a flat resource overview at large text size',
    (tester) async {
      tester.view.physicalSize = const Size(320, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = ReaderApi(readerFixture(tiles: 4));
      await tester.pumpWidget(
        app(api, const ReaderScreen(path: '/Joh1'), textScale: 1.5),
      );
      await tester.pumpAndSettle();
      expect(find.text('Bibel 0 · Joh1'), findsOneWidget);
      expect(find.text('Johannes 1'), findsOneWidget);
      await tester.tap(find.text('Tabs (4)'));
      await tester.pumpAndSettle();
      expect(find.text('Geöffnete Werke'), findsOneWidget);
      expect(find.text('Bibel 0'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Bibel 3'),
        250,
        scrollable: find.descendant(
          of: find.byType(GridView),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Bibel 3'), findsOneWidget);
      await tester.tap(find.byTooltip('Fertig'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Tab-Einstellungen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tabgruppe B'));
      await tester.pumpAndSettle();
      final action = api.actions.single;
      expect(action['action'], 'setTabLinkSet');
      final query = Uri.parse(asString(action['path'])).queryParameters;
      expect(query['workspaceDetached'], 'true');
      expect(query.keys, isNot(contains('workspaceId')));
      expect(query.keys, isNot(contains('workspaceVersion')));
      expect(query.keys, isNot(contains('workspaceContentVersion')));
      expect(asMap(action['fields'])['linkSet'], 'B');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'tablet keeps one pane and opens the exact source-word position in the lexicon',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = ReaderApi(readerFixture(tiles: 3));
      await tester.pumpWidget(app(api, const ReaderScreen(path: '/Joh1')));
      await tester.pumpAndSettle();
      expect(find.text('Johannes 1'), findsOneWidget);
      expect(find.byType(CustomScrollView), findsOneWidget);
      final verse = tester.widget<VerseText>(find.byType(VerseText).first);
      verse.onWord!({'kind': 'w', 'text': 'Liebe', 'strong': 'G26'}, 0);
      await tester.pumpAndSettle();
      expect(api.actions, isEmpty);
      expect(find.text('Lexikon · G26'), findsOneWidget);
      final study = tester.widget<LexiconStudy>(find.byType(LexiconStudy));
      expect(asMap(study.tab['studyContext'])['wordPosition'], 0);
      expect(asMap(study.tab['studyContext'])['reference'], {
        'book': 43,
        'chapter': 1,
        'verse': 1,
      });
      await tester.tap(find.byTooltip('Lexikon schließen'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
