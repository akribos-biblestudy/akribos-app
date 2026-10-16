import 'dart:io';
import 'dart:ui' as ui;

import 'package:akribos_app/core/json.dart';
import 'package:akribos_app/features/reader/reader_verse_menu.dart';
import 'package:akribos_app/features/reader/reader_screen.dart';
import 'package:akribos_app/features/reader/verse_text.dart';
import 'package:akribos_app/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'native_reader_test.dart' show ReaderApi, app, readerFixture;

const _actions = ['marks', 'lists', 'note', 'share'];
final _styles = <Json>[
  {'id': 'yellow', 'name': 'Verheißung', 'color': '#facc15'},
  {'id': 'blue', 'name': 'Frage', 'color': '#38bdf8'},
];

Future<void> _open(
  WidgetTester tester, {
  Size size = const Size(390, 844),
  double scale = 1,
  bool signedIn = true,
  int catalogueSize = 2,
  ValueChanged<String?>? onResult,
  GlobalKey? capture,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  await tester.pumpWidget(
    RepaintBoundary(
      key: capture,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: appTheme(Brightness.light),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            padding: const EdgeInsets.only(top: 24, bottom: 24),
          ),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () async {
                  final result = await showReaderVerseMenu(
                    context,
                    reference: 'Johannes 3,16',
                    text:
                        'Denn so sehr hat Gott die Welt geliebt, dass er seinen '
                        'eingeborenen Sohn gab, damit jeder, der an ihn glaubt, '
                        'nicht verloren geht, sondern ewiges Leben hat.',
                    signedIn: signedIn,
                    styles: [
                      ..._styles,
                      for (var i = 2; i < catalogueSize; i++)
                        {
                          'id': 'style$i',
                          'name': 'Farbe $i',
                          'color': '#aabbcc',
                        },
                    ],
                    highlights: [
                      {'name': 'Verheißung'},
                    ],
                    lists: [
                      for (var i = 0; i < catalogueSize; i++)
                        {'id': 'list$i', 'title': 'Sammlung $i'},
                    ],
                    selectedLists: {'list0'},
                  );
                  onResult?.call(result);
                },
                child: const Text('Vers öffnen'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Vers öffnen'));
  await tester.pumpAndSettle();
}

void _expectSingleLineLabel(WidgetTester tester, Finder control) {
  final label = find.descendant(of: control, matching: find.byType(Text));
  final paragraph = tester.renderObject<RenderParagraph>(label);
  final text = paragraph.text.toPlainText();
  final boxes = paragraph.getBoxesForSelection(
    TextSelection(baseOffset: 0, extentOffset: text.length),
  );
  expect(boxes, hasLength(1));
  expect(boxes.single.left, greaterThanOrEqualTo(-.01));
  expect(boxes.single.right, lessThanOrEqualTo(paragraph.size.width + .01));
  expect(paragraph.didExceedMaxLines, isFalse);
  final icon = find.descendant(of: control, matching: find.byType(Icon));
  expect(tester.getCenter(icon).dy, closeTo(tester.getCenter(label).dy, .01));
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final sdk =
        Platform.environment['FLUTTER_ROOT'] ??
        File(Platform.resolvedExecutable)
            .parent
            .parent
            .parent
            .parent
            .parent
            .parent
            .path;
    final controlsFont = [
      File('$sdk/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf'),
      File('$sdk/engine/src/flutter/txt/third_party/fonts/Roboto-Regular.ttf'),
    ].firstWhere((file) => file.existsSync());
    await (FontLoader(
      'Roboto',
    )..addFont(controlsFont.readAsBytes().then(ByteData.sublistView))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    for (final weight in ['regular', 'semibold', 'bold']) {
      await (FontLoader('AkribosText')
            ..addFont(rootBundle.load('assets/fonts/akribos-text-$weight.ttf')))
          .load();
    }
  });

  for (final size in const [
    Size(320, 568),
    Size(390, 844),
    Size(568, 320),
    Size(844, 390),
    Size(768, 1024),
    Size(1024, 768),
  ]) {
    testWidgets('all main actions fit $size without scrolling', (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final capture = GlobalKey();
      await _open(tester, size: size, catalogueSize: 120, capture: capture);
      final viewport = Offset.zero & size;
      final firstWidth = tester
          .getSize(find.byKey(const ValueKey('verse-action-marks')))
          .width;
      for (final action in _actions) {
        final control = find.byKey(ValueKey('verse-action-$action'));
        expect(control.hitTestable(), findsOneWidget);
        final rect = tester.getRect(control);
        expect(viewport.contains(rect.topLeft), isTrue, reason: action);
        expect(viewport.contains(rect.bottomRight), isTrue, reason: action);
        expect(rect.width, greaterThanOrEqualTo(48));
        expect(rect.width, closeTo(firstWidth, .01));
        expect(rect.height, greaterThanOrEqualTo(48));
        _expectSingleLineLabel(tester, control);
      }
      final scrollable = find.descendant(
        of: find.byKey(const ValueKey('verse-menu-overview-scroll')),
        matching: find.byType(Scrollable),
      );
      expect(
        tester.state<ScrollableState>(scrollable).position.maxScrollExtent,
        0,
      );
      expect(find.text('Farbe 119'), findsNothing);
      expect(find.text('Sammlung 119'), findsNothing);
      expect(tester.takeException(), isNull);
      if (const bool.fromEnvironment('CAPTURE_VERSE_MENU')) {
        await tester.runAsync(() async {
          final image =
              await (capture.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
            '/tmp/akribos-verse-menu-${size.width.toInt()}x${size.height.toInt()}.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
    });
  }

  testWidgets('removed word-marking and copy entries stay absent', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _open(tester);
    expect(find.byKey(const ValueKey('verse-action-partial')), findsNothing);
    expect(find.text('Wörter markieren'), findsNothing);
    expect(find.byKey(const ValueKey('verse-action-copy')), findsNothing);
    expect(find.text('Kopieren'), findsNothing);
    expect(find.byKey(const ValueKey('verse-action-marks')), findsOneWidget);
  });

  testWidgets(
    'large accessibility text retains reachable controls without overflow',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await _open(tester, size: const Size(320, 568), scale: 2.5);
      for (final action in _actions) {
        final control = find.byKey(ValueKey('verse-action-$action'));
        await tester.ensureVisible(control);
        await tester.pumpAndSettle();
        expect(control.hitTestable(), findsOneWidget);
        expect(tester.getSize(control).height, greaterThanOrEqualTo(48));
        _expectSingleLineLabel(tester, control);
        expect(tester.takeException(), isNull);
      }
    },
  );

  for (final action in ['note', 'share']) {
    testWidgets('main action $action returns its unchanged command', (
      tester,
    ) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      String? result;
      await _open(tester, onResult: (value) => result = value);
      await tester.tap(find.byKey(ValueKey('verse-action-$action')));
      await tester.pumpAndSettle();
      expect(result, action);
      expect(find.byType(ReaderVerseMenu), findsNothing);
    });
  }

  for (final selection in [
    ('Verheißung', 'highlight:yellow'),
    ('Markierung „Verheißung“ entfernen', 'removeRange:0'),
    ('Versmarkierung entfernen', 'removeHighlight'),
  ]) {
    testWidgets('mark choice returns ${selection.$2}', (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      String? result;
      await _open(tester, onResult: (value) => result = value);
      await tester.tap(find.byKey(const ValueKey('verse-action-marks')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(selection.$1));
      await tester.pumpAndSettle();
      expect(result, selection.$2);
      expect(tester.takeException(), isNull);
    });
  }

  for (final selection in [
    ('Neue Sammlung mit diesem Vers', 'newList'),
    ('Sammlung 0', 'list:list0'),
    ('Sammlung 1', 'list:list1'),
  ]) {
    testWidgets('collection choice returns ${selection.$2}', (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      String? result;
      await _open(tester, onResult: (value) => result = value);
      await tester.tap(find.byKey(const ValueKey('verse-action-lists')));
      await tester.pumpAndSettle();
      expect(
        find.text('Vers enthalten · Tippen zum Entfernen'),
        findsOneWidget,
      );
      await tester.tap(find.text(selection.$1));
      await tester.pumpAndSettle();
      expect(result, selection.$2);
    });
  }

  testWidgets(
    'large catalogues stay reachable and Back returns without a command',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var commands = 0;
      await _open(tester, catalogueSize: 120, onResult: (_) => commands++);
      await tester.tap(find.byKey(const ValueKey('verse-action-lists')));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Sammlung 119'),
        500,
        scrollable: find.descendant(
          of: find.byKey(const ValueKey('verse-menu-lists')),
          matching: find.byType(Scrollable),
        ),
        maxScrolls: 30,
      );
      await tester.pumpAndSettle();
      expect(find.text('Sammlung 119').hitTestable(), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('verse-action-lists')), findsOneWidget);
      expect(commands, 0);
      await tester.tap(find.byTooltip('Versmenü schließen'));
      await tester.pumpAndSettle();
      expect(commands, 1);
    },
  );

  testWidgets('guests retain share/note and the login boundary', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    String? result;
    await _open(tester, signedIn: false, onResult: (value) => result = value);
    for (final action in ['marks', 'partial', 'lists']) {
      expect(find.byKey(ValueKey('verse-action-$action')), findsNothing);
    }
    for (final action in ['note', 'share']) {
      expect(
        find.byKey(ValueKey('verse-action-$action')).hitTestable(),
        findsOneWidget,
      );
    }
    await tester.tap(find.byTooltip('Zum Markieren und Sammeln anmelden'));
    await tester.pumpAndSettle();
    expect(result, 'login');
  });

  testWidgets('reader menu keeps source-scoped removal fields intact', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    final data = readerFixture();
    final chapter = asMap(asMaps(data['columns']).first['initialChapter']);
    chapter['highlights'] = [
      {
        'verse': 1,
        'endVerse': 2,
        'resourceId': 'BIBLE0',
        'startWord': 1,
        'endWord': 3,
        'name': 'Teilmarkierung',
      },
      {'verse': 1, 'resourceId': 'OTHER', 'name': 'Andere Übersetzung'},
    ];
    asMaps(data['columns']).first['initialChapter'] = chapter;
    final api = ReaderApi(data);
    await tester.pumpWidget(app(api, const ReaderScreen(path: '/Joh1')));
    await tester.pumpAndSettle();
    tester.widget<VerseText>(find.byType(VerseText).first).onVerseNumber!();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('verse-action-marks')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Andere Übersetzung'), findsNothing);
    await tester.tap(find.text('Markierung „Teilmarkierung“ entfernen'));
    await tester.pumpAndSettle();
    final action = api.actions.single;
    expect(action['action'], 'removeHighlight');
    expect(asMap(action['fields']), containsPair('reference', 'Joh1,1'));
    expect(asMap(action['fields']), containsPair('endVerse', 2));
    expect(asMap(action['fields']), containsPair('resourceId', 'BIBLE0'));
    expect(asMap(action['fields']), containsPair('startWord', 1));
    expect(asMap(action['fields']), containsPair('endWord', 3));
    expect(tester.takeException(), isNull);
  });
}
