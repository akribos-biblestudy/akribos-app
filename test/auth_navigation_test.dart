import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:akribos_app/core/api_client.dart';
import 'package:akribos_app/core/app_scope.dart';
import 'package:akribos_app/main.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _SessionApi extends AppApi {
  _SessionApi({this.owner = 'A'})
    : super(server: 'https://example.test', cookies: CookieJar());
  String? owner;
  int fontScale = 100, bootstrapCalls = 0, cleared = 0;
  bool bootstrapOffline = false;
  Completer<void>? nextBootstrapStarted;
  final pendingBootstraps = <Completer<Json>>[];
  final readerScales = <int>[];

  Json snapshot() => {
    ...asMap(
      jsonDecode(File('test/fixtures/bootstrap.json').readAsStringSync()),
    ),
    'user': owner == null
        ? null
        : {'id': owner, 'email': '$owner@example.test'},
    'readerFontScale': fontScale,
  };

  @override
  Future<Json> loadBootstrap() async {
    bootstrapCalls++;
    nextBootstrapStarted?.complete();
    nextBootstrapStarted = null;
    if (bootstrapOffline) throw const ApiException('Test: offline');
    final data = pendingBootstraps.isEmpty
        ? snapshot()
        : await pendingBootstraps.removeAt(0).future;
    // Match the real client's assignment, including delayed stale responses.
    bootstrap = data;
    return data;
  }

  @override
  Future<void> clearSession() async {
    cleared++;
    owner = null;
    await super.clearSession();
  }

  @override
  Future<Json> page(String path) async {
    if (path.startsWith('/login')) {
      return {
        'pending': {'email': 'B@example.test'},
        'redirectTo': '/Joh3,16',
      };
    }
    if (path.startsWith('/search')) return {'query': '', 'results': {}};
    final data = asMap(
      jsonDecode(File('test/fixtures/reader.json').readAsStringSync()),
    );
    data['user'] = snapshot()['user'];
    data['readerFontScale'] = fontScale;
    readerScales.add(fontScale);
    for (final column in asMaps(data['columns'])) {
      final chapter = asMap(column['initialChapter']);
      chapter['navigation'] = {'previous': null, 'next': null};
      for (final row in asMaps(asMap(chapter['chapter'])['rows'])) {
        for (final cell in asMaps(row['cells'])) {
          cell['segments'] = [
            owner == null ? 'Öffentlicher Text' : 'Privater Text $owner',
          ];
        }
      }
    }
    return data;
  }

  @override
  Future<dynamic> get(String path) async => {'workspaces': []};

  @override
  Future<ApiResult> action(String path, String action, Json fields) async {
    if (path == '/logout') {
      return ApiResult(type: 'redirect', status: 303, location: '/Joh1');
    }
    if (path == '/login' && action == 'code') {
      owner = 'B';
      return ApiResult(type: 'redirect', status: 303, location: '/Joh3,16');
    }
    return ApiResult(type: 'success', status: 200, data: {});
  }

  @override
  Future<dynamic> send(String method, String path, {dynamic data}) async => {
    'saved': true,
  };
}

Finder _privateText(String owner) => find.textContaining(
  'Privater Text $owner',
  findRichText: true,
  skipOffstage: false,
);

Future<AppScope> _start(WidgetTester tester, _SessionApi api) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(412, 915);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(api.dispose);
  await tester.pumpWidget(AkribosApp(api: api, enableLinks: false));
  await tester.pumpAndSettle();
  return AppScope.of(tester.element(find.byType(Scaffold).first));
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  testWidgets(
    'successful logout clears private retained readers even when bootstrap is offline',
    (tester) async {
      final api = _SessionApi();
      final scope = await _start(tester, api);
      expect(_privateText('A'), findsWidgets);
      await scope.open('/logout');
      await tester.pumpAndSettle();
      expect(
        _privateText('A'),
        findsWidgets,
      ); // Retained offstage until auth changes.
      api.bootstrapOffline = true;
      await tester.tap(find.text('Auf diesem Gerät abmelden'));
      await tester.pumpAndSettle();
      expect(api.cleared, 1);
      expect(api.bootstrap['user'], isNull);
      expect(_privateText('A'), findsNothing);
      expect(
        find.textContaining('Öffentlicher Text', findRichText: true),
        findsWidgets,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'login waits for a fresh bootstrap and keeps its form alive until redirect',
    (tester) async {
      final api = _SessionApi(owner: null);
      final scope = await _start(tester, api);
      await scope.open('/login');
      await tester.pumpAndSettle();
      final oldData = api.snapshot();
      final oldRequest = Completer<Json>(), freshRequest = Completer<Json>();
      api.pendingBootstraps.addAll([oldRequest, freshRequest]);
      final oldRefresh = scope.refreshSession();
      await tester.pump();
      final freshStarted = Completer<void>();
      api.nextBootstrapStarted = freshStarted;
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Sechsstelliger Code'),
        '123456',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Anmelden'));
      await tester.pump();
      expect(api.owner, 'B');
      oldRequest.complete(oldData);
      await oldRefresh;
      await tester.pump();
      // Authentication invalidates the prior offline identity before starting
      // the fresh bootstrap. That storage work is asynchronous, so a single
      // widget pump is not a reliable signal that the request has started.
      for (var i = 0; i < 100 && !freshStarted.isCompleted; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(freshStarted.isCompleted, isTrue);
      expect(api.bootstrapCalls, 3);
      expect(
        api.bootstrap['user'],
        isNull,
      ); // Old anonymous response was discarded.
      expect(find.text('Willkommen bei Akribos'), findsOneWidget);
      freshRequest.complete(api.snapshot());
      await tester.pumpAndSettle();
      expect(asMap(api.bootstrap['user'])['id'], 'B');
      expect(find.text('Willkommen bei Akribos'), findsNothing);
      expect(_privateText('B'), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('only changed reading preferences reload the retained reader', (
    tester,
  ) async {
    final api = _SessionApi();
    final scope = await _start(tester, api);
    await scope.open('/menu');
    await tester.pumpAndSettle();
    final initialLoads = api.readerScales.length;
    api.fontScale = 150;
    await scope.refreshSession();
    await tester.pumpAndSettle();
    expect(api.readerScales.length, initialLoads + 1);
    expect(api.readerScales.last, 150);
    await scope.refreshSession();
    await tester.pumpAndSettle();
    expect(api.readerScales.length, initialLoads + 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'session expiry clears retained private content and open private dialogs',
    (tester) async {
      final api = _SessionApi();
      final scope = await _start(tester, api);
      final dialog = showDialog<void>(
        context: tester.element(find.byType(Scaffold).first),
        builder: (_) => const AlertDialog(content: Text('Privater Dialog A')),
      );
      await tester.pumpAndSettle();
      api.owner = null;
      await scope.refreshSession();
      await tester.pumpAndSettle();
      await dialog;
      expect(_privateText('A'), findsNothing);
      expect(find.text('Privater Dialog A'), findsNothing);
      expect(api.bootstrap['user'], isNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
