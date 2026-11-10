import 'dart:async';
import 'dart:io';

import 'package:akribos_app/features/reader/offline_reader_screen.dart';
import 'package:akribos_app/features/reader/offline_resource_store.dart';
import 'package:akribos_app/features/reader/verse_text.dart';
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

class PausedPositionStorage extends TestFlutterSecureStoragePlatform {
  PausedPositionStorage(super.data);
  final started = Completer<void>();
  final release = Completer<void>();
  final finished = Completer<void>();

  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) async {
    if (key.startsWith('akribos.offline.position.v1.') &&
        !started.isCompleted) {
      started.complete();
      await release.future;
    }
    await super.write(key: key, value: value, options: options);
    if (key.startsWith('akribos.offline.position.v1.') &&
        !finished.isCompleted) {
      finished.complete();
    }
  }
}

class ObservedOfflineApi extends OfflineTestApi {
  final catalogStarted = Completer<void>();

  @override
  Future<dynamic> get(String path) {
    if (path == '/api/app/offline/resources' && !catalogStarted.isCompleted) {
      catalogStarted.complete();
    }
    return super.get(path);
  }
}

Future<void> waitForRightsCheck(WidgetTester tester) async {
  for (var attempt = 0; attempt < 200; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 20));
    if (find.text('Offline-Freigaben werden geprüft …').evaluate().isEmpty) {
      return;
    }
  }
  fail('The offline rights check did not finish.');
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
      await waitForRightsCheck(tester);
      expect(find.byType(OfflineReaderScreen), findsOneWidget);
      await tester.tap(find.text('Online erneut verbinden'));
      for (var i = 0; i < 100 && storage.positionWrites < 3; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(storage.positionWrites, 3);
      await waitForRightsCheck(tester);
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

  for (final automatic in [false, true]) {
    testWidgets('revoked resource is removed despite a position save failure '
        '(${automatic ? 'resume' : 'manual reconnect'})', (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      SharedPreferences.setMockInitialValues({});
      final dir = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('akribos-offline-revoked'),
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
      final storage = FailingPositionStorage(Map.of(values))
        ..failuresRemaining = 100;
      FlutterSecureStoragePlatform.instance = storage;
      final api = OfflineTestApi();
      addTearDown(api.dispose);
      await tester.pumpWidget(AkribosApp(api: api, enableLinks: false));
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
      expect(storage.positionWrites, greaterThanOrEqualTo(1));
      api.connected = true;
      api.allowed = [];
      if (automatic) {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
      } else {
        await tester.tap(find.text('Online erneut verbinden'));
      }
      await waitFor(tester, find.text('Mehr'));
      expect(find.byType(OfflineReaderScreen), findsNothing);
      final ids = await tester.runAsync(
        () => OfflineResourceStore(origin: origin, userId: 'A').ids(),
      );
      expect(ids, isEmpty);
      expect(storage.positionWrites, greaterThanOrEqualTo(2));
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  for (final modal in ['lexicon', 'footnote']) {
    for (final fast in [false, true]) {
      testWidgets(
        '${fast ? 'fast revocation' : 'pending position storage'} hides the $modal while rights are checked',
        (tester) async {
          FlutterSecureStorage.setMockInitialValues({});
          SharedPreferences.setMockInitialValues({});
          final dir = (await tester.runAsync(
            () => Directory.systemTemp.createTemp('akribos-offline-paused'),
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
            final source = chapter(43, 3);
            final rows = (source['chapter'] as Map)['rows'] as List;
            ((rows.first as Map)['cells'] as List).first['segments'] = [
              {'kind': 'w', 'text': 'Liebe', 'strong': 'G26'},
              {'kind': 'note', 'marker': '7', 'text': 'Geheimer Fußnotentext'},
            ];
            final work = package('bible', 'bible', [source])..['owner'] = 'A';
            final lexicon = {
              'version': 2,
              'owner': 'A',
              'resource': {'id': 'lex', 'name': 'Lexikon', 'kind': 'lexicon'},
              'entries': [
                {
                  'strong': 'G26',
                  'language': 'grc',
                  'lemma': 'ἀγάπη',
                  'definitionHtml': '<p>Liebe erklärt</p>',
                  'seeAlso': <String>[],
                },
              ],
            };
            final store = OfflineResourceStore(origin: origin, userId: 'A');
            await store.write(work);
            await store.write(lexicon);
            await OfflineIdentityStore(origin: origin).write('A', 'session-A');
          });
          final values = (await tester.runAsync(
            () => const FlutterSecureStorage().readAll(),
          ))!;
          final storage = PausedPositionStorage(Map.of(values));
          addTearDown(() {
            if (!storage.release.isCompleted) storage.release.complete();
          });
          FlutterSecureStoragePlatform.instance = storage;
          final api = ObservedOfflineApi();
          addTearDown(api.dispose);
          await tester.pumpWidget(AkribosApp(api: api, enableLinks: false));
          await waitFor(tester, find.byType(OfflineReaderScreen));
          final secret = modal == 'lexicon'
              ? 'Liebe erklärt'
              : 'Geheimer Fußnotentext';
          if (modal == 'lexicon') {
            final verse = tester.widget<VerseText>(
              find.byType(VerseText).first,
            );
            verse.passages!.first.onWord!({
              'kind': 'w',
              'text': 'Liebe',
              'strong': 'G26',
            }, 0);
          } else {
            final painter = tester
                .widgetList<CustomPaint>(find.byType(CustomPaint))
                .map((widget) => widget.foregroundPainter)
                .whereType<VerseNotePainter>()
                .first;
            final marker = painter
                .rectangles(painter.notes.first)
                .first
                .shift(painter.paragraph()!.localToGlobal(Offset.zero));
            await tester.tapAt(marker.center);
          }
          await waitFor(
            tester,
            find.textContaining(secret, findRichText: true),
          );
          if (fast) {
            // A deliberately slow route makes the race deterministic: it must
            // remain covered after the network check has already finished.
            unawaited(
              Navigator.of(
                tester.element(find.byType(OfflineReaderScreen)),
                rootNavigator: true,
              ).push<void>(
                PageRouteBuilder<void>(
                  opaque: false,
                  transitionDuration: Duration.zero,
                  reverseTransitionDuration: const Duration(seconds: 10),
                  pageBuilder: (_, _, _) => const Center(
                    child: Text('Geschützter Dialog während Animation'),
                  ),
                ),
              ),
            );
            await tester.pump();
          }
          if (!fast) {
            tester
                .widget<OfflineReaderScreen>(find.byType(OfflineReaderScreen))
                .onPositionChanged!('bible', {
              'book': 43,
              'chapter': 3,
              'verse': 12,
            });
            for (var i = 0; i < 200 && !storage.started.isCompleted; i++) {
              await tester.runAsync(
                () => Future<void>.delayed(const Duration(milliseconds: 10)),
              );
              await tester.pump(const Duration(milliseconds: 20));
            }
            expect(storage.started.isCompleted, isTrue);
          }
          api.connected = true;
          api.allowed = [];
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
          await waitFor(
            tester,
            find.text('Offline-Freigaben werden geprüft …'),
          );
          expect(
            find.textContaining(secret, findRichText: true).hitTestable(),
            findsNothing,
          );
          expect(find.byType(BlockSemantics), findsWidgets);
          if (fast) {
            // The network and position flush can finish before the modal's
            // reverse animation. Its contents must remain covered on each frame.
            await waitFor(tester, find.text('Mehr'));
            expect(find.byType(OfflineReaderScreen), findsNothing);
            final closingSecret = find.textContaining(
              'Geschützter Dialog während Animation',
              findRichText: true,
              skipOffstage: false,
            );
            expect(closingSecret, findsWidgets);
            for (var frame = 0; frame < 20; frame++) {
              await tester.runAsync(
                () => Future<void>.delayed(const Duration(milliseconds: 10)),
              );
              await tester.pump(const Duration(milliseconds: 16));
              expect(
                find.byKey(const ValueKey('offline-rights-overlay')),
                findsOneWidget,
              );
              expect(
                find.textContaining(secret, findRichText: true).hitTestable(),
                findsNothing,
              );
            }
            await tester.pumpWidget(const SizedBox.shrink());
            return;
          }
          await tester.pump(const Duration(milliseconds: 300));
          expect(find.textContaining(secret, findRichText: true), findsNothing);
          for (var i = 0; i < 200 && !api.catalogStarted.isCompleted; i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 10)),
            );
            await tester.pump(const Duration(milliseconds: 20));
          }
          expect(api.catalogStarted.isCompleted, isTrue);
          final semanticsBoundary = tester.widget<ExcludeSemantics>(
            find
                .ancestor(
                  of: find.byType(OfflineReaderScreen),
                  matching: find.byType(ExcludeSemantics),
                )
                .first,
          );
          expect(semanticsBoundary.excluding, isTrue);
          final inputBoundary = tester.widget<AbsorbPointer>(
            find
                .ancestor(
                  of: find.byType(OfflineReaderScreen),
                  matching: find.byType(AbsorbPointer),
                )
                .first,
          );
          expect(inputBoundary.absorbing, isTrue);
          // The platform write never completes during reconnect. The rights check
          // must still finish and remove the revoked Bible without releasing it.
          await tester.pump(const Duration(seconds: 6));
          await waitFor(tester, find.text('Mehr'));
          expect(storage.release.isCompleted, isFalse);
          expect(find.byType(OfflineReaderScreen), findsNothing);
          final ids = await tester.runAsync(
            () => OfflineResourceStore(origin: origin, userId: 'A').ids(),
          );
          expect(ids, isNot(contains('bible')));
          storage.release.complete();
          await tester.runAsync(() => storage.finished.future);
          // The late write was invalidated by the package removal and cleaned up.
          for (var i = 0; i < 100; i++) {
            final position = await tester.runAsync(
              () => OfflineResourceStore(
                origin: origin,
                userId: 'A',
              ).readPosition(),
            );
            if (position == null) break;
            await tester.pump(const Duration(milliseconds: 20));
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 10)),
            );
          }
          final latePosition = await tester.runAsync(
            () => OfflineResourceStore(
              origin: origin,
              userId: 'A',
            ).readPosition(),
          );
          expect(latePosition, isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }
}
