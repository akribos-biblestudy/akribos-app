import 'package:akribos_app/core/api_client.dart';
import 'package:akribos_app/core/app_scope.dart';
import 'package:akribos_app/core/operator_browser.dart';
import 'package:akribos_app/features/account/account_screen.dart';
import 'package:akribos_app/features/help/help_screen.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('de.akribos.app/browser');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];
  final navigations = <String>[];
  late AppApi api;
  late FakeHttpAdapter adapter;
  var launches = true;

  setUp(() {
    launches = true;
    calls.clear();
    navigations.clear();
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return launches;
    });
    adapter = FakeHttpAdapter(
      (_) async => success({
        'user': {'id': 'reader', 'email': 'reader@example.test'},
        'hasPassword': false,
      }),
    );
    api = AppApi(
      server: 'https://operator.example.test',
      dio: Dio()..httpClientAdapter = adapter,
      cookies: CookieJar(),
    );
  });
  tearDown(() {
    api.dispose();
    messenger.setMockMethodCallHandler(channel, null);
  });

  Widget host(Widget child) => MaterialApp(
    home: AppScope(
      api: api,
      open: (path) async => navigations.add(path),
      refreshSession: () async {},
      setNavigationGuard: (_, _) {},
      setTheme: (_) {},
      themeMode: ThemeMode.system,
      child: Scaffold(body: child),
    ),
  );

  testWidgets(
    'deletion request opens the configured operator and exact anchor without account writes',
    (tester) async {
      await tester.pumpWidget(host(const AccountScreen(path: '/account')));
      await tester.pumpAndSettle();
      final button = find.text('Löschung anfordern');
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(calls.single.method, 'open');
      expect(calls.single.arguments, {
        'url': 'https://operator.example.test/datenschutz#konto-loeschen',
      });
      expect(navigations, isEmpty);
      expect(
        adapter.requests.every((request) => request.options.method == 'GET'),
        isTrue,
      );
      expect(find.text('Dein Konto'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final path in [
    '/datenschutz#konto-loeschen',
    '/impressum?from=app#kontakt',
    '/about',
  ]) {
    testWidgets('operator page preserves the complete URL $path', (
      tester,
    ) async {
      await tester.pumpWidget(host(InformationScreen(path: path)));
      expect(
        find.text(
          path.startsWith('/datenschutz')
              ? 'Datenschutz'
              : path.startsWith('/impressum')
              ? 'Impressum'
              : 'Über Akribos',
        ),
        findsOneWidget,
      );
      final button = find.text('Aktuelle Angaben des Betreibers öffnen');
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(calls.single.arguments, {
        'url': 'https://operator.example.test$path',
      });
      expect(navigations, isEmpty);
      expect(adapter.requests, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  for (final failedWithException in [false, true]) {
    testWidgets(
      'operator launch failure remains visible (exception: $failedWithException)',
      (tester) async {
        launches = false;
        if (failedWithException) {
          messenger.setMockMethodCallHandler(channel, (_) async {
            throw PlatformException(code: 'unavailable');
          });
        }
        await tester.pumpWidget(
          host(const InformationScreen(path: '/datenschutz#konto-loeschen')),
        );
        final button = find.text('Aktuelle Angaben des Betreibers öffnen');
        await tester.ensureVisible(button);
        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(
          find.textContaining(
            'Öffne https://operator.example.test/datenschutz#konto-loeschen in deinem Browser.',
          ),
          findsOneWidget,
        );
        expect(navigations, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }

  test(
    'non-web URLs and credentials never reach the browser channel',
    () async {
      for (final value in [
        'javascript:alert(1)',
        'file:///private/account',
        'akribos://open?path=/account',
        'https://user:password@operator.example.test/datenschutz',
      ]) {
        await expectLater(
          openOperatorPage(Uri.parse(value)),
          throwsA(isA<ApiException>()),
        );
      }
      expect(calls, isEmpty);
    },
  );
}
