import 'dart:async';
import 'dart:convert';

import 'package:akribos_app/core/api_client.dart';
import 'package:akribos_app/features/reader/reader_controller.dart';
import 'package:akribos_app/features/reader/reader_screen.dart';
import 'package:akribos_app/features/reader/reader_state.dart';
import 'package:akribos_app/features/reader/verse_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'native_reader_test.dart' show ReaderApi, app, readerFixture;

class DelayedReaderApi extends ReaderApi {
  DelayedReaderApi(super.data);
  Completer<void>? activation;
  bool reject = false;
  final gets = <String>[];

  @override
  Future<dynamic> send(String method, String path, {dynamic data}) async {
    final response = asMap(await super.send(method, path, data: data));
    if (method == 'PUT') {
      final state = asString(asMap(asMap(data)['snapshot'])['readerState']);
      final parameters = Uri.parse('?$state').queryParametersAll;
      final tiles = asMaps(asMap(this.data['workspace'])['tiles']);
      for (final value in parameters['tab'] ?? <String>[]) {
        final parts = value.split(':');
        final coordinate = parts[0].split('.').map(int.parse).toList();
        final reference = RegExp(r'^Joh(\d+)(?:,(\d+))?').firstMatch(parts[3])!;
        asMaps(tiles[coordinate[0] - 1]['tabs'])[coordinate[1] -
            1]['reference'] = {
          'book': 43,
          'chapter': int.parse(reference[1]!),
          if (reference[2] != null) 'verse': int.parse(reference[2]!),
        };
      }
      this.data['activeSavedWorkspaceContentVersion'] =
          asInt(this.data['activeSavedWorkspaceContentVersion']) + 1;
      response['activeSavedWorkspaceContentVersion'] =
          this.data['activeSavedWorkspaceContentVersion'];
    }
    return response;
  }

  @override
  Future<dynamic> get(String path) async {
    gets.add(path);
    return super.get(path);
  }

  @override
  Future<ApiResult> action(String path, String action, Json fields) async {
    if (action != 'activateTab') return super.action(path, action, fields);
    actions.add({'path': path, 'action': action, 'fields': fields});
    await activation?.future;
    if (reject) {
      return const ApiResult(
        type: 'failure',
        status: 409,
        data: {'error': 'conflict'},
      );
    }
    final workspace = asMap(data['workspace']);
    activateReaderTab(
      workspace,
      asString(fields['tileId']),
      asString(fields['tabId']),
    );
    final state = encodeReaderState(
      workspace,
      asMap(data['searchQueries']),
      '',
    );
    data['readerState'] = state;
    data['activeSavedWorkspaceContentVersion'] =
        asInt(data['activeSavedWorkspaceContentVersion']) + 1;
    return ApiResult(
      type: 'success',
      status: 200,
      data: {
        'readerState': state,
        'path': Uri.parse(readerPath(workspace, state)).path,
        'activeSavedWorkspaceId': 'saved',
        'activeSavedWorkspaceVersion': 4,
        'activeSavedWorkspaceContentVersion':
            data['activeSavedWorkspaceContentVersion'],
      },
    );
  }
}

Json longChapter() {
  final data = asMap(jsonDecode(jsonEncode(readerFixture(tiles: 2))));
  for (final column in asMaps(data['columns'])) {
    final chapter = asMap(column['initialChapter']);
    final rows = asMaps(asMap(chapter['chapter'])['rows']);
    asMap(chapter['chapter'])['rows'] = List.generate(300, (index) {
      final row = asMap(jsonDecode(jsonEncode(rows[index % rows.length])));
      row['verse'] = index + 1;
      asMap((row['cells'] as List).first)['verse'] = index + 1;
      return row;
    });
  }
  return data;
}

void main() {
  testWidgets(
    'optional phone split shows two existing panes without changing their saved layout',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = DelayedReaderApi(readerFixture(tiles: 2));
      final controller = ReaderController();
      await tester.pumpWidget(
        app(api, ReaderScreen(path: '/Joh1', controller: controller)),
      );
      await tester.pumpAndSettle();
      unawaited(controller.showTabs());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Geteilter Bildschirm'));
      await tester.pumpAndSettle();
      expect(find.byType(CustomScrollView), findsNWidgets(2));
      expect(api.actions, isEmpty);
      expect(asMap(api.data['workspace'])['layout'], 'columns-2');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'scroll resume then filter save uses a frozen snapshot and the new version',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = DelayedReaderApi(readerFixture());
      await tester.pumpWidget(app(api, const ReaderScreen(path: '/Joh1')));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -440));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.byTooltip('In diesem Werk suchen'));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.enterText(find.byType(TextField), 'Hoffnung');
      await tester.tap(find.text('Übernehmen'));
      await tester.pumpAndSettle();
      final writes = api.requests
          .where((request) => request['method'] == 'PUT')
          .toList();
      expect(writes, hasLength(2));
      final resume = asMap(writes[0]['data']),
          filters = asMap(writes[1]['data']);
      expect(resume['resume'], isTrue);
      expect(filters['resume'], isNull);
      expect(filters['workspaceContentVersion'], 13);
      expect(
        asMap(resume['snapshot'])['readerState'],
        asMap(filters['snapshot'])['readerState'],
      );
      expect(
        asString(asMap(filters['snapshot'])['readerState']),
        contains('search=1.1:Hoffnung'),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'rapid tab changes are serialized with returned content versions',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = DelayedReaderApi(readerFixture(tiles: 2));
      final controller = ReaderController();
      await tester.pumpWidget(
        app(api, ReaderScreen(path: '/Joh1', controller: controller)),
      );
      await tester.pumpAndSettle();
      api.activation = Completer<void>();
      await tester.drag(find.byType(PageView), const Offset(-350, 0));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(PageView), const Offset(350, 0));
      await tester.pumpAndSettle();
      expect(api.actions, hasLength(1));
      expect(find.text('Bibel 0 · Joh1'), findsOneWidget);
      api.activation!.complete();
      await tester.pumpAndSettle();
      expect(api.actions, hasLength(2));
      final paths = api.actions
          .map((action) => Uri.parse(asString(action['path'])).queryParameters)
          .toList();
      expect(paths[0]['workspaceContentVersion'], '12');
      expect(paths[1]['workspaceContentVersion'], '13');
      expect(await controller.flush(), isTrue);
      expect(api.pages, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    '300 verse chapters build only viewport rows and retain scroll controllers across tab swipes',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = DelayedReaderApi(longChapter());
      final controller = ReaderController();
      await tester.pumpWidget(
        app(api, ReaderScreen(path: '/Joh1', controller: controller)),
      );
      await tester.pumpAndSettle();
      expect(find.byType(VerseText).evaluate().length, lessThan(20));
      expect(controller.tabCount, 2);
      final scroll = tester
          .widget<CustomScrollView>(find.byType(CustomScrollView))
          .controller!;
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -460));
      await tester.pumpAndSettle();
      final offset = scroll.offset;
      expect(offset, greaterThan(100));
      await tester.drag(find.byType(PageView), const Offset(-350, 0));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(PageView), const Offset(350, 0));
      await tester.pumpAndSettle();
      final restored = tester
          .widget<CustomScrollView>(find.byType(CustomScrollView))
          .controller!;
      expect(identical(restored, scroll), isTrue);
      expect(restored.offset, closeTo(offset, 1));
      expect(api.pages, hasLength(1));
      expect(api.gets, isEmpty);
      expect(
        api.requests
            .where((request) => request['method'] == 'PUT')
            .every((request) => asMap(request['data'])['resume'] == true),
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'tab preview is immediate while activation is pending and no full page is requested',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = DelayedReaderApi(readerFixture(tiles: 2));
      final controller = ReaderController();
      await tester.pumpWidget(
        app(api, ReaderScreen(path: '/Joh1', controller: controller)),
      );
      await tester.pumpAndSettle();
      api.activation = Completer<void>();
      await tester.drag(find.byType(PageView), const Offset(-350, 0));
      await tester.pumpAndSettle();
      expect(find.text('Bibel 1 · Joh1'), findsOneWidget);
      expect(api.actions, hasLength(1));
      expect(api.pages, hasLength(1));
      var flushed = false;
      final flush = controller.flush().then((value) => flushed = value);
      await tester.pump();
      expect(flushed, isFalse);
      api.activation!.complete();
      await tester.pumpAndSettle();
      await flush;
      expect(flushed, isTrue);
      expect(api.pages, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'rejected activation restores the prior tab and blocks navigation until explicit retry',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = DelayedReaderApi(readerFixture(tiles: 2))..reject = true;
      final controller = ReaderController();
      await tester.pumpWidget(
        app(api, ReaderScreen(path: '/Joh1', controller: controller)),
      );
      await tester.pumpAndSettle();
      await tester.drag(find.byType(PageView), const Offset(-350, 0));
      await tester.pumpAndSettle();
      expect(find.text('Bibel 0 · Joh1'), findsOneWidget);
      expect(
        find.textContaining('Tabwechsel nicht gespeichert'),
        findsOneWidget,
      );
      expect(await controller.flush(), isFalse);
      expect(api.actions, hasLength(1));
      api.reject = false;
      await tester.tap(find.text('Erneut speichern'));
      await tester.pumpAndSettle();
      expect(await controller.flush(), isTrue);
      expect(api.actions, hasLength(2));
      expect(tester.takeException(), isNull);
    },
  );
}
