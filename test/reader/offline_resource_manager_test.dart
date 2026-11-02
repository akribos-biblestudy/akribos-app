import 'dart:async';
import 'dart:io';

import 'package:akribos_app/core/api_client.dart';
import 'package:akribos_app/features/reader/offline_resource_manager.dart';
import 'package:flutter_test/flutter_test.dart';

import 'offline_resource_store_test.dart' show MemoryKeys;

class FakeApi extends AppApi {
  FakeApi({String origin = 'https://example.test'}) : super(server: origin);
  Future<dynamic> Function(String path)? handler;
  Future<dynamic> Function(String path)? lexiconHandler;
  @override
  Future<dynamic> get(String path) {
    if (path.startsWith('/api/app/offline/v2/lexicons')) {
      if (lexiconHandler == null) {
        throw const ApiException('Nicht verfügbar', status: 404);
      }
      return lexiconHandler!(path);
    }
    return handler!(path);
  }
}

Map<String, dynamic> catalog(String? owner, List<String> ids) => {
  'version': 1,
  'owner': owner,
  'resources': [
    for (final id in ids) {'id': id, 'kind': 'bible'},
  ],
};
Map<String, dynamic> package(String? owner, String id) => {
  'version': 1,
  'owner': owner,
  'resource': {'id': id, 'kind': 'bible'},
  'chapters': [
    {'resourceId': id},
  ],
};
Map<String, dynamic> lexiconCatalog(String? owner, List<String> ids) => {
  'version': 2,
  'owner': owner,
  'resources': [
    for (final id in ids) {'id': id, 'kind': 'lexicon'},
  ],
};
Map<String, dynamic> lexiconPackage(String? owner, String id) => {
  'version': 2,
  'owner': owner,
  'resource': {'id': id, 'kind': 'lexicon', 'name': 'Lexikon'},
  'entries': [
    {
      'strong': 'G26',
      'language': 'grc',
      'lemma': 'ἀγάπη',
      'transliteration': 'agape',
      'definitionHtml': '<p>Liebe</p>',
      'seeAlso': <String>[],
    },
  ],
};

void main() {
  late Directory dir;
  late MemoryKeys keys;
  late FakeApi api;
  late OfflineResourceManager manager;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('akribos-manager-test');
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
  tearDown(() async => dir.delete(recursive: true));

  test('downloads licensed package and deletes revoked resources after a valid online catalog', () async {
    var allowed = ['a', 'b'];
    api.handler = (path) async => path == '/api/app/offline/resources'
        ? catalog('one', allowed)
        : package('one', path.split('/').last);
    await manager.download('a');
    await manager.download('b');
    expect(await manager.store.ids(), ['a', 'b']);
    allowed = ['b'];
    expect((await manager.reconcile()).map((r) => r['id']), ['b']);
    expect(await manager.store.read('a'), isNull);
    expect(await manager.store.read('b'), isNotNull);
    await manager.remove('b');
    expect(await manager.store.ids(), isEmpty);
  });

  test('does not delete cached data when network, account or catalog validation fails', () async {
    await manager.store.write(package('one', 'a'));
    api.handler = (_) async => throw const ApiException('offline');
    await expectLater(manager.reconcile(), throwsA(isA<ApiException>()));
    api.handler = (_) async => catalog('other', []);
    await expectLater(manager.reconcile(), throwsA(isA<ApiException>()));
    api.handler = (_) async => {
      'version': 1,
      'owner': 'one',
      'resources': [
        {'id': 'b', 'kind': 'bible'},
        {'id': 'b', 'kind': 'bible'},
      ],
    };
    await expectLater(manager.reconcile(), throwsFormatException);
    expect(await manager.store.read('a'), isNotNull);
  });

  test('rejects mismatched and unauthorized packages without replacing an existing one', () async {
    await manager.store.write(package('one', 'a'));
    api.handler = (path) async => path == '/api/app/offline/resources'
        ? catalog('one', ['a'])
        : package('other', 'a');
    await expectLater(manager.download('a'), throwsA(isA<ApiException>()));
    api.handler = (path) async => path == '/api/app/offline/resources'
        ? catalog('one', ['a'])
        : package('one', 'b');
    await expectLater(manager.download('a'), throwsFormatException);
    await expectLater(manager.download('b'), throwsA(isA<ApiException>()));
    expect(await manager.store.read('a'), package('one', 'a'));
    expect(await manager.store.read('b'), isNull);
  });

  test(
    'account change while catalog is in flight prevents storing or deleting',
    () async {
      await manager.store.write(package('one', 'a'));
      final pending = Completer<dynamic>();
      api.handler = (_) => pending.future;
      final future = manager.reconcile();
      await Future<void>.delayed(Duration.zero);
      api.bootstrap = {
        'user': {'id': 'two'},
      };
      pending.complete(catalog('one', []));
      await expectLater(future, throwsA(isA<ApiException>()));
      expect(await manager.store.read('a'), isNotNull);
    },
  );

  test(
    'downloads and revokes a lexicon only after both catalogs are validated',
    () async {
      api.handler = (_) async => catalog('one', ['bible']);
      var allowed = ['lex'];
      api.lexiconHandler = (path) async =>
          path == '/api/app/offline/v2/lexicons'
          ? lexiconCatalog('one', allowed)
          : lexiconPackage('one', 'lex');
      await manager.download('lex');
      expect(await manager.store.read('lex'), lexiconPackage('one', 'lex'));
      api.lexiconHandler = (_) async =>
          throw const ApiException('Verbindung fehlt', connectionFailure: true);
      await expectLater(manager.reconcile(), throwsA(isA<ApiException>()));
      expect(await manager.store.read('lex'), isNotNull);
      api.lexiconHandler = null;
      await expectLater(manager.reconcile(), throwsA(isA<ApiException>()));
      expect(await manager.store.read('lex'), isNotNull);
      allowed = [];
      api.lexiconHandler = (_) async => lexiconCatalog('one', allowed);
      await manager.reconcile();
      expect(await manager.store.read('lex'), isNull);
    },
  );

  test(
    'rejects a lexicon with an incorrect owner or invalid entries',
    () async {
      api.handler = (_) async => catalog('one', []);
      api.lexiconHandler = (path) async =>
          path == '/api/app/offline/v2/lexicons'
          ? lexiconCatalog('one', ['lex'])
          : lexiconPackage('other', 'lex');
      await expectLater(manager.download('lex'), throwsA(isA<ApiException>()));
      api.lexiconHandler = (path) async {
        if (path == '/api/app/offline/v2/lexicons') {
          return lexiconCatalog('one', ['lex']);
        }
        final invalid = lexiconPackage('one', 'lex');
        (invalid['entries'] as List).add({
          'strong': 'G26',
          'language': 'grc',
          'lemma': 'duplicate',
          'seeAlso': [],
        });
        return invalid;
      };
      await expectLater(manager.download('lex'), throwsFormatException);
      expect(await manager.store.ids(), isEmpty);
      api.lexiconHandler = (_) async => lexiconCatalog('other', []);
      await expectLater(manager.reconcile(), throwsA(isA<ApiException>()));
    },
  );

  test('constructs origin and account isolated storage scopes', () async {
    await manager.store.write(package('one', 'a'));
    final otherApi = FakeApi(origin: 'https://other.test')
      ..bootstrap = {
        'user': {'id': 'one'},
      };
    final otherOrigin = OfflineResourceManager(
      api: otherApi,
      userId: 'one',
      storage: keys,
      directory: () async => dir,
    );
    final guest = OfflineResourceManager(
      api: api,
      userId: null,
      storage: keys,
      directory: () async => dir,
    );
    expect(await otherOrigin.store.read('a'), isNull);
    expect(await guest.store.read('a'), isNull);
  });

  test(
    'requires a confirmed guest session and rejects unsafe resource IDs',
    () async {
      final guestApi = FakeApi();
      final guest = OfflineResourceManager(
        api: guestApi,
        userId: null,
        storage: keys,
        directory: () async => dir,
      );
      guestApi.handler = (_) async => catalog(null, ['a']);
      await expectLater(guest.catalog(), throwsA(isA<ApiException>()));
      guestApi.bootstrap = {'user': null};
      expect((await guest.catalog()).single['id'], 'a');
      for (final bad in ['.', '..', 'a/b', r'a\b']) {
        guestApi.handler = (_) async => catalog(null, [bad]);
        await expectLater(guest.catalog(), throwsFormatException);
      }
    },
  );
}
