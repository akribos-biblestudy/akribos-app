import 'dart:async';
import 'dart:io';

import 'package:akribos_app/core/api_client.dart';
import 'package:akribos_app/features/reader/offline_resource_manager.dart';
import 'package:akribos_app/features/reader/offline_resources_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'offline_resource_manager_test.dart'
    show FakeApi, catalog, package, lexiconPackage;
import 'offline_resource_store_test.dart' show MemoryKeys;

Future<void> finishLoading(WidgetTester tester) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 20));
    if (find.byType(LinearProgressIndicator).evaluate().isEmpty) return;
  }
  fail('Offline screen did not finish loading');
}

void main() {
  late Directory dir;
  late FakeApi api;
  late OfflineResourceManager manager;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('akribos-screen-test');
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
  });
  tearDown(() async => dir.delete(recursive: true));

  testWidgets('downloads and removes an authorized work', (tester) async {
    var changed = 0;
    var reads = 0;
    api.handler = (path) async => path == '/api/app/offline/resources'
        ? catalog('one', ['Bibel'])
        : package('one', 'Bibel');
    await tester.pumpWidget(
      MaterialApp(
        home: OfflineResourcesScreen(
          manager: manager,
          onChanged: () => changed++,
          onReadOffline: () => reads++,
        ),
      ),
    );
    await finishLoading(tester);
    expect(find.text('Bibel'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Offline lesen'),
          )
          .onPressed,
      isNull,
    );
    await tester.tap(find.text('Herunterladen'));
    await tester.pump();
    await finishLoading(tester);
    expect(find.text('Auf diesem Gerät gespeichert'), findsOneWidget);
    await tester.tap(find.text('Offline lesen'));
    expect(reads, 1);
    expect(await tester.runAsync(manager.store.ids), ['Bibel']);
    await tester.tap(find.text('Entfernen'));
    await tester.pump();
    await finishLoading(tester);
    expect(await tester.runAsync(manager.store.ids), isEmpty);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Offline lesen'),
          )
          .onPressed,
      isNull,
    );
    expect(changed, 2);
  });

  testWidgets(
    'downloads a selection sequentially and keeps failed works selected',
    (tester) async {
      final paths = <String>[];
      api.handler = (path) async {
        if (path == '/api/app/offline/resources') {
          return catalog('one', ['A', 'B', 'C']);
        }
        paths.add(path);
        if (path.endsWith('/B')) {
          throw const ApiException('Download fehlgeschlagen');
        }
        return package('one', path.split('/').last);
      };
      await tester.pumpWidget(
        MaterialApp(home: OfflineResourcesScreen(manager: manager)),
      );
      await finishLoading(tester);
      await tester.tap(find.text('Alle verfügbaren Werke auswählen'));
      await tester.pump();
      await tester.tap(find.text('Auswahl herunterladen (3)'));
      await tester.pump();
      await finishLoading(tester);
      expect(paths, [
        '/api/app/offline/resources/A',
        '/api/app/offline/resources/B',
        '/api/app/offline/resources/C',
      ]);
      expect(await tester.runAsync(manager.store.ids), ['A', 'C']);
      expect(find.textContaining('B: Download fehlgeschlagen'), findsOneWidget);
      expect(find.text('Auswahl herunterladen (1)'), findsOneWidget);
    },
  );

  testWidgets('keeps saved works removable when the connection fails', (
    tester,
  ) async {
    await tester.runAsync(
      () => manager.store.write(package('one', 'Gespeichert')),
    );
    api.handler = (_) async => throw const ApiException('Keine Verbindung');
    await tester.pumpWidget(
      MaterialApp(home: OfflineResourcesScreen(manager: manager)),
    );
    await finishLoading(tester);
    expect(find.text('Keine Verbindung'), findsOneWidget);
    expect(find.text('Gespeichert'), findsOneWidget);
    await tester.tap(find.text('Entfernen'));
    await tester.pump();
    await finishLoading(tester);
    expect(await tester.runAsync(manager.store.ids), isEmpty);
  });

  testWidgets('shows download errors without saving an incomplete package', (
    tester,
  ) async {
    api.handler = (path) async => path == '/api/app/offline/resources'
        ? catalog('one', ['Bibel'])
        : throw const ApiException('Download fehlgeschlagen');
    await tester.pumpWidget(
      MaterialApp(home: OfflineResourcesScreen(manager: manager)),
    );
    await finishLoading(tester);
    await tester.tap(find.text('Herunterladen'));
    await tester.pump();
    await finishLoading(tester);
    expect(find.text('Download fehlgeschlagen'), findsOneWidget);
    expect(await tester.runAsync(manager.store.ids), isEmpty);
  });

  testWidgets('removes revoked works and informs the host', (tester) async {
    await tester.runAsync(() => manager.store.write(package('one', 'Alt')));
    api.handler = (_) async => catalog('one', []);
    var changed = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: OfflineResourcesScreen(
          manager: manager,
          onChanged: () => changed++,
        ),
      ),
    );
    await finishLoading(tester);
    expect(find.text('Alt'), findsNothing);
    expect(await tester.runAsync(manager.store.ids), isEmpty);
    expect(changed, 1);
  });

  testWidgets(
    'refreshes the saved list when a later catalog fails after a revocation',
    (tester) async {
      await tester.runAsync(() async {
        await manager.store.write(package('one', 'Alt'));
        await manager.store.write(lexiconPackage('one', 'lex'));
      });
      api.handler = (_) async => catalog('one', []);
      api.lexiconHandler = (_) async =>
          throw const ApiException('Keine Verbindung', connectionFailure: true);
      var changed = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: OfflineResourcesScreen(
            manager: manager,
            onChanged: () => changed++,
          ),
        ),
      );
      await finishLoading(tester);
      expect(find.text('Alt'), findsNothing);
      expect(find.text('Lexikon'), findsOneWidget);
      expect(await tester.runAsync(manager.store.ids), ['lex']);
      expect(changed, 1);
    },
  );

  testWidgets('does not show old account names after an identity change', (
    tester,
  ) async {
    await tester.runAsync(() => manager.store.write(package('one', 'Privat')));
    final pending = Completer<dynamic>();
    api.handler = (_) => pending.future;
    await tester.pumpWidget(
      MaterialApp(home: OfflineResourcesScreen(manager: manager)),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    api.bootstrap = {
      'user': {'id': 'two'},
    };
    pending.complete(catalog('one', []));
    await finishLoading(tester);
    expect(find.text('Privat'), findsNothing);
    expect(find.textContaining('Konto hat sich geändert'), findsOneWidget);
  });

  testWidgets('fits a narrow, scaled display and a wide landscape display', (
    tester,
  ) async {
    api.handler = (_) async =>
        catalog('one', ['Ein Werk mit einem sehr langen Titel']);
    tester.view.physicalSize = const Size(320, 580);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.7)),
          child: child!,
        ),
        home: OfflineResourcesScreen(manager: manager),
      ),
    );
    await finishLoading(tester);
    await tester.scrollUntilVisible(find.text('Herunterladen'), 200);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    tester.view.physicalSize = const Size(1200, 700);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
