import 'dart:convert';
import 'dart:io';

import 'package:akribos_app/core/api_client.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const server = 'https://akribos.test';
  final origin = Uri.parse(server);

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  AppApi client(FakeHttpAdapter adapter, {CookieJar? cookies}) {
    final api = AppApi(
      server: server,
      dio: Dio()..httpClientAdapter = adapter,
      cookies: cookies,
    );
    addTearDown(api.dispose);
    return api;
  }

  FakeHttpAdapter bootstrapServer() => FakeHttpAdapter((request) async {
    final cookies =
        request.options.headers[HttpHeaders.cookieHeader] as String? ?? '';
    return success({
      'protocolVersion': 1,
      'user': cookies.contains('session=synthetic-session')
          ? {'id': 'synthetic-reader'}
          : null,
    });
  });

  test('Reader initialization keeps the encrypted session across fresh app instances', () async {
    final login = FakeHttpAdapter(
      (_) async => jsonResponse(
        {'type': 'redirect', 'status': 303, 'location': '/account'},
        headers: {
          'set-cookie': [
            'session=synthetic-session; Path=/; Secure; HttpOnly; Expires=${HttpDate.format(DateTime.now().add(const Duration(days: 30)))}',
            'app-email-login=synthetic-challenge; Path=/api/app; Secure; HttpOnly',
            'reader-workspace=synthetic-workspace; Path=/; Secure; HttpOnly',
          ],
        },
      ),
    );
    final first = client(login);
    await first.initializeReader(390);
    await first.action('/login', 'code', {'code': '000000'});
    first.dispose();

    // A replacement APK starts a new Dart process and therefore a fresh jar.
    // Keep the secure platform store, exactly as an in-place update does.
    for (final width in [1024.0, 390.0]) {
      final adapter = bootstrapServer();
      final restarted = client(adapter);
      await restarted.initializeReader(width);
      final data = await restarted.loadBootstrap();
      expect(asMap(data['user'])['id'], 'synthetic-reader');
      final sent =
          adapter.requests.single.options.headers[HttpHeaders.cookieHeader]
              as String;
      expect(sent, contains('session=synthetic-session'));
      expect(sent, contains('app-email-login=synthetic-challenge'));
      expect(sent, contains('reader-workspace=synthetic-workspace'));
      expect(sent, contains('reader-browser-enabled=1'));
      expect(sent, contains('reader-initial-columns=${width < 768 ? 1 : 2}'));
      restarted.dispose();
    }
  });

  test('existing persisted host records are reused without changing storage keys or cookie scope', () async {
    final namespace = base64Url.encode(utf8.encode(origin.origin));
    final legacy = PersistCookieJar(storage: SecureCookieStorage(namespace));
    await legacy.saveFromResponse(origin, [
      Cookie('session', 'synthetic-session')
        ..path = '/'
        ..secure = true
        ..httpOnly = true
        ..expires = DateTime.now().add(const Duration(days: 30)),
      Cookie('app-email-login', 'synthetic-challenge')
        ..path = '/api/app'
        ..secure = true
        ..httpOnly = true,
    ]);
    final keysBefore = (await const FlutterSecureStorage().readAll()).keys
        .toSet();
    final adapter = bootstrapServer();
    final api = client(adapter);
    await api.initializeReader(1280);
    await api.get('/api/documents');
    final sent =
        adapter.requests.single.options.headers[HttpHeaders.cookieHeader]
            as String;
    expect(sent, contains('session=synthetic-session'));
    expect(sent, isNot(contains('app-email-login')));
    expect(
      (await const FlutterSecureStorage().readAll()).keys.toSet(),
      keysBefore,
    );
    final reloaded = PersistCookieJar(storage: SecureCookieStorage(namespace));
    final session = (await reloaded.loadForRequest(origin))
        .singleWhere((cookie) => cookie.name == 'session');
    expect(session.httpOnly, isTrue);
    expect(session.secure, isTrue);
    expect(session.path, '/');
    expect(session.expires!.isAfter(DateTime.now()), isTrue);
  });

  test('explicit logout stays logged out after process restart', () async {
    final adapter = FakeHttpAdapter((_) async => success());
    final jar = PersistCookieJar(
      storage: SecureCookieStorage(
        base64Url.encode(utf8.encode(origin.origin)),
      ),
    );
    await jar.saveFromResponse(origin, [
      Cookie('session', 'synthetic-session')
        ..path = '/'
        ..secure = true,
    ]);
    final api = client(adapter);
    await api.initializeReader(390);
    await api.clearSession();
    api.dispose();
    final restartAdapter = bootstrapServer();
    final restarted = client(restartAdapter);
    await restarted.initializeReader(390);
    expect((await restarted.loadBootstrap())['user'], isNull);
    expect(
      restartAdapter.requests.single.options.headers[HttpHeaders.cookieHeader],
      isNot(contains('session=')),
    );
  });

  test(
    'a failed host-cookie read cannot overwrite the stored session',
    () async {
      final storage = FailingHostStorage();
      final seeded = PersistCookieJar(storage: storage);
      await seeded.saveFromResponse(origin, [
        Cookie('session', 'synthetic-session')
          ..path = '/'
          ..secure = true,
      ]);
      final before = Map<String, String>.from(storage.values);
      storage.failHostRead = true;
      final adapter = bootstrapServer();
      final api = client(adapter, cookies: PersistCookieJar(storage: storage));
      await expectLater(api.initializeReader(390), throwsStateError);
      expect(storage.values, before);
      expect(adapter.requests, isEmpty);
      storage.failHostRead = false;
      await api.initializeReader(390);
      expect(
        asMap((await api.loadBootstrap())['user'])['id'],
        'synthetic-reader',
      );
    },
  );
}

class FailingHostStorage implements Storage {
  final values = <String, String>{};
  bool failHostRead = false;
  @override
  Future<void> init(bool persistSession, bool ignoreExpires) async {}
  @override
  Future<String?> read(String key) async {
    if (failHostRead && key == 'akribos.test') {
      throw StateError('Synthetic storage read failure');
    }
    return values[key];
  }

  @override
  Future<void> write(String key, String value) async => values[key] = value;
  @override
  Future<void> delete(String key) async => values.remove(key);
  @override
  Future<void> deleteAll(List<String> keys) async {
    for (final key in keys) {
      values.remove(key);
    }
  }
}
