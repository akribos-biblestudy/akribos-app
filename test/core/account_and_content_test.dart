import 'dart:convert';

import 'package:akribos_app/core/api_client.dart';
import 'package:akribos_app/core/app_scope.dart';
import 'package:akribos_app/features/account/auth_screen.dart';
import 'package:akribos_app/features/account/account_screen.dart';
import 'package:akribos_app/widgets/action_form.dart';
import 'package:akribos_app/widgets/common.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';

void main() {
  late AppApi api;
  late FakeHttpAdapter adapter;
  late CookieJar cookies;
  final opened = <String>[];
  var refreshes = 0;
  void setup(Future<ResponseBody> Function(CapturedRequest) respond) {
    opened.clear();
    refreshes = 0;
    cookies = CookieJar();
    adapter = FakeHttpAdapter(respond);
    api = AppApi(
      server: 'https://akribos.test',
      dio: Dio()..httpClientAdapter = adapter,
      cookies: cookies,
    );
    addTearDown(api.dispose);
  }

  Widget host(Widget child) => MaterialApp(
    home: AppScope(
      api: api,
      open: (path) async {
        opened.add(path);
      },
      refreshSession: () async {
        refreshes++;
      },
      setNavigationGuard: (_, guard) {},
      setTheme: (_) {},
      themeMode: ThemeMode.system,
      child: Scaffold(body: child),
    ),
  );
  Finder field(String label) => find.byWidgetPredicate(
    (widget) => widget is TextField && widget.decoration?.labelText == label,
  );

  testWidgets(
    'logout is an explicit action and never invokes the redirecting logout GET',
    (tester) async {
      setup(
        (_) async =>
            jsonResponse({'type': 'redirect', 'status': 303, 'location': '/'}),
      );
      await tester.pumpWidget(host(const AuthScreen(path: '/logout')));
      expect(adapter.requests, isEmpty);
      await tester.tap(find.text('Auf diesem Gerät abmelden'));
      await tester.pumpAndSettle();
      expect(
        adapter.requests.single.options.uri.queryParameters['action'],
        'default',
      );
      expect(refreshes, 1);
      expect(opened, ['/Joh1']);
    },
  );
  testWidgets(
    'verification shows the pending address and refuses an expired link',
    (tester) async {
      setup(
        (request) async => success({
          'pending':
              request.options.uri.queryParameters['path'] ==
                  '/login/verify/valid'
              ? {'email': 'reader@example.test'}
              : null,
        }),
      );
      await tester.pumpWidget(
        host(const AuthScreen(path: '/login/verify/valid')),
      );
      await tester.pumpAndSettle();
      expect(find.text('reader@example.test'), findsOneWidget);
      expect(find.text('Bestätigen'), findsOneWidget);
      await tester.pumpWidget(
        host(const AuthScreen(path: '/login/verify/expired')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Bestätigen'), findsNothing);
      expect(find.textContaining('ungültig, abgelaufen'), findsOneWidget);
    },
  );
  testWidgets(
    'a restarted email flow navigates to the challenge URL instead of reloading restart',
    (tester) async {
      setup(
        (request) async => request.options.method == 'GET'
            ? success({'pending': null, 'redirectTo': '/account'})
            : jsonResponse({
                'type': 'redirect',
                'status': 303,
                'location': '/login?redirectTo=%2Faccount',
              }),
      );
      await tester.pumpWidget(host(const AuthScreen(path: '/login?restart=1')));
      await tester.pumpAndSettle();
      await tester.enterText(field('E-Mail-Adresse'), 'reader@example.test');
      await tester.tap(find.text('Weiter'));
      await tester.pumpAndSettle();
      expect(opened, ['/login?redirectTo=%2Faccount']);
      expect(
        adapter.requests.where((request) => request.options.method == 'GET'),
        hasLength(1),
      );
    },
  );
  testWidgets(
    'new password fields receive controllers after account data reloads',
    (tester) async {
      setup((_) async => success());
      const first = ActionForm(
        title: 'Passwort',
        path: '/account',
        action: 'password',
        fields: [FormFieldSpec('password', 'Neues Passwort')],
      );
      const next = ActionForm(
        title: 'Passwort',
        path: '/account',
        action: 'password',
        fields: [
          FormFieldSpec('currentPassword', 'Aktuelles Passwort'),
          FormFieldSpec('password', 'Neues Passwort'),
        ],
      );
      await tester.pumpWidget(host(first));
      await tester.pumpWidget(host(next));
      await tester.enterText(
        field('Aktuelles Passwort'),
        'current-test-password',
      );
      await tester.enterText(field('Neues Passwort'), 'next-test-password');
      await tester.tap(find.text('Speichern'));
      await tester.pumpAndSettle();
      expect(adapter.requests.single.json['fields'], {
        'currentPassword': 'current-test-password',
        'password': 'next-test-password',
      });
    },
  );
  testWidgets(
    'highlight colors accept a validated custom hex value and preserve native presets',
    (tester) async {
      setup((_) async => success());
      await tester.pumpWidget(
        host(
          const ActionForm(
            title: 'Markierungsfarbe hinzufügen',
            path: '/account',
            action: 'addHighlightStyle',
            fields: [
              FormFieldSpec(
                'color',
                'Farbe',
                kind: FieldKind.color,
                value: '#f4d35e',
                options: {'#f4d35e': 'Gold', '#8abde3': 'Blau'},
              ),
            ],
          ),
        ),
      );
      await tester.enterText(field('Farbe'), '#xyz');
      await tester.tap(find.text('Speichern'));
      await tester.pumpAndSettle();
      expect(adapter.requests, isEmpty);
      expect(
        find.text('Bitte eine Farbe im Format #RRGGBB eingeben.'),
        findsOneWidget,
      );
      await tester.enterText(field('Farbe'), '#123aBc');
      await tester.pump();
      final preview = tester.widget<Icon>(
        find.byKey(const ValueKey('color-preview:color')),
      );
      expect(preview.color, const Color(0xff123abc));
      await tester.tap(find.text('Speichern'));
      await tester.pumpAndSettle();
      expect(adapter.requests.single.json['fields'], {'color': '#123aBc'});
      await tester.tap(find.text('Blau'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(field('Farbe')).controller!.text,
        '#8abde3',
      );
      await tester.tap(find.text('Speichern'));
      await tester.pumpAndSettle();
      expect(adapter.requests.last.json['fields'], {'color': '#8abde3'});
    },
  );
  testWidgets(
    'highlight list renders structured verse text and opens its canonical reference',
    (tester) async {
      setup(
        (_) async => success({
          'title': 'Markierungen',
          'verses': [
            {
              'book': 43,
              'chapter': 3,
              'verse': 16,
              'endVerse': 17,
              'segments': ['Gott liebt die Welt.'],
            },
          ],
        }),
      );
      await tester.pumpWidget(
        host(const AccountScreen(path: '/account/highlights/style')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Joh3,16-17'), findsOneWidget);
      await tester.tap(find.text('Joh3,16-17'));
      await tester.pumpAndSettle();
      expect(opened, ['/Joh3,16-17']);
      expect(
        highlightReference({
          'book': 43,
          'chapter': 1,
          'verse': 1,
          'endVerse': 1,
        }),
        {'book': 43, 'chapter': 1, 'verse': 1},
      );
    },
  );
  testWidgets(
    'HTML images use authenticated same-origin requests and external images stay unloaded',
    (tester) async {
      final png = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
      );
      setup(
        (_) async => ResponseBody.fromBytes(
          png,
          200,
          headers: {
            'content-type': ['image/png'],
          },
        ),
      );
      await cookies.saveFromResponse(api.origin, [
        Cookie('session', 'image-session')
          ..path = '/'
          ..secure = true,
      ]);
      await tester.pumpWidget(
        host(
          const HtmlContent(
            html: '<img src="/help/media/admin.png" alt="Intern"><img src="https://external.test/pixel.png" alt="Extern"><p style="background-image:url(https://external.test/background.png)">Text</p>',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(adapter.requests, hasLength(1));
      expect(adapter.requests.single.options.uri.path, '/help/media/admin.png');
      expect(
        adapter.requests.single.options.headers['cookie'],
        contains('session=image-session'),
      );
      expect(
        find.textContaining('Externes Bild wird nicht geladen'),
        findsOneWidget,
      );
    },
  );
  testWidgets(
    'mailto links ask before opening without evaluating a nonexistent HTTP origin',
    (tester) async {
      setup((_) async => success());
      await tester.pumpWidget(
        host(
          const HtmlContent(
            html: '<a href="mailto:reader@example.test">E-Mail</a>',
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('E-Mail', findRichText: true));
      await tester.pumpAndSettle();
      expect(find.text('Externen Link öffnen?'), findsOneWidget);
      expect(adapter.requests, isEmpty);
      await tester.tap(find.text('Abbrechen'));
      await tester.pumpAndSettle();
    },
  );
}
