import 'dart:async';
import 'dart:io';

import 'package:akribos_app/core/api_client.dart';
import 'package:akribos_app/features/reader/offline_reader_screen.dart';
import 'package:akribos_app/features/reader/offline_resource_store.dart';
import 'package:akribos_app/features/reader/reader_local_store.dart';
import 'package:akribos_app/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_secure_storage/test/test_flutter_secure_storage_platform.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'features/reader/offline_reader_screen_test.dart' show chapter, package;
import 'offline_session_integration_test.dart' show OfflineTestApi, waitFor;

class PausedSnapshotStorage extends TestFlutterSecureStoragePlatform {
  PausedSnapshotStorage(super.data);
  final started = Completer<void>();
  final release = Completer<void>();
  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) async {
    if (key.startsWith('akribos.reader.local.v1.') && !started.isCompleted) {
      started.complete();
      await release.future;
    }
    await super.write(key: key, value: value, options: options);
  }
}

class PausedIndexStorage extends TestFlutterSecureStoragePlatform {
  PausedIndexStorage(super.data);
  bool armed = false;
  bool freshBootstrap = false;
  bool staleSnapshotWrite = false;
  final started = Completer<void>();
  final release = Completer<void>();
  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) async {
    if (armed &&
        key.startsWith('akribos.offline.index.v1.') &&
        !started.isCompleted) {
      started.complete();
      await release.future;
    }
    return super.read(key: key, options: options);
  }

  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) async {
    if (started.isCompleted &&
        !freshBootstrap &&
        key.startsWith('akribos.reader.local.v1.')) {
      staleSnapshotWrite = true;
    }
    await super.write(key: key, value: value, options: options);
  }
}

class ArmIndexApi extends OfflineTestApi {
  ArmIndexApi(this.storage);
  final PausedIndexStorage storage;
  int checks = 0;
  @override
  Future<String?> offlineSessionFingerprint() async {
    final value = await super.offlineSessionFingerprint();
    if (++checks == 4) storage.armed = true;
    return value;
  }

  @override
  Future<Json> loadBootstrap() async {
    final value = await super.loadBootstrap();
    if (storage.started.isCompleted) storage.freshBootstrap = true;
    return value;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'session change during snapshot write clears old private reader',
    (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      SharedPreferences.setMockInitialValues({});
      final dir = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('offline-identity-race'),
      ))!;
      const channel = MethodChannel('plugins.flutter.io/path_provider');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => dir.path);
      final origin = Uri.parse('https://example.test');
      await tester.runAsync(() async {
        await OfflineResourceStore(
          origin: origin,
          userId: 'A',
        ).write(package('bible', 'bible', [chapter(43, 3)])..['owner'] = 'A');
        await OfflineIdentityStore(origin: origin).write('A', 'session-A');
        await ReaderLocalStore(
          origin: origin,
          userId: 'A',
        ).write('/Joh3?layout=single&tab=1.1:bible:A:Joh3&active=1.1&focus=1');
      });
      final values = (await tester.runAsync(
        () => const FlutterSecureStorage().readAll(),
      ))!;
      final storage = PausedSnapshotStorage(Map.of(values));
      FlutterSecureStoragePlatform.instance = storage;
      addTearDown(() async {
        if (!storage.release.isCompleted) storage.release.complete();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
        FlutterSecureStorage.setMockInitialValues({});
        await dir.delete(recursive: true);
      });
      final api = OfflineTestApi();
      addTearDown(api.dispose);
      await tester.pumpWidget(AkribosApp(api: api, enableLinks: false));
      await waitFor(tester, find.byType(OfflineReaderScreen));
      api.connected = true;
      await tester.tap(find.text('Online erneut verbinden'));
      for (var i = 0; i < 200 && !storage.started.isCompleted; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(storage.started.isCompleted, isTrue);
      api.invalidateOfflineIdentity();
      api.owner = 'B';
      api.fingerprint = 'session-B';
      storage.release.complete();
      await waitFor(tester, find.text('Mehr'));
      expect(find.byType(OfflineReaderScreen), findsNothing);
      expect(asMap(api.bootstrap['user'])['id'], 'B');
      expect(find.text('Johannes 3'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  for (final sameAccount in [true, false]) {
    testWidgets(
      'session rotation during index read ${sameAccount ? 'retains same-account downloads' : 'clears previous-account downloads'}',
      (tester) async {
        FlutterSecureStorage.setMockInitialValues({});
        SharedPreferences.setMockInitialValues({});
        final dir = (await tester.runAsync(
          () => Directory.systemTemp.createTemp('offline-index-race'),
        ))!;
        const channel = MethodChannel('plugins.flutter.io/path_provider');
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (_) async => dir.path);
        final origin = Uri.parse('https://example.test');
        await tester.runAsync(() async {
          await OfflineResourceStore(
            origin: origin,
            userId: 'A',
          ).write(package('bible', 'bible', [chapter(43, 3)])..['owner'] = 'A');
          await OfflineIdentityStore(origin: origin).write('A', 'session-A');
          await ReaderLocalStore(origin: origin, userId: 'A').write(
            '/Joh3?layout=single&tab=1.1:bible:A:Joh3&active=1.1&focus=1',
          );
        });
        final values = (await tester.runAsync(
          () => const FlutterSecureStorage().readAll(),
        ))!;
        final storage = PausedIndexStorage(Map.of(values));
        FlutterSecureStoragePlatform.instance = storage;
        addTearDown(() async {
          if (!storage.release.isCompleted) storage.release.complete();
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(channel, null);
          FlutterSecureStorage.setMockInitialValues({});
          await dir.delete(recursive: true);
        });
        final api = ArmIndexApi(storage);
        addTearDown(api.dispose);
        await tester.pumpWidget(AkribosApp(api: api, enableLinks: false));
        await waitFor(tester, find.byType(OfflineReaderScreen));
        api.connected = true;
        await tester.tap(find.text('Online erneut verbinden'));
        for (var i = 0; i < 200 && !storage.started.isCompleted; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump(const Duration(milliseconds: 20));
        }
        expect(storage.started.isCompleted, isTrue);
        api.invalidateOfflineIdentity();
        api.fingerprint = 'new-session';
        if (!sameAccount) api.owner = 'B';
        storage.release.complete();
        await waitFor(tester, find.text('Mehr'));
        expect(find.byType(OfflineReaderScreen), findsNothing);
        expect(asMap(api.bootstrap['user'])['id'], sameAccount ? 'A' : 'B');
        expect(storage.staleSnapshotWrite, isFalse);
        final ids = await tester.runAsync(
          () => OfflineResourceStore(origin: origin, userId: 'A').ids(),
        );
        expect(ids, sameAccount ? ['bible'] : isEmpty);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
