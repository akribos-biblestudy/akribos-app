import 'dart:async';
import 'dart:convert';

import 'package:akribos_app/core/api_client.dart';
import 'package:akribos_app/features/reader/reader_controller.dart';
import 'package:akribos_app/features/reader/reader_screen.dart';
import 'package:akribos_app/features/reader/reader_local_store.dart';
import 'package:akribos_app/features/search/search_screen.dart';
import 'package:akribos_app/features/reader/reader_state.dart';
import 'package:akribos_app/features/reader/reader_tab_card.dart';
import 'package:akribos_app/features/reader/verse_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'native_reader_test.dart' show ReaderApi, app, readerFixture;

class DelayedReaderApi extends ReaderApi {
  DelayedReaderApi(super.data);
  final gets = <String>[];
  final chapterResponses = <String, Json>{};
  @override
  Future<dynamic> get(String path) async {
    gets.add(path);
    final resource = Uri.parse(path).queryParameters['resource'];
    if (chapterResponses.containsKey(resource)) {
      return jsonDecode(jsonEncode(chapterResponses[resource]));
    }
    return super.get(path);
  }
}

class ControlledLocalStore extends ReaderLocalStore {
  ControlledLocalStore(ReaderApi api)
    : super(origin: api.origin, userId: 'reader');
  Completer<void>? paused;
  bool reject = false;
  final writes = <String>[];
  @override
  Future<void> write(String path, {Json layoutSizes = const {}}) async {
    writes.add(path);
    await paused?.future;
    if (reject) {
      throw const ApiException(
        'Lokaler Speicher vorübergehend nicht verfügbar',
      );
    }
    await super.write(path, layoutSizes: layoutSizes);
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
    'local flat tabs retain original coordinates across scrolling and phone-to-tablet resize',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fixture = asMap(jsonDecode(jsonEncode(readerFixture(tiles: 4))));
      final workspace = asMap(fixture['workspace']);
      final tiles = asMaps(workspace['tiles']);
      // A browser grid with an inactive second tab and a deliberately empty
      // second tile. Native ordering must preserve the gap in URL coordinates.
      final inactive = asMaps(tiles[1]['tabs']).single;
      inactive['linkSet'] = null;
      (tiles[0]['tabs'] as List).add(inactive);
      tiles[1]['tabs'] = <Json>[];
      tiles[1]['activeTabId'] = null;
      asMaps(tiles[2]['tabs']).single['linkSet'] = 'B';
      workspace['layout'] = 'grid-4';
      final sizes = <String, dynamic>{
        'grid-4': {
          'columns': [.31, .69],
          'rows': [.62, .38],
        },
        'columns-3': {
          'columns': [.2, .5, .3],
          'rows': [1.0],
        },
      };
      workspace['layoutSizes'] = jsonDecode(jsonEncode(sizes));
      fixture['readerState'] = encodeReaderState(workspace, {}, '');
      final initialColumns = asMaps(fixture['columns']);
      final inactiveChapter = asMap(initialColumns[1]['initialChapter']);
      fixture['columns'] = initialColumns
          .where((column) => column['tileId'] != 'tile1')
          .toList();
      final api = DelayedReaderApi(fixture);
      api.chapterResponses['BIBLE1'] = inactiveChapter;
      final controller = ReaderController();
      await tester.pumpWidget(
        app(api, ReaderScreen(path: '/Joh1', controller: controller)),
      );
      await tester.pumpAndSettle();

      void expectBrowserStructure() {
        final saved = asMap(api.data['workspace']);
        expect(saved['layout'], 'grid-4');
        expect(saved['layoutSizes'], sizes);
        expect(
          asMaps(saved['tiles'])
              .map(
                (tile) => [
                  tile['id'],
                  asMaps(tile['tabs'])
                      .map(
                        (tab) => [tab['id'], tab['resourceId'], tab['linkSet']],
                      )
                      .toList(),
                ],
              )
              .toList(),
          [
            [
              'tile0',
              [
                ['tab0', 'BIBLE0', 'A'],
                ['tab1', 'BIBLE1', null],
              ],
            ],
            ['tile1', <Object>[]],
            [
              'tile2',
              [
                ['tab2', 'BIBLE2', 'B'],
              ],
            ],
            [
              'tile3',
              [
                ['tab3', 'BIBLE3', 'A'],
              ],
            ],
          ],
        );
      }

      void expectOriginalCoordinates(String state) {
        final parameters = Uri.parse('?$state').queryParametersAll;
        expect(parameters['layout'], ['grid-4']);
        expect(
          (parameters['tab'] ?? <String>[])
              .map((tab) => tab.split(':').take(3).join(':'))
              .toList(),
          ['1.1:BIBLE0:A', '1.2:BIBLE1:-', '3.1:BIBLE2:B', '4.1:BIBLE3:A'],
        );
      }

      Future<void> swipe(double distance, String title) async {
        await tester.drag(find.byType(PageView), Offset(distance, 0));
        await tester.pumpAndSettle();
        expect(controller.activeTitle, title);
        expect(find.byType(PageView), findsOneWidget);
        expect(find.byType(CustomScrollView), findsOneWidget);
        expectBrowserStructure();
      }

      expect(controller.tabCount, 4);
      expect(controller.activeTitle, 'Bibel 0');
      expectBrowserStructure();
      await swipe(-350, 'Bibel 1');
      expect(api.actions, isEmpty);
      final selected = Uri.parse(
        asString((await api.localStore.read())?['path']),
      );
      expect(selected.queryParametersAll['active'], contains('1.2'));
      expect(api.gets, contains('/api/reader/43/1?resource=BIBLE1'));
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -440));
      await tester.pumpAndSettle();
      expect(await controller.flush(), isTrue);
      final latest = (await api.localStore.read())!;
      expectOriginalCoordinates(Uri.parse(asString(latest['path'])).query);
      final savedTabs = Uri.parse(asString(latest['path']))
          .queryParametersAll['tab']!;
      expect(savedTabs[1], matches(RegExp(r'^1[.]2:BIBLE1:-:Joh1,[0-9]+$')));
      expect(int.parse(savedTabs[1].split(',').last), greaterThan(1));
      expect(savedTabs[0], '1.1:BIBLE0:A:Joh1');
      expect(savedTabs[2], '3.1:BIBLE2:B:Joh1');
      expect(savedTabs[3], '4.1:BIBLE3:A:Joh1');
      expect(latest['layoutSizes'], sizes);
      expect(api.requests, isEmpty);
      final scroll = tester
          .widget<CustomScrollView>(find.byType(CustomScrollView))
          .controller;
      final actionsBeforeResize = api.actions.length;
      tester.view.physicalSize = const Size(1280, 900);
      await tester.pumpAndSettle();
      expect(controller.activeTitle, 'Bibel 1');
      expect(find.byType(PageView), findsOneWidget);
      expect(find.byType(CustomScrollView), findsOneWidget);
      expect(
        tester
            .widget<CustomScrollView>(find.byType(CustomScrollView))
            .controller,
        same(scroll),
      );
      expect(api.actions.length, actionsBeforeResize);
      expectBrowserStructure();
      await swipe(-1100, 'Bibel 2');
      await swipe(-1100, 'Bibel 3');

      unawaited(controller.showTabs());
      await tester.pumpAndSettle();
      expect(find.byType(ReaderTabCard), findsNWidgets(4));
      for (final title in ['Bibel 0', 'Bibel 1', 'Bibel 2', 'Bibel 3']) {
        expect(find.text(title), findsOneWidget);
      }
      expect(find.text('Geteilter Bildschirm'), findsNothing);
      expect(find.byTooltip('Anordnung'), findsNothing);
      expect(
        tester
            .widgetList<ReaderTabCard>(find.byType(ReaderTabCard))
            .where((card) => card.selected)
            .map((card) => card.title),
        ['Bibel 3'],
      );
      await tester.tap(find.text('Bibel 0'));
      await tester.pumpAndSettle();
      expect(controller.activeTitle, 'Bibel 0');
      expect(await controller.flush(), isTrue);
      expect(api.actions, isEmpty);
      expect(api.requests, isEmpty);
      final finalSnapshot = (await api.localStore.read())!;
      expectOriginalCoordinates(
        Uri.parse(asString(finalSnapshot['path'])).query,
      );
      expect(finalSnapshot['layoutSizes'], sizes);
      expectBrowserStructure();
      expect(api.pages, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'scroll and search filters survive a reader restart exclusively in local storage',
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
      expect(find.byTooltip('In diesem Werk suchen'), findsNothing);
      await tester.tap(find.byTooltip('Tab-Einstellungen'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.text('In diesem Werk suchen'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.enterText(find.byType(TextField), 'Hoffnung');
      await tester.tap(find.text('Übernehmen'));
      await tester.pumpAndSettle();
      final snapshot = (await api.localStore.read())!;
      final parameters = Uri.parse(asString(snapshot['path'])).queryParameters;
      expect(parameters['search'], '1.1:Hoffnung');
      expect(parameters['tab'], matches(RegExp(r'Joh1,[0-9]+$')));
      expect(api.requests, isEmpty);
      expect(api.actions, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await tester.pumpWidget(app(api, const ReaderScreen(path: '/')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TabSearchPanel>(find.byType(TabSearchPanel)).query,
        'Hoffnung',
      );
      final restored = Uri.parse(
        asString((await api.localStore.read())?['path']),
      ).queryParameters;
      expect(restored['search'], parameters['search']);
      expect(restored['tab'], parameters['tab']);
      expect(api.requests, isEmpty);
      expect(api.actions, isEmpty);
      expect(
        api.pages.every(
          (path) =>
              Uri.parse(path).queryParameters['workspaceDetached'] == 'true',
        ),
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'rapid tab changes keep the latest local selection while storage is pending',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = DelayedReaderApi(readerFixture(tiles: 2));
      final store = ControlledLocalStore(api);
      final controller = ReaderController();
      await tester.pumpWidget(
        app(
          api,
          ReaderScreen(
            path: '/Joh1',
            controller: controller,
            localStore: store,
          ),
        ),
      );
      await tester.pumpAndSettle();
      store.paused = Completer<void>();
      await tester.drag(find.byType(PageView), const Offset(-350, 0));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(PageView), const Offset(350, 0));
      await tester.pumpAndSettle();
      expect(find.text('Bibel 0 · Joh1'), findsOneWidget);
      store.paused!.complete();
      await tester.pumpAndSettle();
      expect(await controller.flush(), isTrue);
      final snapshot = Uri.parse(asString((await store.read())?['path']));
      expect(snapshot.queryParameters['focus'], '1');
      expect(controller.activeTitle, 'Bibel 0');
      expect(api.actions, isEmpty);
      expect(api.requests, isEmpty);
      expect(api.pages, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a fresh Reader and API restore the locally selected tab without a named workspace request',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fixture = readerFixture(tiles: 2);
      final first = ReaderApi(fixture);
      await tester.pumpWidget(app(first, const ReaderScreen(path: '/Joh1')));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(PageView), const Offset(-350, 0));
      await tester.pumpAndSettle();
      expect(
        Uri.parse(asString((await first.localStore.read())?['path']))
            .queryParameters['focus'],
        '2',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      final restarted = ReaderApi(fixture, seedLocal: false);
      final controller = ReaderController();
      await tester.pumpWidget(
        app(restarted, ReaderScreen(path: '/', controller: controller)),
      );
      await tester.pumpAndSettle();
      expect(controller.activeTitle, 'Bibel 1');
      expect(controller.tabCount, 2);
      expect(find.text('Bibel 1 · Joh1'), findsOneWidget);
      final requested = Uri.parse(restarted.pages.single).queryParameters;
      expect(requested['focus'], '2');
      expect(requested['workspaceDetached'], 'true');
      expect(requested.keys, isNot(contains('workspaceId')));
      expect(restarted.requests, isEmpty);
      expect(restarted.actions, isEmpty);
      expect(
        restarted.reads.where((path) => path.contains('/workspaces')),
        isEmpty,
      );
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
      expect(api.requests, isEmpty);
      expect(api.actions, isEmpty);
      expect(
        Uri.parse(asString((await api.localStore.read())?['path']))
            .queryParameters['focus'],
        '1',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'tab preview is immediate while local persistence is pending and navigation waits',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = DelayedReaderApi(readerFixture(tiles: 2));
      final store = ControlledLocalStore(api);
      final controller = ReaderController();
      await tester.pumpWidget(
        app(
          api,
          ReaderScreen(
            path: '/Joh1',
            controller: controller,
            localStore: store,
          ),
        ),
      );
      await tester.pumpAndSettle();
      store.paused = Completer<void>();
      await tester.drag(find.byType(PageView), const Offset(-350, 0));
      await tester.pumpAndSettle();
      expect(find.text('Bibel 1 · Joh1'), findsOneWidget);
      expect(api.actions, isEmpty);
      expect(api.pages, hasLength(1));
      var flushed = false;
      final flush = controller.flush().then((value) => flushed = value);
      await tester.pump();
      expect(flushed, isFalse);
      store.paused!.complete();
      await tester.pumpAndSettle();
      await flush;
      expect(flushed, isTrue);
      expect(
        Uri.parse(asString((await store.read())?['path']))
            .queryParameters['focus'],
        '2',
      );
      expect(api.requests, isEmpty);
      expect(api.pages, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'failed local persistence blocks navigation until an explicit successful retry',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = DelayedReaderApi(readerFixture(tiles: 2));
      final store = ControlledLocalStore(api);
      final controller = ReaderController();
      await tester.pumpWidget(
        app(
          api,
          ReaderScreen(
            path: '/Joh1',
            controller: controller,
            localStore: store,
          ),
        ),
      );
      await tester.pumpAndSettle();
      store.reject = true;
      await tester.drag(find.byType(PageView), const Offset(-350, 0));
      await tester.pumpAndSettle();
      expect(find.text('Bibel 1 · Joh1'), findsOneWidget);
      expect(
        find.textContaining('auf diesem Gerät nicht gespeichert'),
        findsOneWidget,
      );
      expect(await controller.flush(), isFalse);
      expect(api.actions, isEmpty);
      store.reject = false;
      await tester.tap(find.text('Erneut speichern'));
      await tester.pumpAndSettle();
      expect(await controller.flush(), isTrue);
      expect(
        Uri.parse(asString((await store.read())?['path']))
            .queryParameters['focus'],
        '2',
      );
      expect(api.requests, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}
