import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:akribos_app/core/api_client.dart';
import 'package:akribos_app/features/reader/reader_companion.dart';
import 'package:akribos_app/features/reader/reader_controller.dart';
import 'package:akribos_app/features/reader/reader_screen.dart';
import 'package:akribos_app/features/reader/reader_state.dart';
import 'package:akribos_app/features/reader/reader_tab_grid.dart';
import 'package:akribos_app/features/reader/verse_text.dart';
import 'package:akribos_app/theme/akribos_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'native_reader_test.dart' show ReaderApi, app, readerFixture;

class CommentaryApi extends ReaderApi {
  CommentaryApi() : super(readerFixture(tiles: 2)) {
    for (final column in asMaps(data['columns'])) {
      for (final row in asMaps(
        asMap(asMap(column['initialChapter'])['chapter'])['rows'],
      )) {
        final cell = asMap((row['cells'] as List).first);
        cell['segments'] = [
          ...cell['segments'] as List,
          ' Der Weg führt durch helle und dunkle Stunden. '
              'Geduld und Zuversicht begleiten die Menschen auf ihrer Reise.',
        ];
      }
    }
    data['readerResources'] = [
      ...asMaps(data['readerResources']),
      {
        'id': 'COMMENTARY',
        'kind': 'commentary',
        'name': 'Studienkommentar',
        'tabTitle': 'Kommentar',
      },
    ];
    bootstrap = asMap(jsonDecode(jsonEncode(data)));
  }

  @override
  Future<dynamic> get(String path) async {
    reads.add(path);
    final uri = Uri.parse(path);
    final chapter = int.parse(uri.pathSegments.last);
    return {
      'reference': {'book': 43, 'chapter': chapter},
      'fullTitle': 'Johannes $chapter',
      'chapter': {'rows': []},
      'referenceResources': {
        'commentaries': [
          for (var verse = 1; verse <= 30; verse++)
            {
              'id': 'comment-$chapter-$verse',
              'verseStart': verse,
              'bodyHtml':
                  '<p>Kommentar zu Vers $verse: Eine Erläuterung zum Bibeltext.</p>',
            },
        ],
      },
      'navigation': {},
    };
  }
}

class FailingFollowApi extends CommentaryApi {
  bool fail = true;
  @override
  Future<dynamic> get(String path) {
    if (fail &&
        path.contains('/43/2?') &&
        path.contains('resource=COMMENTARY')) {
      reads.add(path);
      return Future.error(const ApiException('Kommentarzugriff widerrufen'));
    }
    return super.get(path);
  }
}

void main() {
  testWidgets(
    'failed commentary follow surfaces visible retry at the current passage',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = FailingFollowApi();
      final controller = ReaderController();
      addTearDown(controller.dispose);
      addTearDown(api.dispose);
      await tester.pumpWidget(
        app(api, ReaderScreen(path: '/', controller: controller)),
      );
      await tester.pumpAndSettle();
      final enable = controller.setCompanion(
        const ReaderCompanion(enabled: true, resourceId: 'COMMENTARY'),
      );
      await tester.pumpAndSettle();
      expect(await enable, isTrue);
      final companion = find.byKey(const ValueKey('reader-companion'));
      expect(
        find.descendant(
          of: companion,
          matching: find.textContaining(
            'Kommentar zu Vers',
            findRichText: true,
          ),
        ),
        findsWidgets,
      );
      await tester.tap(find.widgetWithText(TextButton, 'Bibel 0 · Joh1').first);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OutlinedButton, '2'));
      await tester.pumpAndSettle();
      expect(controller.reference['chapter'], 2);
      expect(
        find.descendant(
          of: companion,
          matching: find.textContaining('Kommentarzugriff widerrufen'),
        ),
        findsWidgets,
      );
      expect(
        find.descendant(
          of: companion,
          matching: find.textContaining(
            'Kommentar zu Vers',
            findRichText: true,
          ),
        ),
        findsNothing,
      );
      api.fail = false;
      await tester.tap(
        find.descendant(
          of: companion,
          matching: find.widgetWithText(
            TextButton,
            'Erneut laden: Kommentarzugriff widerrufen',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        api.reads
            .where(
              (path) =>
                  path.contains('/43/2?') &&
                  path.contains('resource=COMMENTARY'),
            )
            .length,
        2,
      );
      expect(
        find.descendant(of: companion, matching: find.text('Johannes 2')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'reorder preserves active identity, groups, positions and lookup context',
    () {
      final data = readerFixture(tiles: 3);
      final workspace = asMap(data['workspace']);
      final tiles = asMaps(workspace['tiles']);
      workspace['focusedTileId'] = 'tile1';
      final tab = activeTab(tiles[1]);
      tab['reference'] = {'book': 43, 'chapter': 3, 'verse': 16};
      tab['linkSet'] = 'C';
      tab['lookup'] = 'G26';
      tab['studyContext'] = {
        'sourceResourceId': 'BIBLE0',
        'reference': {'book': 43, 'chapter': 1, 'verse': 2},
        'word': 'Liebe',
        'wordPosition': 4,
      };
      final before = jsonEncode(tab);
      expect(moveReaderTab(workspace, 'tab1', 3), isTrue);
      final onlyTile = asMaps(workspace['tiles']).single;
      expect(asMaps(onlyTile['tabs']).map((tab) => tab['id']), [
        'tab0',
        'tab2',
        'tab1',
      ]);
      expect(activeTab(onlyTile)['id'], 'tab1');
      expect(jsonEncode(activeTab(onlyTile)), before);
      final state = encodeReaderState(workspace, {
        'tab1': 'Liebe',
      }, 'notesTag=Hoffnung');
      final query = Uri.splitQueryString(state);
      expect(query['search'], '1.3:Liebe');
      expect(query['wordPosition'], '1.3:4');
      expect(query['active'], '1.3');
      expect(query['notesTag'], 'Hoffnung');
      expect(
        readerPath(workspace, state),
        startsWith('/Joh3,16?layout=single'),
      );
    },
  );

  test('two columns respond to window width and accessible text', () {
    expect(canShowReaderCompanion(1024, TextScaler.noScaling), isTrue);
    expect(canShowReaderCompanion(600, TextScaler.noScaling), isFalse);
    expect(canShowReaderCompanion(1024, const TextScaler.linear(2)), isFalse);
    expect(canShowReaderCompanion(1400, const TextScaler.linear(2)), isTrue);
  });

  testWidgets('long-press dragging changes visual order; plus remains last', (
    tester,
  ) async {
    final ids = ['first', 'second', 'third'];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, update) => ReaderTabGrid(
              ids: ids,
              cards: [
                for (final id in ids) Card(child: Center(child: Text(id))),
              ],
              addCard: const Card(child: Center(child: Text('Neuer Tab'))),
              columns: 2,
              cardHeight: 180,
              onMove: (id, destination) async {
                update(() {
                  ids.remove(id);
                  ids.insert(destination.clamp(0, ids.length), id);
                });
              },
            ),
          ),
        ),
      ),
    );
    final start = tester.getCenter(find.text('first'));
    final end = tester.getCenter(find.text('Neuer Tab'));
    final drag = await tester.startGesture(start);
    await tester.pump(const Duration(milliseconds: 600));
    await drag.moveTo(end);
    await tester.pump();
    await drag.up();
    await tester.pumpAndSettle();
    expect(ids, ['second', 'third', 'first']);
    expect(find.text('Neuer Tab'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('first')).dy,
      tester.getTopLeft(find.text('Neuer Tab')).dy,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'tablet companion swaps sides, persists, and survives split-screen',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = CommentaryApi();
      final controller = ReaderController();
      addTearDown(controller.dispose);
      const capturePath = String.fromEnvironment('TABLET_CAPTURE_PATH');
      if (capturePath.isNotEmpty) {
        WidgetsApp.debugAllowBannerOverride = false;
        addTearDown(() => WidgetsApp.debugAllowBannerOverride = true);
        await tester.runAsync(() async {
          final reading = FontLoader('AkribosText');
          reading.addFont(
            rootBundle.load('assets/fonts/akribos-text-regular.ttf'),
          );
          reading.addFont(
            rootBundle.load('assets/fonts/akribos-text-semibold.ttf'),
          );
          reading.addFont(
            rootBundle.load('assets/fonts/akribos-text-bold.ttf'),
          );
          await reading.load();
          final controls = FontLoader('Roboto')
            ..addFont(
              File(const String.fromEnvironment('CAPTURE_ROBOTO_TTF'))
                  .readAsBytes()
                  .then(ByteData.sublistView),
            );
          await controls.load();
          final icons = FontLoader('MaterialIcons')
            ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
          await icons.load();
        });
      }
      await tester.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('capture-tablet'),
          child: app(
            api,
            Theme(
              data: buildAkribosTheme(Brightness.light),
              child: ReaderScreen(path: '/', controller: controller),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final presentation = controller.setVersePerLine(false);
      await tester.pumpAndSettle();
      expect(await presentation, isTrue);
      await tester.drag(
        find.byType(CustomScrollView).first,
        const Offset(0, -300),
      );
      await tester.pumpAndSettle();
      await controller.flush();
      final scrolledVerse = asInt(controller.reference['verse']);
      expect(scrolledVerse, greaterThan(1));
      void expectPassageVisible() {
        final paragraph = tester.state<VerseTextState>(
          find.byType(VerseText).first,
        );
        final viewport = find
            .descendant(
              of: find.byType(PageView),
              matching: find.byType(CustomScrollView),
            )
            .first;
        final verseY = paragraph.paragraph!
            .localToGlobal(Offset(0, paragraph.passageTop(scrolledVerse - 1)))
            .dy;
        expect((verseY - tester.getTopLeft(viewport).dy).abs(), lessThan(4));
      }

      final enable = controller.setCompanion(
        const ReaderCompanion(enabled: true, resourceId: 'COMMENTARY'),
      );
      await tester.pumpAndSettle();
      expect(await enable, isTrue);
      expectPassageVisible();
      if (capturePath.isNotEmpty) {
        await tester.runAsync(() async {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const ValueKey('capture-tablet')),
          );
          final image = await boundary.toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(capturePath).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      expect(find.byKey(const ValueKey('reader-two-columns')), findsOneWidget);
      expect(find.text('Studienkommentar'), findsOneWidget);
      expect(
        api.reads.any((path) => path.contains('resource=COMMENTARY')),
        isTrue,
      );
      final primaryX = tester
          .getTopLeft(find.byKey(const ValueKey('reader-primary')))
          .dx;
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('reader-companion'))).dx,
        greaterThan(primaryX),
      );
      final switchSides = controller.setCompanion(
        controller.companion.copyWith(onLeft: true),
      );
      await tester.pumpAndSettle();
      expect(await switchSides, isTrue);
      expectPassageVisible();
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('reader-companion'))).dx,
        lessThan(
          tester.getTopLeft(find.byKey(const ValueKey('reader-primary'))).dx,
        ),
      );
      expect(
        (await api.localStore.read())?['companion'],
        controller.companion.toJson(),
      );
      final referenceBefore = Map.of(controller.reference);
      await tester.drag(
        find.byKey(const ValueKey('reader-companion')),
        const Offset(0, -240),
      );
      await tester.pumpAndSettle();
      expect(controller.reference, referenceBefore);
      tester.view.physicalSize = const Size(540, 850);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('reader-two-columns')), findsNothing);
      expect(controller.companion.enabled, isTrue);
      expectPassageVisible();
      tester.view.physicalSize = const Size(1100, 850);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('reader-two-columns')), findsOneWidget);
      expect(controller.reference, referenceBefore);
      expectPassageVisible();
      expect(api.actions, isEmpty);
      expect(api.requests, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('tab overview reorder keeps selected tab and persists the URL', (
    tester,
  ) async {
    final api = ReaderApi(readerFixture(tiles: 3));
    final controller = ReaderController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      app(api, ReaderScreen(path: '/', controller: controller)),
    );
    await tester.pumpAndSettle();
    unawaited(controller.showTabs());
    await tester.pumpAndSettle();
    final first = find.byKey(const ValueKey('reader-tab-drop:tab0'));
    final target = find.byKey(const ValueKey('reader-tab-drop:tab2'));
    final gesture = await tester.startGesture(tester.getCenter(first));
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveTo(tester.getCenter(target));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(controller.activeResource?.id, 'BIBLE0');
    final saved = Uri.parse(asString((await api.localStore.read())?['path']));
    expect(saved.queryParametersAll['tab']!.map((tab) => tab.split(':')[1]), [
      'BIBLE1',
      'BIBLE2',
      'BIBLE0',
    ]);
    expect(saved.queryParameters['active'], '1.3');
    expect(api.actions, isEmpty);
    expect(api.requests, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
