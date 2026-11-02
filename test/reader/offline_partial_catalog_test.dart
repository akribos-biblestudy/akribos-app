import 'dart:io';

import 'package:akribos_app/core/api_client.dart';
import 'package:akribos_app/features/reader/offline_resource_manager.dart';
import 'package:akribos_app/features/reader/offline_resources_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'offline_resource_manager_test.dart'
    show FakeApi, catalog, package, lexiconPackage;
import 'offline_resource_store_test.dart' show MemoryKeys;
import 'offline_resources_screen_test.dart' show finishLoading;

void main() {
  late Directory dir;
  late FakeApi api;
  late OfflineResourceManager manager;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('offline-partial-catalog');
    api = FakeApi()
      ..bootstrap = {
        'user': {'id': 'one'},
      };
    manager = OfflineResourceManager(
      api: api,
      userId: 'one',
      storage: MemoryKeys(),
      directory: () async => dir,
    );
    api.handler = (path) async => path == '/api/app/offline/resources'
        ? catalog('one', ['Bibel'])
        : package('one', 'Bibel');
    api.lexiconHandler = (_) async => throw const ApiException(
      'Lexikon-Katalog nicht erreichbar',
      connectionFailure: true,
    );
  });
  tearDown(() async {
    api.dispose();
    await dir.delete(recursive: true);
  });

  testWidgets(
    'v1 downloads remain available while unverified v2 packages stay gated',
    (tester) async {
      await tester.runAsync(
        () => manager.store.write(lexiconPackage('one', 'lex')),
      );
      await tester.pumpWidget(
        MaterialApp(home: OfflineResourcesScreen(manager: manager)),
      );
      await finishLoading(tester);
      expect(find.text('Bibel'), findsOneWidget);
      expect(find.text('Lexikon'), findsOneWidget);
      expect(
        find.textContaining('Freigabe der gespeicherten Offline-Lexika'),
        findsOneWidget,
      );
      await tester.tap(find.text('Herunterladen'));
      await tester.pump();
      await finishLoading(tester);
      expect(
        await tester.runAsync(() => manager.store.read('Bibel')),
        package('one', 'Bibel'),
      );
      expect(
        await tester.runAsync(() => manager.store.read('lex')),
        lexiconPackage('one', 'lex'),
      );
      final denied = await tester.runAsync(() async {
        try {
          await manager.reconcile();
          return false;
        } on ApiException {
          return true;
        }
      });
      expect(denied, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  test('v2 outage does not permit an unlisted lexicon download', () async {
    expect((await manager.catalog()).map((item) => item['id']), ['Bibel']);
    await expectLater(manager.download('lex'), throwsA(isA<ApiException>()));
    expect(await manager.store.ids(), isEmpty);
  });
}
