import 'dart:io';
import 'dart:ui' as ui;

import 'package:akribos_app/core/api_client.dart';
import 'package:akribos_app/core/app_scope.dart';
import 'package:akribos_app/features/documents/document_editor.dart';
import 'package:akribos_app/theme/akribos_theme.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

const _sermon = '''## Was uns trägt

-   **Hoffnung** wächst, wenn wir uns Zeit zum Zuhören nehmen. Ein kleiner Schritt kann vieles verändern.[^1]

    -   Raum für ehrliche Fragen schaffen und aufmerksam bleiben.

    -   Die nächste Begegnung bewusst gestalten.

    -   Andere höher achten und auf ihre Gedanken eingehen.

    -   Aufmerksam bleiben.

    -   Uns für andere interessieren.

-   **Vertrauen** schenkt Mut für den nächsten Schritt.

    > Ein kleiner Anfang kann viel verändern.

    Danach geht der Gedanke im selben Listenpunkt weiter.

### Eine Einladung für heute

1. Zur Ruhe kommen.
2. Einen Gedanken mitnehmen.

| Gedanke | Einladung |
| :--- | :--- |
| **Zuhören** | Heute bewusst Zeit schenken. |
| **Vertrauen** | Einen offenen Schritt wagen. |

[^1]: Diese Beispielausarbeitung dient ausschließlich der Darstellung des Editors. Sie enthält **keine privaten Inhalte**.
''';

class _CaptureApi extends AppApi {
  _CaptureApi() : super(server: 'https://example.test', cookies: CookieJar());
  @override
  Future<Json> page(String path) async => {
    'user': {'id': 'synthetic-screenshot-user'},
    'readerFontScale': 100,
    'document': {
      'id': 'screenshot-sermon',
      'kind': 'sermon',
      'title': 'Getragen durch Hoffnung',
      'bodyMarkdown': _sermon,
      'bodyHtml': '',
      'revision': 1,
    },
    'bibles': [],
    'tags': [],
    'passages': [],
    'attachments': [],
  };
  @override
  Future<dynamic> get(String path) async => {};
}

void main() {
  testWidgets(
    'capture native Markdown editor and complete document reading surfaces',
    (tester) async {
      if (!const bool.fromEnvironment('AKRIBOS_EDITOR_SCREENSHOTS')) return;
      FlutterSecureStorage.setMockInitialValues({});
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
          reading.addFont(
            rootBundle.load('assets/fonts/akribos-text-$cut.ttf'),
          );
        }
        final controls = FontLoader('Roboto')
          ..addFont(
            File('/usr/share/fonts/noto/NotoSans-Regular.ttf')
                .readAsBytes()
                .then(ByteData.sublistView),
          );
        final sourceFont = FontLoader('monospace')
          ..addFont(
            File('/usr/share/fonts/liberation/LiberationMono-Regular.ttf')
                .readAsBytes()
                .then(ByteData.sublistView),
          );
        final icons = FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
        await Future.wait([
          reading.load(),
          controls.load(),
          sourceFont.load(),
          icons.load(),
        ]);
      });
      for (final entry in [
        ('editor-phone', const Size(390, 844), false, Brightness.light),
        ('editor-phone-dark', const Size(390, 844), false, Brightness.dark),
        ('editor-reading', const Size(390, 844), true, Brightness.light),
        ('editor-reading-dark', const Size(390, 844), true, Brightness.dark),
        ('editor-tablet', const Size(1280, 900), false, Brightness.light),
        (
          'editor-tablet-reading',
          const Size(1280, 900),
          true,
          Brightness.light,
        ),
        ('editor-reading-large', const Size(390, 844), true, Brightness.dark),
      ]) {
        tester.view.physicalSize = entry.$2;
        tester.view.devicePixelRatio = 1;
        final api = _CaptureApi();
        final boundary = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundary,
            child: AppScope(
              api: api,
              open: (_) async {},
              refreshSession: () async {},
              setNavigationGuard: (_, _) {},
              setTheme: (_) {},
              themeMode: entry.$4 == Brightness.dark
                  ? ThemeMode.dark
                  : ThemeMode.light,
              child: MaterialApp(
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    textScaler: TextScaler.linear(
                      entry.$1 == 'editor-reading-large' ? 1.6 : 1,
                    ),
                  ),
                  child: child!,
                ),
                debugShowCheckedModeBanner: false,
                locale: const Locale('de'),
                supportedLocales: const [Locale('de')],
                localizationsDelegates: const [
                  GlobalMaterialLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                ],
                theme: buildAkribosTheme(entry.$4),
                home: const Scaffold(
                  body: SafeArea(
                    child: DocumentEditor(path: '/notes/screenshot-sermon'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        if (entry.$3) {
          await tester.tap(find.text('Lesen'));
          await tester.pumpAndSettle();
        }
        expect(tester.takeException(), isNull);
        await tester.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory('docs/screenshots').create(recursive: true);
          await File('docs/screenshots/${entry.$1}.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        api.dispose();
      }
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    },
  );
}
