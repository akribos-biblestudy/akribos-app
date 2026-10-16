import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:akribos_app/core/api_client.dart';
import 'package:akribos_app/core/app_scope.dart';
import 'package:akribos_app/core/deep_link.dart';
import 'package:akribos_app/main.dart';
import 'package:akribos_app/features/reader/reader_screen.dart';
import 'package:akribos_app/features/reader/reader_state.dart';
import 'package:akribos_app/features/reader/reader_local_store.dart';
import 'package:akribos_app/features/documents/documents_screen.dart';
import 'package:akribos_app/widgets/floating_navigation.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:akribos_app/features/search/search_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _SeedApi extends AppApi {
  _SeedApi() : super(server: 'https://example.test', cookies: CookieJar());
  final List<String> pageCalls = [];
  final List<String> getCalls = [];
  Completer<Json>? initialReader;
  final Json _seed = asMap(
    jsonDecode(
      File(
        const String.fromEnvironment(
          'AKRIBOS_CAPTURE_BOOTSTRAP',
          defaultValue: 'test/fixtures/bootstrap.json',
        ),
      ).readAsStringSync(),
    ),
  );
  final Json reader = asMap(
    jsonDecode(
      File(
        const String.fromEnvironment(
          'AKRIBOS_CAPTURE_READER',
          defaultValue: 'test/fixtures/reader.json',
        ),
      ).readAsStringSync(),
    ),
  );
  @override
  Future<Json> loadBootstrap() async {
    bootstrap = _seed;
    return bootstrap;
  }

  @override
  Future<Json> page(String path) async {
    pageCalls.add(path);
    if (!path.startsWith('/search') && initialReader != null) {
      final pending = initialReader!;
      initialReader = null;
      return pending.future;
    }
    if (path.startsWith('/search')) return {'query': '', 'results': {}};
    if (path == '/login') return {'pending': null, 'redirectTo': '/account'};
    if (path.startsWith('/help')) return {'topics': [], 'results': []};
    if (Uri.parse(path).path == '/notes') {
      return {
        'documents': [
          {'id': 'note', 'kind': 'note', 'title': 'Persönliche Notiz'},
        ],
        'filters': {'kind': 'note'},
      };
    }
    if (Uri.parse(path).path == '/sermons') {
      return {
        'sermons': [
          {
            'id': 'sermon',
            'kind': 'sermon',
            'title': 'Meine Ausarbeitung',
            'sermonStatus': 'idea',
          },
        ],
        'board': {
          'columns': [
            {'id': 'idea', 'name': 'Ideen'},
          ],
        },
        'filters': {},
      };
    }
    // A finite viewport fixture: live chapter loading is tested against the real server separately.
    for (final column in asMaps(reader['columns'])) {
      asMap(column['initialChapter'])['navigation'] = {
        'previous': null,
        'next': null,
      };
    }
    reader['user'] = _seed['user'];
    return reader;
  }

  @override
  Future<dynamic> get(String path) async {
    getCalls.add(path);
    return {'hits': [], 'total': 0, 'page': 1, 'pageCount': 1};
  }

  @override
  Future<ApiResult> action(String path, String action, Json fields) async =>
      ApiResult(type: 'success', status: 200, data: reader);
  @override
  Future<dynamic> send(String method, String path, {dynamic data}) async => {
    'saved': true,
  };
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  test('deep links are confined to the configured server', () {
    final server = Uri.parse('https://akribos.de');
    expect(
      appLinkPath(Uri.parse('akribos://open?path=%2FJoh3%2C16'), server),
      '/Joh3,16',
    );
    expect(
      appLinkPath(Uri.parse('https://akribos.de/invites/abc'), server),
      '/invites/abc',
    );
    expect(appLinkPath(Uri.parse('https://evil.test/login'), server), isNull);
    expect(
      appLinkPath(Uri.parse('akribos://open?path=%2F%2Fevil.test'), server),
      isNull,
    );
    expect(
      appLinkPath(Uri.parse('https://user:pass@akribos.de/login'), server),
      isNull,
    );
  });
  for (final width in [320.0, 840.0, 1280.0]) {
    testWidgets(
      'native shell fits $width px and opens account dialog navigation',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final api = _SeedApi();
        addTearDown(api.dispose);
        await tester.pumpWidget(AkribosApp(api: api, enableLinks: false));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.bySemanticsLabel('Akribos – Lesen'), findsOneWidget);
        expect(find.byType(FloatingNavigationBar), findsOneWidget);
        await tester.tap(find.byTooltip('Anmelden'));
        await tester.pumpAndSettle();
        expect(find.text('Willkommen bei Akribos'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
  testWidgets(
    'section switches retain the reader and search without new page loads',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = _SeedApi();
      addTearDown(api.dispose);
      await tester.pumpWidget(AkribosApp(api: api, enableLinks: false));
      await tester.pumpAndSettle();
      final readerCalls = api.pageCalls.length;
      await tester.tap(find.text('Suchen'));
      await tester.pumpAndSettle();
      expect(find.byType(SearchScreen), findsOneWidget);
      expect(api.pageCalls.any((p) => p.startsWith('/search')), isFalse);
      await tester.tap(find.text('Lesen'));
      await tester.pumpAndSettle();
      expect(api.pageCalls.length, readerCalls);
      await tester.tap(find.text('Suchen'));
      await tester.pumpAndSettle();
      expect(api.pageCalls.length, readerCalls);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'navbar search reruns the retained query only in the newly visible Reader translation',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = _SeedApi();
      addTearDown(api.dispose);
      final secondResource = asMaps(api.reader['readerResources'])
          .firstWhere((resource) => resource['id'] == 'SEEDPLAIN');
      final workspace = asMap(api.reader['workspace']);
      final secondTile = asMaps(workspace['tiles'])[1];
      asMaps(secondTile['tabs']).single['resourceId'] = secondResource['id'];
      final columns = asMaps(api.reader['columns']);
      columns[1]['resource'] = secondResource;
      columns[1]['initialChapter'] = jsonDecode(
        jsonEncode(columns[0]['initialChapter']),
      );
      api.reader['readerState'] = encodeReaderState(workspace, {}, '');
      final local = ReaderLocalStore(origin: api.origin, userId: null);
      FlutterSecureStorage.setMockInitialValues({
        local.storageKey: jsonEncode({
          'version': 1,
          'path': readerPath(workspace, asString(api.reader['readerState'])),
          'layoutSizes': {},
        }),
      });
      await tester.pumpWidget(AkribosApp(api: api, enableLinks: false));
      await tester.pumpAndSettle();
      final nav = find.byType(FloatingNavigationBar);
      Future<void> select(String label) async {
        await tester.tap(find.descendant(of: nav, matching: find.text(label)));
        await tester.pumpAndSettle();
      }

      List<Uri> searches() => api.getCalls
          .map(Uri.parse)
          .where((uri) => uri.path == '/api/reader/search')
          .toList();

      await select('Suchen');
      expect(find.text('Testübersetzung'), findsOneWidget);
      expect(searches(), isEmpty);
      final query = find.descendant(
        of: find.byType(SearchBox),
        matching: find.byType(TextField),
      );
      await tester.enterText(query, 'Liebe');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(searches(), hasLength(1));
      expect(searches().single.queryParameters, {
        'q': 'Liebe',
        'resource': 'SEEDDE',
        'page': '1',
      });

      await select('Lesen');
      await tester.drag(find.byType(PageView), const Offset(-350, 0));
      await tester.pumpAndSettle();
      expect(find.text('Schlicht Tab · Joh3,16'), findsOneWidget);
      expect(
        searches(),
        hasLength(1),
        reason: 'Switching Reader tabs must not run a hidden search.',
      );
      await select('Suchen');
      expect(find.text('Testübersetzung schlicht (Schlicht)'), findsOneWidget);
      expect(tester.widget<TextField>(query).controller!.text, 'Liebe');
      expect(searches(), hasLength(2));
      expect(searches().last.queryParameters, {
        'q': 'Liebe',
        'resource': 'SEEDPLAIN',
      });
      expect(
        api.pageCalls.any((path) => Uri.parse(path).path == '/search'),
        isFalse,
      );
      expect(
        searches().every(
          (uri) => uri.queryParametersAll['resource']!.length == 1,
        ),
        isTrue,
      );

      await select('Lesen');
      await select('Suchen');
      expect(
        searches(),
        hasLength(2),
        reason: 'Revisiting the same selected resource retains its result.',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'notes destination returns from preparations while preserving navigation guards',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = _SeedApi();
      api._seed['user'] = {'id': 'reader'};
      addTearDown(api.dispose);
      await tester.pumpWidget(AkribosApp(api: api, enableLinks: false));
      await tester.pumpAndSettle();
      final nav = find.byType(FloatingNavigationBar);
      Future<void> select(String label) async {
        await tester.tap(find.descendant(of: nav, matching: find.text(label)));
        await tester.pumpAndSettle();
      }

      await select('Notizen');
      await tester.tap(find.text('Ausarbeitungen'));
      await tester.pumpAndSettle();
      expect(find.text('Meine Ausarbeitung'), findsOneWidget);
      await select('Notizen');
      expect(Uri.parse(api.pageCalls.last).queryParameters, {
        'kind': 'note',
        'passage': 'Joh3',
      });
      expect(find.text('Meine Notizen'), findsOneWidget);
      expect(find.text('Persönliche Notiz'), findsOneWidget);
      expect(find.text('Meine Ausarbeitung'), findsNothing);
      await tester.tap(
        find.descendant(
          of: find.byType(DocumentsScreen),
          matching: find.text('Ausarbeitungen'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Meine Ausarbeitung'), findsOneWidget);
      final scope = AppScope.of(tester.element(find.byType(DocumentsScreen)));
      final owner = Object();
      var allowLeave = false;
      var guardCalls = 0;
      scope.setNavigationGuard(owner, () async {
        guardCalls++;
        return allowLeave;
      });
      final before = api.pageCalls.length;
      await select('Notizen');
      expect(guardCalls, 1);
      expect(api.pageCalls.length, before);
      expect(find.text('Meine Ausarbeitung'), findsOneWidget);
      allowLeave = true;
      await select('Notizen');
      expect(guardCalls, 2);
      expect(find.text('Meine Notizen'), findsOneWidget);
      scope.setNavigationGuard(owner, null);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'chapter notes can be disabled and stay disabled across navigation and restart',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final api = _SeedApi();
      api._seed['user'] = {'id': 'reader'};
      addTearDown(api.dispose);
      await tester.pumpWidget(AkribosApp(api: api, enableLinks: false));
      await tester.pumpAndSettle();
      Future<void> select(String label) async {
        await tester.tap(
          find.descendant(
            of: find.byType(FloatingNavigationBar),
            matching: find.text(label),
          ),
        );
        await tester.pumpAndSettle();
      }

      await select('Notizen');
      expect(Uri.parse(api.pageCalls.last).queryParameters['passage'], 'Joh3');
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isTrue,
      );
      await tester.tap(find.text('Aktuelles Kapitel'));
      await tester.pumpAndSettle();
      expect(Uri.parse(api.pageCalls.last).queryParameters, {'kind': 'note'});
      await select('Lesen');
      await select('Notizen');
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isFalse,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(AkribosApp(api: api, enableLinks: false));
      await tester.pumpAndSettle();
      await select('Notizen');
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isFalse,
      );
      expect(Uri.parse(api.pageCalls.last).queryParameters, {'kind': 'note'});
      await tester.tap(find.text('Aktuelles Kapitel'));
      await tester.pumpAndSettle();
      expect(Uri.parse(api.pageCalls.last).queryParameters['passage'], 'Joh3');
      final scope = AppScope.of(tester.element(find.byType(DocumentsScreen)));
      final workspace = asMap(api.reader['workspace']);
      final tile = asMaps(workspace['tiles'])
          .firstWhere((t) => t['id'] == workspace['focusedTileId']);
      activeTab(tile)['reference'] = {'book': 1, 'chapter': 2, 'verse': 4};
      await scope.open('/1Mo2,4');
      await tester.pumpAndSettle();
      await select('Notizen');
      expect(Uri.parse(api.pageCalls.last).queryParameters['passage'], '1Mo2');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'removed mobile routes fall back to libraries and help stays app-specific',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final api = _SeedApi();
      api._seed['user'] = {'id': 'reader'};
      addTearDown(api.dispose);
      await tester.pumpWidget(AkribosApp(api: api, enableLinks: false));
      await tester.pumpAndSettle();
      final scope = AppScope.of(tester.element(find.byType(Scaffold).first));
      await scope.open('/notes/import?old=1');
      await tester.pumpAndSettle();
      expect(Uri.parse(api.pageCalls.last).queryParameters, {
        'kind': 'note',
        'passage': 'Joh3',
      });
      expect(find.text('Meine Notizen'), findsOneWidget);
      await scope.open('/sermons/templates');
      await tester.pumpAndSettle();
      expect(api.pageCalls.last, '/sermons');
      expect(find.text('Meine Ausarbeitung'), findsOneWidget);
      expect(find.byTooltip('Schritt bearbeiten'), findsNothing);
      expect(
        api.pageCalls.any(
          (p) =>
              p.startsWith('/notes/import') ||
              p.startsWith('/sermons/templates'),
        ),
        isFalse,
      );
      await scope.open('/menu');
      await tester.pumpAndSettle();
      for (final removed in [
        'Ausarbeitungen',
        'Notizen importieren',
        'Vorlagen',
        'Datenschutz',
        'Impressum',
        'Akribos-Link öffnen',
      ]) {
        expect(find.text(removed), findsNothing);
      }
      expect(find.text('Über Akribos'), findsOneWidget);
      await scope.open('/help/reading/old-web-guide');
      await tester.pumpAndSettle();
      expect(find.text('Die App-Hilfe entsteht noch'), findsOneWidget);
      expect(api.pageCalls.any((p) => p.startsWith('/help')), isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'floating navigation stays inset and opens the reader tab overview',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = _SeedApi();
      addTearDown(api.dispose);
      await tester.pumpWidget(AkribosApp(api: api, enableLinks: false));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tabs'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Testübersetzung'), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('hidden canonical reader redirect preserves the visible search', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final api = _SeedApi();
    addTearDown(api.dispose);
    final pending = Completer<Json>();
    api.initialReader = pending;
    await tester.pumpWidget(AkribosApp(api: api, enableLinks: false));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('Suchen'));
    await tester.pumpAndSettle();
    pending.completeError(const AppRedirect('/Joh1'));
    await tester.pumpAndSettle();
    expect(find.byType(SearchScreen), findsOneWidget);
    final loaded = api.pageCalls.length;
    expect(api.pageCalls.last, contains('/Joh1?layout='));
    expect(api.pageCalls.last, contains('workspaceDetached=true'));
    await tester.tap(find.text('Lesen'));
    await tester.pumpAndSettle();
    expect(api.pageCalls.length, loaded);
    expect(find.byType(ReaderScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'explicit reader opening reloads an identical URL and respects guards',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final api = _SeedApi();
      addTearDown(api.dispose);
      await tester.pumpWidget(AkribosApp(api: api, enableLinks: false));
      await tester.pumpAndSettle();
      var scope = AppScope.of(tester.element(find.byType(ReaderScreen)));
      final before = api.pageCalls.length;
      await scope.open('/');
      await tester.pumpAndSettle();
      expect(api.pageCalls.length, before + 1);
      scope = AppScope.of(tester.element(find.byType(ReaderScreen)));
      final owner = Object();
      scope.setNavigationGuard(owner, () async => false);
      await tester.tap(find.text('Suchen'));
      await tester.pumpAndSettle();
      expect(api.pageCalls, isNot(contains('/search')));
      scope.setNavigationGuard(owner, null);
      await tester.tap(find.text('Suchen'));
      await tester.pumpAndSettle();
      expect(find.byType(SearchScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'guest settings expose local text presentation without account loading',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(320, 844);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final api = _SeedApi();
      addTearDown(api.dispose);
      await tester.pumpWidget(AkribosApp(api: api, enableLinks: false));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mehr'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Einstellungen'));
      await tester.tap(find.text('Einstellungen'));
      await tester.pumpAndSettle();
      expect(find.text('Textdarstellung'), findsOneWidget);
      expect(
        find.text('Zusammenhängende Absätze im Blocksatz.'),
        findsOneWidget,
      );
      expect(find.widgetWithText(ListTile, 'Versweise'), findsOneWidget);
      expect(find.widgetWithText(ListTile, 'Fließtext'), findsOneWidget);
      expect(
        api.pageCalls.any(
          (path) => path.startsWith('/account') || path.startsWith('/settings'),
        ),
        isFalse,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'E-Ink preference survives restart and also reaches dialogs above navigator',
    (tester) async {
      SharedPreferences.setMockInitialValues({'eInk': true});
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = _SeedApi();
      addTearDown(api.dispose);
      await tester.pumpWidget(AkribosApp(api: api, enableLinks: false));
      await tester.pumpAndSettle();
      final context = tester.element(find.byType(Scaffold).first);
      expect(AppScope.of(context).eInk, isTrue);
      expect(MediaQuery.of(context).disableAnimations, isTrue);
      expect(Theme.of(context).colorScheme.primary, Colors.black);
      final result = showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          content: Text(
            AppScope.of(context).eInk ? 'E-Ink verfügbar' : 'Fehlt',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('E-Ink verfügbar'), findsOneWidget);
      Navigator.of(tester.element(find.byType(AlertDialog))).pop(true);
      await tester.pumpAndSettle();
      expect(await result, isTrue);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('capture reproducible seeded Flutter reading views', (
    tester,
  ) async {
    if (!const bool.fromEnvironment('AKRIBOS_SCREENSHOTS')) return;
    await tester.runAsync(() async {
      final reading = FontLoader('AkribosText')
        ..addFont(rootBundle.load('assets/fonts/akribos-text-regular.ttf'));
      final controls = FontLoader('Roboto')
        ..addFont(
          File('/usr/share/fonts/noto/NotoSans-Regular.ttf')
              .readAsBytes()
              .then((bytes) => ByteData.sublistView(bytes)),
        );
      final icons = FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      await reading.load();
      await controls.load();
      await icons.load();
    });
    for (final entry in [
      ('phone', 390.0, 844.0, false),
      ('phone-dark', 390.0, 844.0, false),
      ('tablet', 1280.0, 900.0, false),
      ('eink', 1200.0, 900.0, true),
    ]) {
      SharedPreferences.setMockInitialValues({
        'eInk': entry.$4,
        'theme': entry.$1 == 'phone-dark' ? 'dark' : 'light',
      });
      tester.view.physicalSize = Size(entry.$2, entry.$3);
      tester.view.devicePixelRatio = 1;
      final boundary = GlobalKey();
      final api = _SeedApi();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: AkribosApp(
            key: ValueKey(entry.$1),
            api: api,
            enableLinks: false,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => precacheImage(
          const AssetImage('assets/brand/wordmark.png'),
          tester.element(find.byType(Scaffold).first),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final render =
            boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await render.toImage(pixelRatio: 1);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory('docs/screenshots').create(recursive: true);
        await File('docs/screenshots/${entry.$1}.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
      if (entry.$1 == 'phone') {
        await tester.tap(find.text('Tabs'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.runAsync(() async {
          final render =
              boundary.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final capture = await render.toImage(pixelRatio: 1);
          final bytes = await capture.toByteData(
            format: ui.ImageByteFormat.png,
          );
          await File('docs/screenshots/phone-tabs.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          capture.dispose();
        });
      }
      await tester.pumpWidget(const SizedBox.shrink());
      api.dispose();
    }
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}
