import 'dart:async';

import 'package:akribos_app/core/app_updates.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';

const _android = InstalledAppInfo(
  version: '0.5.0',
  build: '17',
  packageName: 'de.akribos.app',
  platform: 'android',
);
const _ios = InstalledAppInfo(
  version: '0.5.0',
  build: '17',
  packageName: 'de.akribos.app',
  platform: 'ios',
  storeCountry: 'DE',
  osVersion: '18.5',
);

class _Gateway implements AppUpdateGateway {
  int checks = 0;
  bool fails = false;
  bool closed = false;
  Completer<StoreCheckResult>? pending;
  StoreCheckResult result = const StoreCheckResult(
    status: StoreUpdateStatus.available,
    update: StoreUpdate(build: '18'),
  );
  @override
  Future<InstalledAppInfo> info() async => _android;
  @override
  Future<StoreCheckResult> check(InstalledAppInfo installed) async {
    checks++;
    if (fails) throw StateError('Offline');
    return pending == null ? result : pending!.future;
  }

  @override
  Future<bool> openStore(
    InstalledAppInfo installed,
    StoreUpdate update,
  ) async => true;
  @override
  void dispose() => closed = true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('de.akribos.app/updates');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('store versions compare numerically with omitted zero components', () {
    expect(compareStoreVersions('0.10.0', '0.9.9'), greaterThan(0));
    expect(compareStoreVersions('1.2', '1.2.0'), 0);
    expect(compareStoreVersions('1.2.0', '1.2.1'), lessThan(0));
    expect(compareStoreVersions('1.2-beta', '1.2'), isNull);
    expect(compareStoreVersions('garbage', '1'), isNull);
  });

  test('installed metadata comes from the platform; missing metadata is not invented', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (call) async => {
        'version': '2.7.1',
        'build': '83',
        'packageName': 'de.akribos.app',
        'platform': 'android',
        'storeInstallation': true,
      },
    );
    final gateway = PlatformAppUpdateGateway();
    addTearDown(gateway.dispose);
    final info = await gateway.info();
    expect(info.version, '2.7.1');
    expect(info.build, '83');
    messenger.setMockMethodCallHandler(
      channel,
      (call) async => {'platform': 'android'},
    );
    await expectLater(gateway.info(), throwsFormatException);
  });

  testWidgets('disposing a gateway cancels pending platform deadlines', (
    tester,
  ) async {
    final pending = Completer<Object?>();
    messenger.setMockMethodCallHandler(channel, (call) => pending.future);
    final gateway = PlatformAppUpdateGateway();
    final result = expectLater(gateway.info(), throwsStateError);
    gateway.dispose();
    await result;
    pending.complete(null);
    await tester.pump();
  });

  test('Play eligibility and errors stay distinct from no update', () async {
    var response = <String, dynamic>{'status': 'available', 'build': '18'};
    var fail = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (fail) throw PlatformException(code: 'store_check');
      return response;
    });
    final gateway = PlatformAppUpdateGateway();
    addTearDown(gateway.dispose);
    expect((await gateway.check(_android)).update?.build, '18');
    response = {'status': 'current'};
    expect((await gateway.check(_android)).status, StoreUpdateStatus.current);
    response = {'status': 'unavailable'};
    expect(
      (await gateway.check(_android)).status,
      StoreUpdateStatus.unavailable,
    );
    response = {'status': 'available', 'build': '17'};
    await expectLater(gateway.check(_android), throwsFormatException);
    fail = true;
    await expectLater(
      gateway.check(_android),
      throwsA(isA<PlatformException>()),
    );
  });

  test('checks coalesce, throttle resumes and permit explicit retry', () async {
    final gateway = _Gateway()..pending = Completer<StoreCheckResult>();
    var now = DateTime(2026, 10, 17);
    final controller = AppUpdateController(gateway: gateway, now: () => now);
    addTearDown(controller.dispose);
    final initial = controller.initialize();
    await Future<void>.delayed(Duration.zero);
    final concurrent = controller.check(force: true);
    gateway.pending!.complete(gateway.result);
    await Future.wait([initial, concurrent]);
    gateway.pending = null;
    expect(gateway.checks, 1);
    expect(controller.installed?.build, '17');
    await controller.check();
    expect(gateway.checks, 1);
    await controller.check(force: true);
    expect(gateway.checks, 2);
    now = now.add(AppUpdateController.checkInterval);
    await controller.check();
    expect(gateway.checks, 3);
  });

  test(
    'dismissal survives restart, expires and does not hide a newer update',
    () async {
      var now = DateTime(2026, 10, 17);
      final first = AppUpdateController(gateway: _Gateway(), now: () => now);
      await first.initialize();
      expect(first.showNotice, isTrue);
      await first.dismiss();
      expect(first.showNotice, isFalse);
      first.dispose();
      final gateway = _Gateway();
      final restored = AppUpdateController(gateway: gateway, now: () => now);
      addTearDown(restored.dispose);
      await restored.initialize();
      expect(restored.showNotice, isFalse);
      now = now.add(AppUpdateController.remindInterval);
      await restored.check();
      expect(restored.showNotice, isTrue);
      await restored.dismiss();
      gateway.result = const StoreCheckResult(
        status: StoreUpdateStatus.available,
        update: StoreUpdate(build: '19'),
      );
      await restored.check(force: true);
      expect(restored.showNotice, isTrue);
    },
  );

  test(
    'network failure never claims current and resumes retry after backoff',
    () async {
      final gateway = _Gateway()..fails = true;
      var now = DateTime(2026, 10, 17);
      final controller = AppUpdateController(gateway: gateway, now: () => now);
      addTearDown(controller.dispose);
      await controller.initialize();
      expect(controller.status, StoreUpdateStatus.failed);
      expect(controller.installed?.version, '0.5.0');
      expect(controller.showNotice, isFalse);
      expect(controller.errorMessage, isNotEmpty);
      gateway.fails = false;
      now = now.add(AppUpdateController.retryInterval);
      await controller.check();
      expect(controller.status, StoreUpdateStatus.available);
    },
  );

  test(
    'late responses after disposal do not notify or open the store',
    () async {
      final gateway = _Gateway()..pending = Completer<StoreCheckResult>();
      final controller = AppUpdateController(gateway: gateway);
      var changes = 0;
      controller.addListener(() => changes++);
      final initial = controller.initialize();
      await Future<void>.delayed(Duration.zero);
      controller.dispose();
      final before = changes;
      gateway.pending!.complete(gateway.result);
      await initial;
      expect(changes, before);
      expect(gateway.closed, isTrue);
      expect(await controller.openStore(), isFalse);
    },
  );

  Map<String, Object> listing({
    String version = '0.6.0',
    String minimumOs = '15.0',
  }) => {
    'bundleId': 'de.akribos.app',
    'wrapperType': 'software',
    'version': version,
    'trackId': 123456,
    'minimumOsVersion': minimumOs,
    'trackViewUrl': 'https://untrusted.example/never-follow',
  };

  test(
    'Apple lookup uses actual storefront and no Akribos credentials',
    () async {
      final adapter = FakeHttpAdapter(
        (_) async => jsonResponse({
          'results': [listing()],
        }),
      );
      final dio = Dio()..httpClientAdapter = adapter;
      addTearDown(dio.close);
      Uri? opened;
      final gateway = PlatformAppUpdateGateway(
        storeClient: dio,
        launcher: (uri) async {
          opened = uri;
          return true;
        },
      );
      final result = await gateway.check(_ios);
      expect(result.status, StoreUpdateStatus.available);
      final request = adapter.requests.single.options;
      expect(request.uri.host, 'itunes.apple.com');
      expect(request.uri.queryParameters['country'], 'de');
      expect(request.uri.queryParameters['bundleId'], 'de.akribos.app');
      expect(
        request.headers.keys.map((key) => key.toLowerCase()),
        isNot(contains(anyOf('cookie', 'authorization', 'x-akribos-app'))),
      );
      expect(request.followRedirects, isFalse);
      expect(await gateway.openStore(_ios, result.update!), isTrue);
      expect(opened.toString(), 'https://apps.apple.com/de/app/id123456');
      expect(
        await gateway.openStore(
          _ios,
          StoreUpdate(storeUri: Uri.parse('https://evil.test/id1')),
        ),
        isFalse,
      );
    },
  );

  test(
    'Apple missing listing or country never means the installed app is current',
    () async {
      final adapter = FakeHttpAdapter(
        (_) async => jsonResponse({'results': []}),
      );
      final dio = Dio()..httpClientAdapter = adapter;
      addTearDown(dio.close);
      final gateway = PlatformAppUpdateGateway(storeClient: dio);
      expect((await gateway.check(_ios)).status, StoreUpdateStatus.unavailable);
      messenger.setMockMethodCallHandler(channel, (call) async => null);
      const unknownCountry = InstalledAppInfo(
        version: '0.5.0',
        build: '17',
        packageName: 'de.akribos.app',
        platform: 'ios',
      );
      expect(
        (await gateway.check(unknownCountry)).status,
        StoreUpdateStatus.unavailable,
      );
      expect(adapter.requests, hasLength(1));
    },
  );

  test('Apple matches exact identity and rejects malformed versions and unsupported OS', () async {
    var entries = [listing()..['bundleId'] = 'another.app'];
    final adapter = FakeHttpAdapter(
      (_) async => jsonResponse({'results': entries}),
    );
    final dio = Dio()..httpClientAdapter = adapter;
    addTearDown(dio.close);
    final gateway = PlatformAppUpdateGateway(storeClient: dio);
    expect((await gateway.check(_ios)).status, StoreUpdateStatus.unavailable);
    entries = [listing(version: '0.4.0')];
    expect((await gateway.check(_ios)).status, StoreUpdateStatus.current);
    entries = [listing(version: 'bad')];
    await expectLater(gateway.check(_ios), throwsFormatException);
    entries = [listing(minimumOs: '26.0')];
    expect((await gateway.check(_ios)).status, StoreUpdateStatus.unavailable);
  });

  test('known sideload and TestFlight installations perform no public-store lookup', () async {
    final adapter = FakeHttpAdapter(
      (_) async => throw StateError('Must not call store'),
    );
    final dio = Dio()..httpClientAdapter = adapter;
    addTearDown(dio.close);
    final gateway = PlatformAppUpdateGateway(storeClient: dio);
    for (final platform in ['android', 'ios']) {
      final info = InstalledAppInfo(
        version: '0.5.0',
        build: '17',
        packageName: 'de.akribos.app',
        platform: platform,
        storeInstallation: false,
      );
      expect((await gateway.check(info)).status, StoreUpdateStatus.unavailable);
    }
    expect(adapter.requests, isEmpty);
  });
}
