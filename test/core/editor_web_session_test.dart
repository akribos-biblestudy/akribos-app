import 'dart:async';
import 'dart:convert';

import 'package:akribos_app/core/api_client.dart';
import 'package:akribos_app/core/editor_web_session.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('de.akribos.app/editor-session');
  final origin = Uri.parse('https://akribos.test');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<MethodCall> calls;

  setUp(() async {
    calls = [];
    FlutterSecureStorage.setMockInitialValues({});
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    await EditorWebSession(channel: channel, supported: true).clear(origin);
    calls.clear();
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  EditorWebSession bridge() =>
      EditorWebSession(channel: channel, supported: true);
  Cookie session(String value) => Cookie('session', value)
    ..path = '/'
    ..secure = true
    ..httpOnly = true;
  AppApi api(CookieJar jar, {FakeHttpAdapter? adapter}) {
    final client = AppApi(
      server: origin.origin,
      cookies: jar,
      dio: Dio()
        ..httpClientAdapter =
            adapter ?? FakeHttpAdapter((_) async => success()),
      editorWebSession: bridge(),
    );
    client.bootstrap = {
      'user': {'id': 'synthetic-user'},
    };
    addTearDown(client.dispose);
    return client;
  }

  test('cold preparation reads only the encrypted host session and waits for native acknowledgement', () async {
    final namespace = base64Url.encode(utf8.encode(origin.origin));
    final seeded = PersistCookieJar(storage: SecureCookieStorage(namespace));
    await seeded.saveFromResponse(origin, [
      session('synthetic-editor-session'),
      Cookie('app-email-login', 'synthetic-challenge')..path = '/api/app',
      Cookie('reader-workspace', 'synthetic-workspace')..path = '/',
    ]);
    final client = api(
      PersistCookieJar(storage: SecureCookieStorage(namespace)),
    );
    final native = Completer<void>();
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      await native.future;
      return null;
    });
    var ready = false;
    final preparation = client.prepareEditorWebSession().then(
      (_) => ready = true,
    );
    await Future<void>.delayed(Duration.zero);
    expect(ready, isFalse);
    expect(calls.length, 1);
    final arguments = Map<String, dynamic>.from(calls.single.arguments as Map);
    expect(calls.single.method, 'setSession');
    expect(arguments.keys.toSet(), {'origin', 'session'});
    expect(arguments['origin'], origin.origin);
    expect(arguments['session'] == 'synthetic-editor-session', isTrue);
    expect(
      arguments.values.any((value) => value == 'synthetic-challenge'),
      isFalse,
    );
    native.complete();
    await preparation;
    expect(ready, isTrue);
  });

  test('missing, expired, non-HttpOnly, domain and wrong-path cookies never enter the native store', () async {
    for (final invalid in <Cookie?>[
      null,
      session('synthetic-expired')..expires = DateTime.utc(2000),
      session('synthetic-script-readable')..httpOnly = false,
      session('synthetic-domain')..domain = 'akribos.test',
      session('synthetic-path')..path = '/notes',
      session('synthetic-insecure')..secure = false,
    ]) {
      final jar = CookieJar();
      if (invalid != null) await jar.saveFromResponse(origin, [invalid]);
      await expectLater(
        api(jar).prepareEditorWebSession(),
        throwsA(isA<ApiException>()),
      );
      expect((calls.last.arguments as Map).containsKey('session'), isFalse);
    }
  });

  test(
    'a guest bootstrap never transfers an otherwise present session',
    () async {
      final jar = CookieJar();
      await jar.saveFromResponse(origin, [session('synthetic-guest')]);
      final client = api(jar)..bootstrap = {'user': null};
      await expectLater(
        client.prepareEditorWebSession(),
        throwsA(isA<ApiException>()),
      );
      expect((calls.single.arguments as Map).containsKey('session'), isFalse);
    },
  );

  test('native operations serialize across origins and recover after a platform failure without leaking its details', () async {
    final firstNative = Completer<void>();
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (calls.length == 1) {
        await firstNative.future;
        throw PlatformException(
          code: 'failure',
          message: 'synthetic-private-platform-detail',
        );
      }
      return null;
    });
    final first = bridge().setSession(origin, 'synthetic-editor-session');
    final assertion = expectLater(
      first,
      throwsA(
        isA<EditorWebSessionException>().having(
          (error) =>
              error.toString().contains('synthetic-private-platform-detail'),
          'does not expose native details',
          false,
        ),
      ),
    );
    final second = bridge().clear(Uri.parse('https://other.test'));
    await Future<void>.delayed(Duration.zero);
    expect(calls.length, 1);
    firstNative.complete();
    await assertion;
    await second;
    expect(calls.length, 2);
    expect((calls.last.arguments as Map)['origin'], 'https://other.test');
    expect((calls.last.arguments as Map).containsKey('session'), isFalse);
  });

  test('successful login invalidates the old WebView session even if the following bootstrap fails', () async {
    final jar = CookieJar();
    await jar.saveFromResponse(origin, [session('synthetic-old')]);
    final adapter = FakeHttpAdapter((request) async {
      if (request.options.uri.path == '/api/app/action') {
        return jsonResponse(
          {'type': 'redirect', 'status': 303, 'location': '/notes'},
          headers: {
            'set-cookie': ['session=synthetic-new; Path=/; Secure; HttpOnly'],
          },
        );
      }
      return jsonResponse({'type': 'failure', 'status': 503}, status: 503);
    });
    final client = api(jar, adapter: adapter);
    await client.action('/login', 'password', {});
    expect(calls.length, 1);
    expect((calls.single.arguments as Map).containsKey('session'), isFalse);
    await expectLater(client.loadBootstrap(), throwsA(isA<ApiException>()));
    expect(calls.length, 1);
  });

  test('bootstrap identity changes clear the native store but ordinary refreshes do not', () async {
    var owner = 'synthetic-first';
    final client = api(
      CookieJar(),
      adapter: FakeHttpAdapter(
        (_) async => success({
          'protocolVersion': 1,
          'user': {'id': owner},
        }),
      ),
    );
    await client.loadBootstrap();
    calls.clear();
    await client.loadBootstrap();
    expect(calls, isEmpty);
    owner = 'synthetic-second';
    await client.loadBootstrap();
    expect(calls.length, 1);
    expect((calls.single.arguments as Map).containsKey('session'), isFalse);
  });

  test(
    'logout clears the encrypted jar even if native cleanup fails',
    () async {
      final jar = CookieJar();
      await jar.saveFromResponse(origin, [session('synthetic-editor-session')]);
      final client = api(jar);
      messenger.setMockMethodCallHandler(channel, (_) async {
        throw PlatformException(code: 'failure');
      });
      await expectLater(
        client.clearSession(),
        throwsA(isA<EditorWebSessionException>()),
      );
      expect(await jar.loadForRequest(origin), isEmpty);
      expect(client.bootstrap, isEmpty);
    },
  );

  test(
    'logout racing preparation cannot release a stale authenticated editor',
    () async {
      final jar = CookieJar();
      await jar.saveFromResponse(origin, [session('synthetic-editor-session')]);
      final client = api(jar);
      final prepared = Completer<void>();
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        if ((call.arguments as Map).containsKey('session')) {
          await prepared.future;
        }
        return null;
      });
      final loading = client.prepareEditorWebSession();
      final rejected = expectLater(loading, throwsA(isA<ApiException>()));
      await Future<void>.delayed(Duration.zero);
      final logout = client.clearSession();
      prepared.complete();
      await rejected;
      await logout;
      expect((calls.last.arguments as Map).containsKey('session'), isFalse);
      expect(await jar.loadForRequest(origin), isEmpty);
    },
  );
  test(
    'native cleanup failure cannot hide a successful authentication boundary',
    () async {
      final jar = CookieJar();
      await jar.saveFromResponse(origin, [session('synthetic-old')]);
      final client = api(
        jar,
        adapter: FakeHttpAdapter((request) async {
          if (request.options.uri.path == '/api/app/action') {
            return jsonResponse(
              {'type': 'redirect', 'status': 303, 'location': '/notes'},
              headers: {
                'set-cookie': [
                  'session=synthetic-new; Path=/; Secure; HttpOnly',
                ],
              },
            );
          }
          return success({
            'protocolVersion': 1,
            'user': {'id': 'synthetic-new-user'},
          });
        }),
      );
      messenger.setMockMethodCallHandler(channel, (_) async {
        throw PlatformException(code: 'unavailable');
      });
      expect(
        (await client.action('/login', 'password', {})).isRedirect,
        isTrue,
      );
      expect(
        asMap((await client.loadBootstrap())['user'])['id'],
        'synthetic-new-user',
      );
      await expectLater(
        client.prepareEditorWebSession(),
        throwsA(isA<EditorWebSessionException>()),
      );
    },
  );
  test('opening another document in the same prepared session retains native web caches', () async {
    await bridge().setSession(origin, 'synthetic-repeat');
    await bridge().setSession(origin, 'synthetic-repeat');
    expect(calls.length, 1);
    await bridge().setSession(origin, 'synthetic-changed');
    expect(calls.length, 2);
    await bridge().setSession(
      Uri.parse('https://other.test'),
      'synthetic-changed',
    );
    expect(calls.length, 3);
    await bridge().setSession(origin, 'synthetic-repeat');
    expect(calls.length, 4);
  });

  test('every explicit clear executes and the same session must prepare again after logout', () async {
    final client = bridge();
    await client.setSession(origin, 'synthetic-repeat');
    await client.clear(origin);
    await client.clear(origin);
    await client.setSession(origin, 'synthetic-repeat');
    expect(calls.length, 4);
    expect((calls[1].arguments as Map).containsKey('session'), isFalse);
    expect((calls[2].arguments as Map).containsKey('session'), isFalse);
    expect((calls.last.arguments as Map).containsKey('session'), isTrue);
  });

  test('failed replacement discards the previous prepared binding instead of reusing stale cookies', () async {
    final client = bridge();
    await client.setSession(origin, 'synthetic-first');
    var fail = true;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (fail) throw PlatformException(code: 'unavailable');
      return null;
    });
    await expectLater(
      client.setSession(origin, 'synthetic-second'),
      throwsA(isA<EditorWebSessionException>()),
    );
    fail = false;
    await client.setSession(origin, 'synthetic-first');
    expect(calls.length, 3);
    await client.setSession(origin, 'synthetic-first');
    expect(calls.length, 3);
  });
}
