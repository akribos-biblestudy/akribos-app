import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:akribos_app/core/api_client.dart';
import 'package:akribos_app/core/app_scope.dart';
import 'package:akribos_app/core/deep_link.dart';
import 'package:akribos_app/main.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _SeedApi extends AppApi {
  _SeedApi() : super(server: 'https://example.test', cookies: CookieJar());
  final Json _seed = asMap(
    jsonDecode(File('test/fixtures/bootstrap.json').readAsStringSync()),
  );
  final Json reader = asMap(
    jsonDecode(File('test/fixtures/reader.json').readAsStringSync()),
  );
  @override
  Future<Json> loadBootstrap() async {
    bootstrap = _seed;
    return bootstrap;
  }

  @override
  Future<Json> page(String path) async {
    if (path == '/login') return {'pending': null, 'redirectTo': '/account'};
    if (path.startsWith('/help')) return {'topics': [], 'results': []};
    // A finite viewport fixture: live chapter loading is tested against the real server separately.
    for (final column in asMaps(reader['columns'])) {
      asMap(column['initialChapter'])['navigation'] = {
        'previous': null,
        'next': null,
      };
    }
    return reader;
  }

  @override
  Future<dynamic> get(String path) async => {'workspaces': []};
  @override
  Future<ApiResult> action(String path, String action, Json fields) async =>
      ApiResult(type: 'success', status: 200, data: reader);
  @override
  Future<dynamic> send(String method, String path, {dynamic data}) async => {
    'saved': true,
  };
}

void main() {
  test('deep links are confined to the configured server', () {
    final server = Uri.parse('https://akribos.de');
    expect(
      appLinkPath(Uri.parse('akribos://open?path=%2FJoh3%2C16'), server),
      '/Joh3,16',
    );
    expect(
      appLinkPath(Uri.parse('https://akribos.de/invites/abc'), server),
      '/invites/abc',
    );
    expect(appLinkPath(Uri.parse('https://evil.test/login'), server), isNull);
    expect(
      appLinkPath(Uri.parse('akribos://open?path=%2F%2Fevil.test'), server),
      isNull,
    );
    expect(
      appLinkPath(Uri.parse('https://user:pass@akribos.de/login'), server),
      isNull,
    );
  });
  for (final width in [320.0, 840.0, 1280.0]) {
    testWidgets(
      'native shell fits $width px and opens account dialog navigation',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final api = _SeedApi();
        addTearDown(api.dispose);
        await tester.pumpWidget(AkribosApp(api: api, enableLinks: false));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('akribos'), findsOneWidget);
        expect(
          find.byType(width >= 840 ? NavigationRail : NavigationBar),
          findsOneWidget,
        );
        await tester.tap(find.byTooltip('Anmelden'));
        await tester.pumpAndSettle();
        expect(find.text('Willkommen bei Akribos'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
  testWidgets(
    'E-Ink preference survives restart and also reaches dialogs above navigator',
    (tester) async {
      SharedPreferences.setMockInitialValues({'eInk': true});
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = _SeedApi();
      addTearDown(api.dispose);
      await tester.pumpWidget(AkribosApp(api: api, enableLinks: false));
      await tester.pumpAndSettle();
      final context = tester.element(find.byType(Scaffold).first);
      expect(AppScope.of(context).eInk, isTrue);
      expect(MediaQuery.of(context).disableAnimations, isTrue);
      expect(Theme.of(context).colorScheme.primary, Colors.black);
      final result = showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          content: Text(
            AppScope.of(context).eInk ? 'E-Ink verfügbar' : 'Fehlt',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('E-Ink verfügbar'), findsOneWidget);
      Navigator.of(tester.element(find.byType(AlertDialog))).pop(true);
      await tester.pumpAndSettle();
      expect(await result, isTrue);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('capture reproducible seeded Flutter reading views', (
    tester,
  ) async {
    if (!const bool.fromEnvironment('AKRIBOS_SCREENSHOTS')) return;
    await tester.runAsync(() async {
      final reading = FontLoader('AkribosText')
        ..addFont(rootBundle.load('assets/fonts/akribos-text-regular.ttf'));
      final controls = FontLoader('Roboto')
        ..addFont(
          File('/usr/share/fonts/noto/NotoSans-Regular.ttf')
              .readAsBytes()
              .then((bytes) => ByteData.sublistView(bytes)),
        );
      final icons = FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      await reading.load();
      await controls.load();
      await icons.load();
    });
    for (final entry in [
      ('phone', 390.0, 844.0, false),
      ('tablet', 1280.0, 900.0, false),
      ('eink', 1200.0, 900.0, true),
    ]) {
      SharedPreferences.setMockInitialValues({'eInk': entry.$4});
      tester.view.physicalSize = Size(entry.$2, entry.$3);
      tester.view.devicePixelRatio = 1;
      final boundary = GlobalKey();
      final api = _SeedApi();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: AkribosApp(
            key: ValueKey(entry.$1),
            api: api,
            enableLinks: false,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final render =
            boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await render.toImage(pixelRatio: 1);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory('docs/screenshots').create(recursive: true);
        await File('docs/screenshots/${entry.$1}.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
      await tester.pumpWidget(const SizedBox.shrink());
      api.dispose();
    }
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}
