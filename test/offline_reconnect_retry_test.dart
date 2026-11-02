import 'dart:io';

import 'package:akribos_app/features/reader/offline_reader_screen.dart';
import 'package:akribos_app/features/reader/offline_resource_store.dart';
import 'package:akribos_app/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_secure_storage/test/test_flutter_secure_storage_platform.dart';
// The platform override injects a real storage failure for the integration test.
// ignore: depend_on_referenced_packages
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'features/reader/offline_reader_screen_test.dart' show chapter, package;
import 'offline_session_integration_test.dart' show OfflineTestApi, waitFor;

class FailingPositionStorage extends TestFlutterSecureStoragePlatform {
  FailingPositionStorage(super.data);
  int failuresRemaining = 3;
  int positionWrites = 0;

  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) async {
    if (key.startsWith('akribos.offline.position.v1.')) {
      positionWrites++;
      if (failuresRemaining > 0) {
        failuresRemaining--;
        throw PlatformException(
          code: 'unavailable',
          message: 'Temporärer Speicherfehler',
        );
      }
    }
    await super.write(key: key, value: value, options: options);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'failed position saves retain offline view and retry the latest draft on reconnect',
    (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      SharedPreferences.setMockInitialValues({});
      final dir = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('akribos-offline-retry'),
      ))!;
      const channel = MethodChannel('plugins.flutter.io/path_provider');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => dir.path);
      addTearDown(() async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
        FlutterSecureStorage.setMockInitialValues({});
        await dir.delete(recursive: true);
      });
      final origin = Uri.parse('https://example.test');
      await tester.runAsync(() async {
        final work = package('bible', 'bible', [chapter(43, 3)])
          ..['owner'] = 'A';
        await OfflineResourceStore(origin: origin, userId: 'A').write(work);
        await OfflineIdentityStore(origin: origin).write('A', 'session-A');
      });
      final values = (await tester.runAsync(
        () => const FlutterSecureStorage().readAll(),
      ))!;
      final storage = FailingPositionStorage(Map.of(values));
      FlutterSecureStoragePlatform.instance = storage;
      final api = OfflineTestApi();
      addTearDown(api.dispose);
      await tester.pumpWidget(AkribosApp(api: api, enableLinks: false));
      await waitFor(tester, find.text('Offline lesen'));
      await tester.tap(find.text('Offline lesen'));
      await waitFor(tester, find.byType(OfflineReaderScreen));
      tester
          .widget<OfflineReaderScreen>(find.byType(OfflineReaderScreen))
          .onPositionChanged!('bible', {'book': 43, 'chapter': 3, 'verse': 12});
      for (var i = 0; i < 100 && storage.positionWrites < 1; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(storage.positionWrites, 1);
      api.connected = true;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      for (var i = 0; i < 100 && storage.positionWrites < 2; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(storage.positionWrites, 2);
      expect(find.byType(OfflineReaderScreen), findsOneWidget);
      await tester.tap(find.text('Online erneut verbinden'));
      for (var i = 0; i < 100 && storage.positionWrites < 3; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(storage.positionWrites, 3);
      expect(find.byType(OfflineReaderScreen), findsOneWidget);
      await tester.tap(find.text('Online erneut verbinden'));
      await waitFor(tester, find.text('Mehr'));
      expect(storage.positionWrites, 4);
      final position = await tester.runAsync(
        () => OfflineResourceStore(origin: origin, userId: 'A').readPosition(),
      );
      expect(position?['reference'], {'book': 43, 'chapter': 3, 'verse': 12});
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
