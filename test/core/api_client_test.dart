import 'dart:convert';

import 'package:akribos_app/core/api_client.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';

void main() {
  late CookieJar cookies;
  late AppApi api;
  late FakeHttpAdapter adapter;
  void setup(Future<ResponseBody> Function(CapturedRequest) respond) {
    cookies = CookieJar();
    adapter = FakeHttpAdapter(respond);
    api = AppApi(
      server: 'https://akribos.test',
      dio: Dio()..httpClientAdapter = adapter,
      cookies: cookies,
      browserTabId: 'b5f284be-271b-4f93-9f9f-970700b6176c',
    );
    addTearDown(api.dispose);
  }

  test('normalizes native numbers, booleans and repeated fields without losing leading zeroes', () async {
    setup((_) async => success());
    await api.action('/account', 'reader', {
      'fontScale': 125,
      'flag': true,
      'id': '0012',
      'values': [1, false, '003'],
      'absent': null,
    });
    expect(adapter.requests.single.json, {
      'fields': {
        'fontScale': '125',
        'flag': 'true',
        'id': '0012',
        'values': ['1', 'false', '003'],
      },
    });
    expect(
      adapter.requests.single.options.headers['Origin'],
      'https://akribos.test',
    );
    expect(adapter.requests.single.options.headers['x-akribos-app'], '1');
    expect(adapter.requests.single.options.followRedirects, isFalse);
    expect(
      () => api.action('/notes', 'create', {
        'title': {'bad': 'object'},
      }),
      throwsA(isA<ApiException>()),
    );
  });
  test(
    'rejects foreign URLs and non-HTTP schemes before sending cookies',
    () async {
      setup((_) async => success());
      await cookies.saveFromResponse(api.origin, [
        Cookie('session', 'private-session')
          ..path = '/'
          ..secure = true,
      ]);
      for (final path in [
        'https://evil.test/',
        '//evil.test/',
        'mailto:user@example.test',
        'file:///etc/passwd',
        'https://user@akribos.test/',
        '/\\evil.test/',
      ]) {
        await expectLater(api.get(path), throwsA(isA<ApiException>()));
      }
      expect(adapter.requests, isEmpty);
    },
  );
  test('does not follow off-origin redirects or copy session cookies to their target', () async {
    setup(
      (_) async => jsonResponse(
        {},
        status: 302,
        headers: {
          'location': ['https://evil.test/'],
          'set-cookie': ['session=redirect-cookie; Path=/; Secure; HttpOnly'],
        },
      ),
    );
    await expectLater(api.get('/notes'), throwsA(isA<ApiException>()));
    expect(adapter.requests, hasLength(1));
    expect(
      await cookies.loadForRequest(Uri.parse('https://evil.test/')),
      isEmpty,
    );
    expect(
      (await cookies.loadForRequest(api.origin)).single.value,
      'redirect-cookie',
    );
  });
  test('returns local HTTP redirects without replaying a mutation', () async {
    setup(
      (_) async => jsonResponse(
        {},
        status: 303,
        headers: {
          'location': ['/login'],
        },
      ),
    );
    await expectLater(
      api.send('PATCH', '/api/documents/id', data: {'revision': 1}),
      throwsA(
        isA<AppRedirect>().having(
          (error) => error.location,
          'location',
          '/login',
        ),
      ),
    );
    expect(adapter.requests, hasLength(1));
  });
  test(
    'rejects foreign envelope redirects and preserves conflict details',
    () async {
      setup(
        (request) async =>
            request.options.uri.queryParameters['action'] == 'create'
            ? jsonResponse({
                'type': 'redirect',
                'status': 303,
                'location': 'https://evil.test/',
              })
            : jsonResponse({
                'type': 'failure',
                'status': 409,
                'data': {'error': 'conflict', 'currentRevision': 7},
              }, status: 409),
      );
      await expectLater(
        api.action('/notes', 'create', {}),
        throwsA(isA<ApiException>()),
      );
      final result = await api.action('/notes', 'restore', {'revision': 1});
      expect(result.isSuccess, isFalse);
      expect(result.status, 409);
      expect(result.data['currentRevision'], 7);
    },
  );
  test('email challenge cookies stay on app paths and session cookies reach document API', () async {
    setup((request) async {
      final action = request.options.uri.queryParameters['action'];
      if (action == 'start') {
        return jsonResponse(
          {'type': 'redirect', 'status': 303, 'location': '/login'},
          headers: {
            'set-cookie': [
              'app-email-login=challenge; Path=/api/app; HttpOnly; Secure',
            ],
          },
        );
      }
      if (action == 'code') {
        return jsonResponse(
          {'type': 'redirect', 'status': 303, 'location': '/account'},
          headers: {
            'set-cookie': [
              'session=authenticated; Path=/; HttpOnly; Secure',
              'app-email-login=; Path=/api/app; Max-Age=0; HttpOnly; Secure',
            ],
          },
        );
      }
      return success();
    });
    await api.action('/login', 'start', {'email': 'reader@example.test'});
    await api.page('/login');
    expect(
      adapter.requests.last.options.headers['cookie'],
      contains('app-email-login=challenge'),
    );
    await api.get('/api/documents');
    expect(adapter.requests.last.options.headers['cookie'], isNull);
    await api.action('/login', 'code', {'code': '001234'});
    expect(adapter.requests.last.json['fields']['code'], '001234');
    await api.get('/api/documents');
    expect(
      adapter.requests.last.options.headers['cookie'],
      contains('session=authenticated'),
    );
    expect(
      await cookies.loadForRequest(
        Uri.parse('https://akribos.test/api/app/page'),
      ),
      hasLength(1),
    );
    await api.clearSession();
    expect(await cookies.loadForRequest(api.origin), isEmpty);
  });
  test(
    'password login carries a local redirect without changing form semantics',
    () async {
      setup(
        (request) async =>
            request.options.uri.queryParameters['action'] == 'start'
            ? success({'step': 'password', 'email': 'reader@example.test'})
            : jsonResponse({
                'type': 'redirect',
                'status': 303,
                'location': '/account',
              }),
      );
      expect(
        (await api.action('/login', 'start', {
          'email': 'reader@example.test',
        })).data['step'],
        'password',
      );
      final result = await api.action('/login', 'login', {
        'email': 'reader@example.test',
        'password': 'test-password',
        'redirectTo': '/account',
      });
      expect(result.isRedirect, isTrue);
      expect(result.location, '/account');
      expect(adapter.requests.last.json['fields']['redirectTo'], '/account');
    },
  );
  test(
    'multipart keeps file bytes and repeated fields and sends CSRF origin',
    () async {
      setup((_) async => success({'canImport': true}));
      await api.uploadAction(
        '/notes/import',
        'preview',
        {
          'tags': ['eins', 'zwei'],
          'revision': 2,
        },
        [
          AppUpload(
            field: 'file',
            name: 'study.md',
            bytes: utf8.encode('# Prüfung'),
            contentType: 'text/markdown',
          ),
        ],
      );
      final request = adapter.requests.single;
      expect(request.options.contentType, startsWith('multipart/form-data'));
      expect(request.options.headers['Origin'], 'https://akribos.test');
      final body = utf8.decode(request.body);
      expect(body, contains('filename="study.md"'));
      expect(body, contains('# Prüfung'));
      expect(body, contains('eins'));
      expect(body, contains('zwei'));
    },
  );
}
