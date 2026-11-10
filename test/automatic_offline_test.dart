import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:akribos_app/core/api_client.dart';
import 'package:akribos_app/features/reader/offline_reader_screen.dart';
import 'package:akribos_app/features/reader/offline_resource_store.dart';
import 'package:akribos_app/features/reader/reader_local_store.dart';
import 'package:akribos_app/features/reader/reader_screen.dart';
import 'package:akribos_app/features/reader/reader_state.dart';
import 'package:akribos_app/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'features/reader/offline_reader_screen_test.dart' show chapter, package;
import 'offline_session_integration_test.dart' show OfflineTestApi, waitFor;

class FailingReaderApi extends OfflineTestApi {
  @override
  Future<Json> page(String path) async {
    onReaderConnectionFailure?.call();
    throw const ApiException('Keine Verbindung', connectionFailure: true);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  final origin = Uri.parse('https://example.test');
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    dir = await Directory.systemTemp.createTemp('automatic-offline');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => dir.path);
    await OfflineResourceStore(origin: origin, userId: 'A').write(
      package('bible', 'bible', [chapter(43, 2), chapter(43, 3)])
        ..['owner'] = 'A',
    );
    await OfflineIdentityStore(origin: origin).write('A', 'session-A');
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await dir.delete(recursive: true);
  });
  testWidgets(
    'cold start uses the more recent online position and reconnects automatically',
    (tester) async {
      await tester.runAsync(() async {
        await OfflineResourceStore(
          origin: origin,
          userId: 'A',
        ).writePosition('bible', {'book': 43, 'chapter': 2});
        await ReaderLocalStore(
          origin: origin,
          userId: 'A',
        ).write('/Joh3?layout=single&tab=1.1:bible:A:Joh3&active=1.1&focus=1');
      });
      final api = OfflineTestApi();
      addTearDown(api.dispose);
      await tester.pumpWidget(AkribosApp(api: api, enableLinks: false));
      await waitFor(tester, find.byType(OfflineReaderScreen));
      expect(
        tester
            .widget<OfflineReaderScreen>(find.byType(OfflineReaderScreen))
            .initialReference?['chapter'],
        3,
      );
      api.connected = true;
      await tester.pump(const Duration(seconds: 31));
      await waitFor(tester, find.text('Mehr'));
      final snapshot = await tester.runAsync(
        () => ReaderLocalStore(origin: origin, userId: 'A').read(),
      );
      expect(
        readerPositionFromPath(snapshot!['path'])?.reference['chapter'],
        3,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'a dialog is kept open and the reader failure is retried after it closes',
    (tester) async {
      final api = OfflineTestApi()..connected = true;
      addTearDown(api.dispose);
      await tester.pumpWidget(AkribosApp(api: api, enableLinks: false));
      await waitFor(tester, find.byType(ReaderScreen));
      for (var i = 0; i < 100; i++) {
        if (tester
                .widget<ReaderScreen>(find.byType(ReaderScreen))
                .controller
                ?.activeResource !=
            null) {
          break;
        }
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 20));
      }
      final context = tester.element(find.byType(ReaderScreen));
      unawaited(
        showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Offener Entwurf'),
            content: const TextField(),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Schließen'),
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'Entwurf bleibt');
      api.connected = false;
      api.onReaderConnectionFailure!();
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('Offener Entwurf'), findsOneWidget);
      expect(find.text('Entwurf bleibt'), findsOneWidget);
      expect(find.byType(OfflineReaderScreen), findsNothing);
      await tester.tap(find.text('Schließen'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 2));
      await waitFor(
        tester,
        find.text('Aktuelles Werk nicht offline gespeichert'),
      );
      await tester.tap(find.text('bible'));
      await waitFor(tester, find.byType(OfflineReaderScreen));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('ambiguous legacy positions require a choice', (tester) async {
    await tester.runAsync(() async {
      await OfflineResourceStore(
        origin: origin,
        userId: 'A',
      ).writePosition('bible', {'book': 43, 'chapter': 2});
      await ReaderLocalStore(
        origin: origin,
        userId: 'A',
      ).write('/Joh3?layout=single&tab=1.1:bible:A:Joh3&active=1.1&focus=1');
      const storage = FlutterSecureStorage();
      for (final entry in (await storage.readAll()).entries) {
        if (entry.key.startsWith('akribos.reader.local.v1.') ||
            entry.key.startsWith('akribos.offline.position.v1.')) {
          final data = jsonDecode(entry.value) as Map<String, dynamic>;
          data.remove('updatedAt');
          await storage.write(key: entry.key, value: jsonEncode(data));
        }
      }
    });
    final api = OfflineTestApi();
    addTearDown(api.dispose);
    await tester.pumpWidget(AkribosApp(api: api, enableLinks: false));
    await waitFor(tester, find.text('Lesestelle auswählen'));
    expect(find.textContaining('Online: bible · Joh3'), findsOneWidget);
    expect(find.textContaining('Offline: bible · Joh2'), findsOneWidget);
    await tester.tap(find.text('Offline-Lesestelle'));
    await waitFor(tester, find.byType(OfflineReaderScreen));
    expect(
      tester
          .widget<OfflineReaderScreen>(find.byType(OfflineReaderScreen))
          .initialReference?['chapter'],
      2,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('transition blocks navigation while identity is being checked', (
    tester,
  ) async {
    final api = OfflineTestApi()..connected = true;
    addTearDown(api.dispose);
    await tester.pumpWidget(AkribosApp(api: api, enableLinks: false));
    await waitFor(tester, find.text('Mehr'));
    final started = Completer<void>();
    final pending = Completer<String?>();
    api.fingerprintStarted = started;
    api.delayedFingerprint = pending;
    api.connected = false;
    api.onReaderConnectionFailure!();
    for (var i = 0; i < 100 && !started.isCompleted; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(started.isCompleted, isTrue);
    await tester.tap(find.text('Mehr'), warnIfMissed: false);
    await tester.pump();
    expect(find.text('Offener Entwurf'), findsNothing);
    pending.complete('session-A');
    await waitFor(
      tester,
      find.text('Aktuelles Werk nicht offline gespeichert'),
    );
    await tester.tap(find.text('bible'));
    await waitFor(tester, find.byType(OfflineReaderScreen));
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'first Reader request failure preserves the stored online position',
    (tester) async {
      await tester.runAsync(() async {
        await OfflineResourceStore(
          origin: origin,
          userId: 'A',
        ).writePosition('bible', {'book': 43, 'chapter': 2});
        await ReaderLocalStore(
          origin: origin,
          userId: 'A',
        ).write('/Joh3?layout=single&tab=1.1:bible:A:Joh3&active=1.1&focus=1');
      });
      final api = FailingReaderApi()..connected = true;
      addTearDown(api.dispose);
      await tester.pumpWidget(AkribosApp(api: api, enableLinks: false));
      await waitFor(tester, find.byType(OfflineReaderScreen));
      expect(
        tester
            .widget<OfflineReaderScreen>(find.byType(OfflineReaderScreen))
            .initialReference?['chapter'],
        3,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('a hidden Reader failure waits until the Reader is revisited', (
    tester,
  ) async {
    final api = OfflineTestApi()..connected = true;
    addTearDown(api.dispose);
    await tester.pumpWidget(AkribosApp(api: api, enableLinks: false));
    await waitFor(tester, find.text('Mehr'));
    await tester.tap(find.text('Mehr'));
    await tester.pumpAndSettle();
    api.connected = false;
    api.onReaderConnectionFailure!();
    await tester.pump(const Duration(seconds: 2));
    expect(find.byType(OfflineReaderScreen), findsNothing);
    await tester.tap(find.text('Lesen'));
    await tester.pump();
    await waitFor(
      tester,
      find.text('Aktuelles Werk nicht offline gespeichert'),
    );
    await tester.tap(find.text('bible'));
    await waitFor(tester, find.byType(OfflineReaderScreen));
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
