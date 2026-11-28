import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:akribos_app/core/api_client.dart';
import 'package:akribos_app/core/app_scope.dart';
import 'package:akribos_app/features/reader/offline_reader_screen.dart';
import 'package:akribos_app/features/reader/offline_resource_store.dart';
import 'package:akribos_app/features/reader/reader_local_store.dart';
import 'package:akribos_app/main.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'features/reader/offline_reader_screen_test.dart' show chapter, package;

class OfflineTestApi extends AppApi {
  OfflineTestApi()
    : super(server: 'https://example.test', cookies: CookieJar());
  bool connected = false;
  bool catalogOffline = false;
  bool lexiconCatalogOffline = false;
  String? owner = 'A';
  String? fingerprint = 'session-A';
  Completer<String?>? delayedFingerprint;
  Completer<void>? fingerprintStarted;
  List<String> allowed = ['bible'];

  @override
  Future<String?> offlineSessionFingerprint() async {
    final pending = delayedFingerprint;
    if (pending != null) {
      delayedFingerprint = null;
      fingerprintStarted?.complete();
      return pending.future;
    }
    return fingerprint;
  }

  @override
  Future<Json> loadBootstrap() async {
    if (!connected) {
      throw const ApiException('Keine Verbindung', connectionFailure: true);
    }
    bootstrap = {
      ...asMap(
        jsonDecode(File('test/fixtures/bootstrap.json').readAsStringSync()),
      ),
      'user': owner == null ? null : {'id': owner},
    };
    return bootstrap;
  }

  @override
  Future<dynamic> get(String path) async {
    if (!connected) {
      throw const ApiException('Keine Verbindung', connectionFailure: true);
    }
    if (path.startsWith('/api/app/offline/v2/lexicons')) {
      if (lexiconCatalogOffline) {
        throw const ApiException('Keine Verbindung', connectionFailure: true);
      }
      throw const ApiException('Nicht verfügbar', status: 404);
    }
    if (path == '/api/app/offline/resources') {
      if (catalogOffline) {
        throw const ApiException('Keine Verbindung', connectionFailure: true);
      }
      return {
        'version': 1,
        'owner': owner,
        'resources': [
          for (final id in allowed) {'id': id, 'kind': 'bible'},
        ],
      };
    }
    return {'workspaces': []};
  }

  @override
  Future<Json> page(String path) async {
    final data = asMap(
      jsonDecode(File('test/fixtures/reader.json').readAsStringSync()),
    );
    data['user'] = owner == null ? null : {'id': owner};
    return data;
  }
}

Future<void> waitFor(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 200; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 20));
    if (finder.evaluate().isNotEmpty) {
      return;
    }
  }
  fail('Expected widget did not appear: $finder');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    dir = await Directory.systemTemp.createTemp('akribos-offline-session');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => dir.path);
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await dir.delete(recursive: true);
  });

  Future<void> seed(WidgetTester tester) async {
    await tester.runAsync(() async {
      final origin = Uri.parse('https://example.test');
      final work = package('bible', 'bible', [chapter(43, 3)])..['owner'] = 'A';
      await OfflineResourceStore(origin: origin, userId: 'A').write(work);
      await OfflineIdentityStore(origin: origin).write('A', 'session-A');
    });
  }

  testWidgets('cold start reads a matching saved session and returns online', (
    tester,
  ) async {
    await seed(tester);
    final api = OfflineTestApi();
    addTearDown(api.dispose);
    await tester.pumpWidget(AkribosApp(api: api, enableLinks: false));
    await waitFor(tester, find.byType(OfflineReaderScreen));
    expect(find.text('Johannes 3'), findsOneWidget);
    api.connected = true;
    await tester.tap(find.text('Online erneut verbinden'));
    await waitFor(tester, find.text('Mehr'));
    expect(find.byType(OfflineReaderScreen), findsNothing);
    expect(api.bootstrap['user']['id'], 'A');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'restores position, font scale and verse layout across offline restarts',
    (tester) async {
      final origin = Uri.parse('https://example.test');
      await tester.runAsync(() async {
        final work = package('bible', 'bible', [chapter(43, 2), chapter(43, 3)])
          ..['owner'] = 'A';
        final store = OfflineResourceStore(origin: origin, userId: 'A');
        await store.write(work);
        await store.writePosition('bible', {
          'book': 43,
          'chapter': 2,
          'verse': 1,
        });
        await ReaderLocalStore(
          origin: origin,
          userId: 'A',
        ).write('/?layout=single', versePerLine: true);
        await OfflineIdentityStore(origin: origin)
            .write('A', 'session-A', fontScale: 150);
      });
      final api = OfflineTestApi();
      addTearDown(api.dispose);
      await tester.pumpWidget(AkribosApp(api: api, enableLinks: false));
      await waitFor(tester, find.byType(OfflineReaderScreen));
      var reader = tester.widget<OfflineReaderScreen>(
        find.byType(OfflineReaderScreen),
      );
      expect(reader.initialReference?['chapter'], 2);
      expect(reader.fontScale, 1.5);
      expect(reader.versePerLine, isTrue);
      expect(find.text('Johannes 2'), findsOneWidget);
      await tester.tap(find.text('Buch und Kapitel · Joh2'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('passage-chapter-3')));
      await tester.pumpAndSettle();
      Json? position;
      for (var i = 0; i < 100; i++) {
        position = await tester.runAsync<Json?>(
          () =>
              OfflineResourceStore(origin: origin, userId: 'A').readPosition(),
        );
        if (asMap(position?['reference'])['chapter'] == 3) {
          break;
        }
        await tester.pump(const Duration(milliseconds: 20));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
      }
      expect(asMap(position?['reference'])['chapter'], 3);
      await tester.pumpWidget(const SizedBox.shrink());
      final restartedApi = OfflineTestApi();
      addTearDown(restartedApi.dispose);
      await tester.pumpWidget(
        AkribosApp(api: restartedApi, enableLinks: false),
      );
      await waitFor(tester, find.byType(OfflineReaderScreen));
      reader = tester.widget<OfflineReaderScreen>(
        find.byType(OfflineReaderScreen),
      );
      expect(reader.initialReference?['chapter'], 3);
      expect(reader.fontScale, 1.5);
      expect(reader.versePerLine, isTrue);
      expect(find.text('Johannes 3'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'changed or missing session fingerprint cannot open cached private text',
    (tester) async {
      await seed(tester);
      final api = OfflineTestApi()..fingerprint = 'session-B';
      addTearDown(api.dispose);
      await tester.pumpWidget(AkribosApp(api: api, enableLinks: false));
      await waitFor(
        tester,
        find.textContaining('Offline-Anmeldung stimmt nicht mehr'),
      );
      expect(find.byType(OfflineReaderScreen), findsNothing);
      expect(find.text('Johannes 3'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('reconnect removes a resource whose grant has been revoked', (
    tester,
  ) async {
    await seed(tester);
    final api = OfflineTestApi();
    addTearDown(api.dispose);
    await tester.pumpWidget(AkribosApp(api: api, enableLinks: false));
    await waitFor(tester, find.byType(OfflineReaderScreen));
    api.connected = true;
    api.allowed = [];
    await tester.tap(find.text('Online erneut verbinden'));
    await waitFor(tester, find.text('Mehr'));
    List<String>? ids;
    for (var attempt = 0; attempt < 100; attempt++) {
      ids = await tester.runAsync(
        () => OfflineResourceStore(origin: api.origin, userId: 'A').ids(),
      );
      if (ids?.isEmpty == true) {
        break;
      }
      await tester.pump(const Duration(milliseconds: 20));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
    }
    expect(ids, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'temporary catalog connection failure preserves a matching offline identity',
    (tester) async {
      await seed(tester);
      final api = OfflineTestApi()
        ..connected = true
        ..catalogOffline = true;
      addTearDown(api.dispose);
      await tester.pumpWidget(AkribosApp(api: api, enableLinks: false));
      await waitFor(tester, find.text('Mehr'));
      final identity = await tester.runAsync(
        () => OfflineIdentityStore(origin: api.origin).read(),
      );
      expect(identity?['owner'], 'A');
      expect(identity?['fingerprint'], 'session-A');
      final ids = await tester.runAsync(
        () => OfflineResourceStore(origin: api.origin, userId: 'A').ids(),
      );
      expect(ids, ['bible']);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('an authentication change interrupts an in-flight offline open', (
    tester,
  ) async {
    await seed(tester);
    final api = OfflineTestApi()..connected = true;
    addTearDown(api.dispose);
    await tester.pumpWidget(AkribosApp(api: api, enableLinks: false));
    await waitFor(tester, find.text('Mehr'));
    final scope = AppScope.of(tester.element(find.byType(Scaffold).first));
    final pending = Completer<String?>();
    final started = Completer<void>();
    api.delayedFingerprint = pending;
    api.fingerprintStarted = started;
    api.connected = false;
    api.onReaderConnectionFailure!();
    for (var i = 0; i < 200 && !started.isCompleted; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(started.isCompleted, isTrue);
    api.owner = 'B';
    api.fingerprint = 'session-B';
    api.connected = true;
    final changed = scope.authenticationChanged();
    await tester.pump();
    expect(
      find.byKey(const ValueKey('automatic-offline-transition')),
      findsNothing,
    );
    pending.complete('session-A');
    var finished = false;
    changed.then((_) => finished = true);
    for (var i = 0; i < 200 && !finished; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(finished, isTrue);
    expect(find.byType(OfflineReaderScreen), findsNothing);
    expect(asMap(api.bootstrap['user'])['id'], 'B');
    final previous = await tester.runAsync(
      () => OfflineResourceStore(origin: api.origin, userId: 'A').ids(),
    );
    expect(previous, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'a failed lexicon check still removes revoked Bible data and fails closed',
    (tester) async {
      await seed(tester);
      final api = OfflineTestApi()
        ..connected = true
        ..allowed = []
        ..lexiconCatalogOffline = true;
      addTearDown(api.dispose);
      await tester.runAsync(
        () => OfflineResourceStore(origin: api.origin, userId: 'A').write({
          'version': 2,
          'owner': 'A',
          'resource': {'id': 'lex', 'name': 'Lexikon', 'kind': 'lexicon'},
          'entries': <Object>[],
        }),
      );
      await tester.pumpWidget(AkribosApp(api: api, enableLinks: false));
      await waitFor(tester, find.text('Mehr'));
      final ids = await tester.runAsync(
        () => OfflineResourceStore(origin: api.origin, userId: 'A').ids(),
      );
      final identity = await tester.runAsync(
        () => OfflineIdentityStore(origin: api.origin).read(),
      );
      expect(ids, ['lex']);
      expect(identity, isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
