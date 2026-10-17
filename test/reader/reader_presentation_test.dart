import 'dart:io';
import 'dart:ui' as ui;

import 'package:akribos_app/core/json.dart';
import 'package:akribos_app/core/app_scope.dart';
import 'package:akribos_app/main.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:akribos_app/features/reader/reader_screen.dart';
import 'package:akribos_app/features/reader/verse_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'native_reader_test.dart' show ReaderApi, readerFixture, app;

class _PresentationApi extends ReaderApi {
  _PresentationApi(super.data);
  @override
  Future<Json> loadBootstrap() async => bootstrap;
  @override
  Future<Json> page(String path) async => path == '/account'
      ? {...bootstrap, 'highlightStyles': []}
      : super.page(path);
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await (FontLoader('AkribosText')
          ..addFont(rootBundle.load('assets/fonts/akribos-text-regular.ttf')))
        .load();
    await (FontLoader('NotoSansHebrew')..addFont(
          rootBundle.load(
            'assets/fonts/noto-sans-hebrew-hebrew-400-normal.ttf',
          ),
        ))
        .load();
  });
  for (final direction in TextDirection.values) {
    testWidgets('marker joins spaces and wraps using actual $direction glyphs', (
      tester,
    ) async {
      final boundary = GlobalKey();
      final segments = direction == TextDirection.ltr
          ? <dynamic>[
              'Am ',
              {'kind': 'w', 'text': 'Anfang'},
              ' war das Wort und das Wort war bei Gott.',
            ]
          : <dynamic>[
              'בְּרֵאשִׁית ',
              {'kind': 'w', 'text': 'בָּרָא'},
              ' אֱלֹהִים אֵת הַשָּׁמַיִם וְאֵת הָאָרֶץ',
            ];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: RepaintBoundary(
                key: boundary,
                child: SizedBox(
                  width: 230,
                  child: VerseText(
                    segments: segments,
                    direction: direction,
                    selectable: false,
                    passages: [
                      VersePassage(
                        segments: segments,
                        highlights: const [
                          {'start': 0, 'end': 100, 'color': '#facc15'},
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final paint = tester.widget<CustomPaint>(
        find.descendant(
          of: find.byType(VerseText),
          matching: find.byWidgetPredicate(
            (w) => w is CustomPaint && w.painter is VerseMarkerPainter,
          ),
        ),
      );
      final marker = paint.painter! as VerseMarkerPainter;
      final rects = marker.rectangles(marker.ranges.single);
      expect(rects.length, greaterThan(1));
      final paragraph = marker.paragraph()!;
      expect(paragraph.textAlign, TextAlign.justify);
      for (final rect in rects.take(rects.length - 1)) {
        expect(rect.left, closeTo(0, 1));
        expect(rect.right, closeTo(paragraph.size.width, 1));
      }
      final text = paragraph.text.toPlainText();
      final gap = text.indexOf(' ');
      final whitespace = paragraph
          .getBoxesForSelection(
            TextSelection(baseOffset: gap, extentOffset: gap + 1),
          )
          .single
          .toRect();
      expect(rects.any((r) => r.contains(whitespace.center)), isTrue);
      // One uninterrupted band per line, regardless of separately tagged words.
      expect(
        rects.map((r) => r.center.dy.round()).toSet().length,
        rects.length,
      );
      expect(marker.ranges.single.end, text.length);
      if (const bool.fromEnvironment('CAPTURE_READER_UI')) {
        await tester.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage(pixelRatio: 3);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('/tmp/akribos-marker-${direction.name}.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'partial markers retain word bounds through notes and styled runs',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: VerseText(
              selectable: false,
              segments: [
                'Vor ',
                {
                  'kind': 'nd',
                  'children': [
                    {'kind': 'w', 'text': 'Herr'},
                  ],
                },
                ' ',
                {'kind': 'note', 'marker': 'a', 'text': 'Anmerkung'},
                {'kind': 'em', 'text': 'ist gut'},
                ' danach',
              ],
              highlights: [
                {'start': 1, 'end': 3, 'color': '#ffcc00'},
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final painter = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((w) => w.painter)
          .whereType<VerseMarkerPainter>()
          .single;
      final range = painter.ranges.single;
      final text = painter.paragraph()!.text.toPlainText();
      expect(
        text.substring(range.start, range.end),
        'HERR\u2060\ufffc ist gut',
      );
      expect(painter.rectangles(range), hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'settings justify paragraphs and preserve the verse across offstage changes and restart',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      final api = _PresentationApi(readerFixture());
      addTearDown(api.dispose);
      await tester.pumpWidget(AkribosApp(api: api, enableLinks: false));
      await tester.pumpAndSettle();
      await AppScope.of(tester.element(find.byType(ReaderScreen)))
          .open('/Joh1,16');
      await tester.pumpAndSettle();
      final controller = tester
          .widget<ReaderScreen>(find.byType(ReaderScreen))
          .controller!;
      final readerState = tester.state(find.byType(ReaderScreen));
      final pageCalls = api.pages.length;
      Future<void> changePresentation(String label) async {
        await tester.tap(find.text('Mehr'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Einstellungen'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(ListTile, label));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<ListTile>(find.widgetWithText(ListTile, label))
              .selected,
          isTrue,
        );
        await tester.tap(find.text('Lesen'));
        await tester.pumpAndSettle();
        expect(tester.state(find.byType(ReaderScreen)), same(readerState));
        expect(api.pages.length, pageCalls);
      }

      expect(
        tester
            .state<VerseTextState>(find.byType(VerseText).first)
            .paragraph!
            .textAlign,
        TextAlign.start,
      );
      controller.showTabs();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('reader-add-tab')), findsOneWidget);
      expect(find.byTooltip('Werk hinzufügen'), findsNothing);
      expect(find.byTooltip('Eigene Notizen und Dokumente'), findsNothing);
      expect(find.byTooltip('Textdarstellung'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('reader-add-tab')));
      await tester.pumpAndSettle();
      expect(find.byType(ListTile), findsWidgets);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(controller.tabCount, 1);
      expect(api.actions, isEmpty);
      await changePresentation('Fließtext');
      final text = tester.widget<VerseText>(find.byType(VerseText).first);
      expect(text.passages, hasLength(30));
      final paragraph = tester.state<VerseTextState>(
        find.byType(VerseText).first,
      );
      final render = paragraph.paragraph!;
      expect(render.textAlign, TextAlign.justify);
      final viewport = tester.getTopLeft(find.byType(CustomScrollView));
      expect(
        (render.localToGlobal(Offset(0, paragraph.passageTop(15))).dy -
                viewport.dy)
            .abs(),
        lessThan(2),
      );
      final saved = await api.localStore.read();
      expect(saved?['versePerLine'], isFalse);
      expect(Uri.parse(asString(saved?['path'])).path, '/Joh1,16');
      text.passages![15].onWord!({
        'kind': 'w',
        'text': 'Liebe',
        'strong': 'G26',
      }, 0);
      await tester.pumpAndSettle();
      expect(find.text('Lexikon · G26'), findsOneWidget);
      await tester.tap(find.byTooltip('Lexikon schließen'));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -220));
      await tester.pumpAndSettle();
      await controller.flush();
      final moved = await api.localStore.read();
      expect(asInt(controller.reference['verse']), greaterThan(16));
      final currentVerse = '${controller.reference['verse']}';
      await changePresentation('Versweise');
      final current = find.byWidgetPredicate(
        (w) => w is VerseText && w.verseNumber == currentVerse,
      );
      expect(current, findsOneWidget);
      expect((tester.getTopLeft(current).dy - viewport.dy).abs(), lessThan(5));
      expect((await api.localStore.read())?['path'], moved?['path']);
      await changePresentation('Fließtext');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(AkribosApp(api: api, enableLinks: false));
      await tester.pumpAndSettle();
      expect(
        tester.widget<VerseText>(find.byType(VerseText).first).passages,
        hasLength(30),
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final scale in [100, 200]) {
    testWidgets(
      'section and chapter headings exceed scripture at $scale percent',
      (tester) async {
        final data = readerFixture()..['readerFontScale'] = scale;
        final chapter = asMap(asMaps(data['columns']).first['initialChapter']);
        asMap(
          (asMaps(asMap(chapter['chapter'])['rows']).first['cells'] as List)
              .first,
        )['heading'] = 'Ein neuer Abschnitt';
        final api = ReaderApi(data);
        await tester.pumpWidget(app(api, const ReaderScreen(path: '/Joh1')));
        await tester.pumpAndSettle();
        final body = tester
            .widget<VerseText>(find.byType(VerseText).first)
            .fontSize;
        expect(
          tester.widget<Text>(find.text('Ein neuer Abschnitt')).style!.fontSize,
          greaterThan(body),
        );
        expect(
          tester.widget<Text>(find.text('Johannes 1')).style!.fontSize,
          greaterThan(body),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
