import 'dart:async';
import 'dart:io';

import 'package:akribos_app/core/api_client.dart';
import 'package:akribos_app/features/reader/offline_resource_manager.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'offline_resource_manager_test.dart' show FakeApi, catalog, package;
import 'offline_resource_store_test.dart' show MemoryKeys;

class PausedIndexKeys extends MemoryKeys {
  final blocked = Completer<void>();
  final resume = Completer<void>();
  bool _pause = true;
  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (_pause && key.startsWith('akribos.offline.index.v1.')) {
      _pause = false;
      blocked.complete();
      await resume.future;
    }
    await super.write(key: key, value: value);
  }
}

void main() {
  late Directory dir;
  late MemoryKeys keys;
  late FakeApi api;
  late OfflineResourceManager manager;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('offline-generation');
    keys = MemoryKeys();
    api = FakeApi()
      ..bootstrap = {
        'user': {'id': 'one'},
      };
    manager = OfflineResourceManager(
      api: api,
      userId: 'one',
      storage: keys,
      directory: () async => dir,
    );
  });
  tearDown(() async {
    api.dispose();
    await dir.delete(recursive: true);
  });

  test(
    'same account after auth boundary cannot accept a delayed package',
    () async {
      final pending = Completer<dynamic>();
      final started = Completer<void>();
      api.handler = (path) {
        if (path == '/api/app/offline/resources') {
          return Future.value(catalog('one', ['a']));
        }
        started.complete();
        return pending.future;
      };
      final download = manager.download('a');
      await started.future;
      api.invalidateOfflineIdentity();
      api.bootstrap = {
        'user': {'id': 'one'},
      };
      pending.complete(package('one', 'a'));
      await expectLater(download, throwsA(isA<ApiException>()));
      expect(await manager.store.ids(), isEmpty);
      final fresh = OfflineResourceManager(
        api: api,
        userId: 'one',
        storage: keys,
        directory: () async => dir,
      );
      api.handler = (path) async => path == '/api/app/offline/resources'
          ? catalog('one', ['a'])
          : package('one', 'a');
      await fresh.download('a');
      expect(await fresh.store.read('a'), package('one', 'a'));
    },
  );

  test('stale download cleanup cannot delete a new session package', () async {
    final paused = PausedIndexKeys();
    final oldManager = OfflineResourceManager(
      api: api,
      userId: 'one',
      storage: paused,
      directory: () async => dir,
    );
    var revision = 'old';
    final newFetched = Completer<void>();
    api.handler = (path) async {
      if (path == '/api/app/offline/resources') return catalog('one', ['a']);
      final data = package('one', 'a')..['revision'] = revision;
      if (revision == 'new') newFetched.complete();
      return data;
    };
    final oldWrite = oldManager.download('a');
    await paused.blocked.future;
    api.invalidateOfflineIdentity();
    revision = 'new';
    final fresh = OfflineResourceManager(
      api: api,
      userId: 'one',
      storage: paused,
      directory: () async => dir,
    );
    final newWrite = fresh.download('a');
    await newFetched.future;
    final rejected = expectLater(oldWrite, throwsA(isA<ApiException>()));
    paused.resume.complete();
    await rejected;
    await newWrite;
    expect((await fresh.store.read('a'))?['revision'], 'new');
    expect(await fresh.store.ids(), ['a']);
  });

  test(
    'same account after auth boundary cannot apply a delayed revocation',
    () async {
      await manager.store.write(package('one', 'a'));
      final pending = Completer<dynamic>();
      final started = Completer<void>();
      api.handler = (_) {
        started.complete();
        return pending.future;
      };
      final reconcile = manager.reconcile();
      await started.future;
      api.invalidateOfflineIdentity();
      api.bootstrap = {
        'user': {'id': 'one'},
      };
      pending.complete(catalog('one', []));
      await expectLater(reconcile, throwsA(isA<ApiException>()));
      expect(await manager.store.read('a'), isNotNull);
    },
  );
}
