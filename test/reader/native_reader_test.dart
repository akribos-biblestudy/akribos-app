import 'dart:convert';

import 'package:akribos_app/core/api_client.dart';
import 'package:akribos_app/core/app_scope.dart';
import 'package:akribos_app/features/reader/reader_screen.dart';
import 'package:akribos_app/features/reader/reader_notes.dart';
import 'package:akribos_app/features/reader/reader_state.dart';
import 'package:akribos_app/features/reader/verse_text.dart';
import 'package:akribos_app/features/reader/workspace_screen.dart';
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
  ReaderApi(this.data)
    : super(server: 'https://example.test', cookies: CookieJar());
  final Json data;
  final actions = <Json>[], requests = <Json>[];
  final pages = <String>[];
  @override
  Future<Json> page(String path) async {
    pages.add(path);
    return asMap(jsonDecode(jsonEncode(data)));
  }

  @override
  Future<dynamic> get(String path) async =>
      path == '/api/reader/workspaces' ? {'workspaces': []} : {};
  @override
  Future<dynamic> send(String method, String path, {dynamic data}) async {
    requests.add({'method': method, 'path': path, 'data': data});
    if (path == '/api/reader/workspaces') {
      return {
        'ok': true,
        'workspace': {
          'id': 'new-id',
          'name': data['name'],
          'revision': 1,
          'isActive': false,
        },
      };
    }
    if (method == 'PUT') {
      this.data['readerState'] = asMap(data['snapshot'])['readerState'];
    }
    return {
      'saved': true,
      'activeSavedWorkspaceId': 'saved',
      'activeSavedWorkspaceVersion': 4,
      'activeSavedWorkspaceContentVersion': method == 'PUT' ? 13 : 12,
      'readerState': this.data['readerState'],
      'path': '/Joh1',
    };
  }

  @override
  Future<ApiResult> action(String path, String action, Json fields) async {
    actions.add({'path': path, 'action': action, 'fields': fields});
    if (path.startsWith('/workspaces/')) {
      return const ApiResult(
        type: 'redirect',
        status: 303,
        location: '/Joh1?layout=single',
      );
    }
    if (action == 'setLayoutSize') {
      return ApiResult(
        type: 'success',
        status: 200,
        data: {'readerState': data['readerState']},
      );
    }
    return ApiResult(
      type: 'success',
      status: 200,
      data: {'readerState': data['readerState'], 'path': '/Joh1'},
    );
  }
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
    'mobile tab selection publishes focus even when its tile tab is already active',
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
      expect(api.actions.single['action'], 'activateTab');
      expect(asMap(api.actions.single['fields'])['tileId'], 'tile1');
      expect(asMap(api.actions.single['fields'])['tabId'], 'tab1');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'workspace deep link reads its name and activates only after explicit open',
    (tester) async {
      final api = ReaderApi({'name': 'Meine Wortstudie'});
      final opened = <String>[];
      await tester.pumpWidget(
        app(
          api,
          const WorkspaceScreen(path: '/workspaces/selected-id'),
          open: (path) async {
            opened.add(path);
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(api.pages, ['/workspaces/selected-id']);
      expect(api.requests, isEmpty);
      expect(api.actions, isEmpty);
      expect(opened, isEmpty);
      expect(find.text('Meine Wortstudie'), findsOneWidget);
      await tester.tap(find.text('Arbeitsbereich öffnen'));
      await tester.pumpAndSettle();
      expect(api.actions.single['path'], '/workspaces/selected-id');
      expect(api.actions.single['action'], 'default');
      expect(opened, ['/Joh1?layout=single']);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'tablet divider persists ratios and handles size action without a response path',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = ReaderApi(readerFixture(tiles: 3));
      await tester.pumpWidget(app(api, const ReaderScreen(path: '/Joh1')));
      await tester.pumpAndSettle();
      final divider = find
          .byWidgetPredicate(
            (widget) =>
                widget is MouseRegion &&
                widget.cursor == SystemMouseCursors.resizeColumn,
          )
          .first;
      await tester.drag(divider, const Offset(80, 0));
      await tester.pumpAndSettle();
      final action = api.actions.single;
      expect(action['action'], 'setLayoutSize');
      final fields = asMap(action['fields']);
      final columns = asString(fields['columns'])
          .split(',')
          .map(double.parse)
          .toList();
      expect(columns.length, 3);
      expect(columns.first, greaterThan(1 / 3));
      expect(columns.reduce((left, right) => left + right), closeTo(1, .00001));
      expect(fields['rows'], '1.0');
      expect(api.pages.last, startsWith('/Joh1?layout='));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'e-ink paging jumps one viewport and persists position with server selection versions',
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
      final writes = api.requests
          .where((request) => request['method'] == 'PUT')
          .toList();
      expect(writes, hasLength(1));
      final saved = asMap(writes.single['data']);
      expect(saved['workspaceVersion'], 4);
      expect(saved['workspaceContentVersion'], 12);
      expect(saved['resume'], isTrue);
      final snapshot = Uri.splitQueryString(
        asString(asMap(saved['snapshot'])['readerState']),
      );
      expect(snapshot['tab'], matches(RegExp(r'Joh1,([2-9]|[12][0-9]|30)$')));
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
      expect(query['workspaceId'], 'saved');
      expect(query['workspaceVersion'], '4');
      expect(query['workspaceContentVersion'], '12');
      expect(asMap(action['fields'])['linkSet'], 'B');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'tablet shows multiple panes and exact source-word position opens lexicon',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = ReaderApi(readerFixture(tiles: 3));
      await tester.pumpWidget(app(api, const ReaderScreen(path: '/Joh1')));
      await tester.pumpAndSettle();
      expect(find.text('Johannes 1'), findsNWidgets(3));
      final verse = tester.widget<VerseText>(find.byType(VerseText).first);
      verse.onWord!({'kind': 'w', 'text': 'Liebe', 'strong': 'G26'}, 0);
      await tester.pumpAndSettle();
      expect(api.actions.single['action'], 'openLexiconTab');
      expect(asMap(api.actions.single['fields'])['wordPosition'], 0);
      expect(asMap(api.actions.single['fields'])['sourceReference'], 'Joh1,1');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'creating a workspace uses nested server workspace result and explicitly activates it',
    (tester) async {
      final api = ReaderApi(readerFixture());
      final opened = <String>[];
      await tester.pumpWidget(
        app(
          api,
          WorkspaceScreen(
            snapshot: {
              'readerState': api.data['readerState'],
              'layoutSizes': {},
            },
          ),
          open: (path) async {
            opened.add(path);
          },
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Neue Ansicht aus aktuellem Reader'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Predigt');
      await tester.tap(find.text('Speichern'));
      await tester.pumpAndSettle();
      expect(api.requests.single['method'], 'POST');
      expect(asMap(api.requests.single['data'])['name'], 'Predigt');
      expect(api.actions.single['path'], '/workspaces/new-id');
      expect(api.actions.single['action'], 'default');
      expect(opened, ['/Joh1?layout=single']);
      expect(tester.takeException(), isNull);
    },
  );
}
