import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:akribos_app/core/api_client.dart';
import 'package:akribos_app/core/app_scope.dart';
import 'package:akribos_app/features/documents/markdown_document_reader.dart';
import 'package:akribos_app/theme/akribos_theme.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;

final _fixtures = jsonDecode(
  File('test/features/documents/fixtures/web_markdown_rendering.json')
      .readAsStringSync(),
) as Map<String, dynamic>;

Widget _host(
  Widget child, {
  required AppApi api,
  double scale = 1,
  Brightness brightness = Brightness.light,
  Future<void> Function(String)? open,
}) => AppScope(
  api: api,
  open: open ?? (_) async {},
  refreshSession: () async {},
  setNavigationGuard: (_, _) {},
  setTheme: (_) {},
  themeMode: ThemeMode.system,
  child: MaterialApp(
    theme: buildAkribosTheme(brightness),
    home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(scale)),
      child: Scaffold(body: child),
    ),
  ),
);

void main() {
  for (final name in ['listQuote', 'fiveSubitems', 'quotedContinuation']) {
    test('complete web serializer fixture $name keeps container hierarchy', () {
      final fixture = _fixtures[name] as Map<String, dynamic>;
      final source = fixture['markdown'] as String;
      final actual = html.parseFragment(renderDocumentMarkdown(source));
      final web = html.parseFragment(fixture['rendered'] as String);
      for (final selector in [
        'ul',
        'li',
        'blockquote',
        'li > blockquote',
        'li > ul',
        'strong',
      ]) {
        expect(
          actual.querySelectorAll(selector).length,
          web.querySelectorAll(selector).length,
          reason: selector,
        );
      }
      expect(actual.querySelectorAll('pre'), isEmpty);
      expect(source, fixture['markdown']);
    });
  }
  test('genuine code remains code and source is never rewritten', () {
    final source = _fixtures['genuineCode']['markdown'] as String;
    final parsed = html.parseFragment(renderDocumentMarkdown(source));
    expect(
      parsed.querySelector('pre code')!.text,
      contains('-   Uns für andere echt interessieren'),
    );
    expect(parsed.querySelectorAll('pre'), hasLength(1));
  });
  test(
    'rich repeated and unreferenced footnotes render without upstream crash',
    () {
      final source = _fixtures['footnotes']['markdown'] as String;
      final parsed = html.parseFragment(renderDocumentMarkdown(source));
      expect(parsed.querySelectorAll('[data-footnote-ref="n"]'), hasLength(2));
      expect(
        parsed.querySelector('[data-footnote-id="n"] ul li')!.text,
        'Punkt',
      );
      expect(
        parsed.querySelector('[data-footnote-id="n"] blockquote')!.text,
        contains('Zitat'),
      );
      expect(
        parsed.querySelector('[data-footnote-id="unused"]')!.text,
        contains('Nicht referenziert'),
      );
      expect(parsed.querySelectorAll('u'), hasLength(1));
      expect(parsed.querySelectorAll('mark'), hasLength(1));
    },
  );
  test(
    'server HTML remains authoritative and gains native footnote targets',
    () {
      final rendered = renderDocumentMarkdown(
        'A different source is a caller error.',
        renderedHtml: _fixtures['footnotes']['rendered'] as String,
      );
      final parsed = html.parseFragment(rendered);
      expect(parsed.querySelectorAll('[data-footnote-ref="n"]'), hasLength(2));
      expect(parsed.querySelector('[id="fn-n"]'), isNotNull);
      expect(parsed.text, isNot(contains('A different source')));
    },
  );
  test('unsafe media and links never survive local display HTML', () {
    final parsed = html.parseFragment(
      renderDocumentMarkdown(
        '<script>bad()</script>\n\n<img src="https://outside.test/image">\n\n[bad](javascript:alert) [Bible](/Joh3,16) [Section](#section)\n\n<u onclick="bad()">Okay</u>',
      ),
    );
    expect(parsed.querySelectorAll('script,iframe,[onclick]'), isEmpty);
    expect(parsed.querySelectorAll('[href^="javascript:"]'), isEmpty);
    expect(parsed.querySelector('[href="/Joh3,16"]'), isNotNull);
    expect(parsed.querySelector('[href="#section"]'), isNotNull);
  });
  test(
    'empty server HTML falls back and tasks and image descriptors survive',
    () {
      final parsed = html.parseFragment(
        renderDocumentMarkdown(
          '- [x] Erledigt\n- [ ] Offen\n\n![Eigenes Bild](/api/documents/id/attachments/image)\n',
          renderedHtml: '',
        ),
      );
      expect(parsed.text, contains('☑'));
      expect(parsed.text, contains('☐'));
      expect(
        parsed.querySelector('img')!.attributes['src'],
        '/api/documents/id/attachments/image',
      );
      expect(parsed.querySelector('img')!.attributes['alt'], 'Eigenes Bild');
    },
  );
  testWidgets('marked text has readable rendered contrast in both themes', (
    tester,
  ) async {
    final api = AppApi(server: 'https://example.test', cookies: CookieJar());
    addTearDown(api.dispose);
    for (final brightness in [Brightness.light, Brightness.dark]) {
      await tester.pumpWidget(
        _host(
          const MarkdownDocumentReader(markdown: '<mark>Markiert</mark>'),
          api: api,
          brightness: brightness,
        ),
      );
      await tester.pumpAndSettle();
      final paragraph = tester
          .renderObjectList<RenderParagraph>(find.byType(RichText))
          .singleWhere((p) => p.text.toPlainText() == 'Markiert');
      Color? foreground;
      void inspect(InlineSpan span, TextStyle parent) {
        final style = parent.merge(span.style);
        if (span is TextSpan) {
          if (span.text?.contains('Markiert') == true) foreground = style.color;
          for (final child in span.children ?? <InlineSpan>[]) {
            inspect(child, style);
          }
        }
      }

      inspect(paragraph.text, const TextStyle());
      expect(foreground, isNotNull);
      final background = buildAkribosTheme(brightness)
          .extension<AkribosThemeTokens>()!
          .accentSoft;
      final a = foreground!.computeLuminance(),
          b = background.computeLuminance();
      expect(
        ((a > b ? a : b) + .05) / ((a < b ? a : b) + .05),
        greaterThanOrEqualTo(4.5),
      );
      expect(tester.takeException(), isNull);
    }
  });
  testWidgets(
    'footnote sheet closes without navigation or reading-position loss',
    (tester) async {
      final api = AppApi(server: 'https://example.test', cookies: CookieJar());
      addTearDown(api.dispose);
      final controller = ScrollController();
      addTearDown(controller.dispose);
      final paths = <String>[];
      await tester.pumpWidget(
        _host(
          MarkdownDocumentReader(
            markdown: _fixtures['footnotes']['markdown'] as String,
            scrollController: controller,
          ),
          api: api,
          open: (path) async {
            paths.add(path);
          },
        ),
      );
      await tester.pumpAndSettle();
      final offset = controller.offset;
      await tester.tap(find.bySemanticsLabel(RegExp('Fußnote 1 öffnen')).first);
      await tester.pumpAndSettle();
      expect(find.text('Fußnote 1'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Schließen'));
      await tester.pumpAndSettle();
      expect(find.text('Fußnote 1'), findsNothing);
      expect(controller.offset, offset);
      expect(paths, isEmpty);
    },
  );
  testWidgets(
    'same-document anchors scroll locally while Bible links retain target',
    (tester) async {
      final api = AppApi(server: 'https://example.test', cookies: CookieJar());
      addTearDown(api.dispose);
      final controller = ScrollController();
      addTearDown(controller.dispose);
      final paths = <String>[];
      final source =
          '[Zur Stelle](#target)\n\n${List.filled(20, 'Ein Absatz mit etwas Text.').join('\n\n')}\n\n<h2 id="target">Ziel</h2>\n\n[Bibel](/Joh3,16#v16)';
      await tester.pumpWidget(
        _host(
          MarkdownDocumentReader(
            markdown: source,
            scrollController: controller,
          ),
          api: api,
          open: (path) async {
            paths.add(path);
          },
        ),
      );
      await tester.pumpAndSettle();
      await tester.tapAt(
        tester.getTopLeft(find.text('Zur Stelle', findRichText: true)) +
            const Offset(20, 15),
      );
      await tester.pumpAndSettle();
      expect(controller.offset, greaterThan(0));
      expect(paths, isEmpty);
      await tester.tapAt(
        tester.getTopLeft(find.text('Bibel', findRichText: true)) +
            const Offset(20, 15),
      );
      await tester.pumpAndSettle();
      expect(paths, ['/Joh3,16#v16']);
    },
  );
  testWidgets(
    'list marker shares first-line baseline at phone and tablet text scales',
    (tester) async {
      final api = AppApi(server: 'https://example.test', cookies: CookieJar());
      addTearDown(api.dispose);
      await _loadFonts(tester);
      for (final size in [const Size(320, 780), const Size(1000, 900)]) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        for (final scale in [1.0, 2.0]) {
          await tester.pumpWidget(
            _host(
              const MarkdownDocumentReader(
                markdown: '1. Parent with a long text that can wrap onto another line.\n\n   - Child with another long text wrapping across multiple lines.\n\n   > Quote\n',
              ),
              api: api,
              scale: scale,
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          final paragraphs = tester
              .renderObjectList<RenderParagraph>(find.byType(RichText))
              .where((p) => p.text.toPlainText().startsWith('Parent'))
              .toList();
          final markers = tester
              .renderObjectList<RenderParagraph>(find.byType(RichText))
              .where((p) => p.text.toPlainText() == '1.')
              .toList();
          expect(paragraphs, hasLength(1));
          expect(markers, hasLength(1));
          double baseline(RenderParagraph p) =>
              p.localToGlobal(Offset.zero).dy +
              (TextPainter(
                    text: p.text,
                    textDirection: p.textDirection,
                    textScaler: p.textScaler,
                  )..layout(maxWidth: p.size.width))
                  .computeLineMetrics()
                  .first
                  .baseline;
          expect(
            baseline(markers.single),
            closeTo(baseline(paragraphs.single), .1),
          );
          final children = tester
              .renderObjectList<RenderParagraph>(find.byType(RichText))
              .where((p) => p.text.toPlainText().startsWith('Child'))
              .toList();
          final bullets = tester
              .renderObjectList<RenderParagraph>(find.byType(RichText))
              .where(
                (p) => const {'•', '◦', '▪'}.contains(p.text.toPlainText()),
              )
              .toList();
          expect(children, hasLength(1));
          expect(bullets, hasLength(1));
          expect(
            baseline(bullets.single),
            closeTo(baseline(children.single), .1),
          );
          expect(
            bullets.single.textScaler.scale(19),
            children.single.textScaler.scale(19),
          );
          expect(
            children.single.localToGlobal(Offset.zero).dx,
            greaterThan(paragraphs.single.localToGlobal(Offset.zero).dx),
          );
        }
      }
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    },
  );
  testWidgets('capture synthetic native document reader surfaces', (
    tester,
  ) async {
    if (!const bool.fromEnvironment('AKRIBOS_DOCUMENT_READER_SCREENSHOTS')) {
      return;
    }
    await _loadFonts(tester);
    final api = AppApi(server: 'https://example.test', cookies: CookieJar());
    addTearDown(api.dispose);
    final source =
        '# Gemeinsam unterwegs\n\n${_fixtures['listQuote']['markdown']}\n${_fixtures['fiveSubitems']['markdown']}\n| Gedanke | Nächster Schritt |\n| --- | --- |\n| Zuhören | Zeit schenken |\n\n${_fixtures['footnotes']['markdown']}';
    for (final entry in [
      ('reader-phone', const Size(390, 844), Brightness.light, 1.0),
      ('reader-phone-dark', const Size(390, 844), Brightness.dark, 1.0),
      ('reader-tablet', const Size(1100, 900), Brightness.light, 1.0),
      ('reader-large', const Size(390, 844), Brightness.light, 2.0),
    ]) {
      tester.view.physicalSize = entry.$2;
      tester.view.devicePixelRatio = 1;
      final boundary = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: _host(
            MarkdownDocumentReader(markdown: source),
            api: api,
            brightness: entry.$3,
            scale: entry.$4,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final image =
            await (boundary.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary)
                .toImage(pixelRatio: 1);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory('/tmp/akribos-editor-assessment')
            .create(recursive: true);
        await File('/tmp/akribos-editor-assessment/${entry.$1}.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

Future<void> _loadFonts(WidgetTester tester) async {
  await tester.runAsync(() async {
    final reading = FontLoader('AkribosText');
    for (final cut in [
      'regular',
      'italic',
      'semibold',
      'semibold-italic',
      'bold',
      'bold-italic',
    ]) {
      reading.addFont(rootBundle.load('assets/fonts/akribos-text-$cut.ttf'));
    }
    // A bundled stand-in keeps incidental Material labels deterministic on CI;
    // the actual reading baseline uses the AkribosText cuts loaded above.
    final controls = FontLoader('Roboto')
      ..addFont(rootBundle.load('assets/fonts/akribos-text-regular.ttf'));
    await Future.wait([reading.load(), controls.load()]);
  });
}
