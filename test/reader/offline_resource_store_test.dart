import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:akribos_app/features/reader/offline_resource_store.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

class MemoryKeys extends FlutterSecureStorage {
  final values = <String, String>{};
  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => values[key];
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
    values[key] = value!;
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    values.remove(key);
  }
}

class PausedKeys extends MemoryKeys {
  final started = Completer<void>();
  final release = Completer<void>();

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
    if (key.startsWith('akribos.offline.position.v1.') &&
        !started.isCompleted) {
      started.complete();
      await release.future;
    }
    await super.write(key: key, value: value);
  }
}

void main() {
  late Directory dir;
  late MemoryKeys keys;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('akribos-offline-test');
    keys = MemoryKeys();
  });
  tearDown(() async {
    await dir.delete(recursive: true);
  });
  OfflineResourceStore store({
    String? user = 'one',
    String server = 'https://example.test',
  }) => OfflineResourceStore(
    origin: Uri.parse(server),
    userId: user,
    storage: keys,
    directory: () async => dir,
  );
  Map<String, dynamic> package(
    String id, {
    String? user = 'one',
    String text = 'private text',
  }) => {
    'version': 1,
    'owner': user,
    'resource': {'id': id},
    'chapters': [
      {'text': text},
    ],
  };

  test(
    'encrypts packages and isolates account and origin across restarts',
    () async {
      await store().write(package('book'));
      final file = await dir
          .list(recursive: true)
          .where((e) => e is File)
          .cast<File>()
          .single;
      expect(await file.readAsString(), isNot(contains('private text')));
      expect(await store().read('book'), package('book'));
      expect(await store(user: 'two').read('book'), isNull);
      expect(await store(user: null).read('book'), isNull);
      expect(await store(server: 'https://other.test').read('book'), isNull);
      await expectLater(
        store(user: 'two').write(package('book')),
        throwsFormatException,
      );
    },
  );

  test(
    'stores and reads a package larger than the previous 32 MiB limit',
    () async {
      final text = 'x' * (32 * 1024 * 1024 + 1);
      await store().write(package('large', text: text));
      final restored = await store().read('large');
      expect((restored!['chapters'] as List).single['text'], text);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'authenticates ciphertext and refuses swapping a different resource',
    () async {
      await store().write(package('a'));
      await store().write(package('b'));
      final files = await dir
          .list(recursive: true)
          .where((e) => e is File)
          .cast<File>()
          .toList();
      await files[0].writeAsString(await files[1].readAsString());
      final failures = <bool>[];
      for (final id in ['a', 'b']) {
        try {
          await store().read(id);
          failures.add(false);
        } catch (_) {
          failures.add(true);
        }
      }
      expect(failures.where((v) => v), hasLength(1));
    },
  );

  test(
    'serial writes preserve the last requested value and deletion',
    () async {
      await Future.wait([
        store().write(package('a', text: 'old')),
        store().write(package('a', text: 'new')),
      ]);
      expect(jsonEncode(await store().read('a')), contains('new'));
      await store().remove('a');
      expect(await store().read('a'), isNull);
      await store().write(package('b'));
      await store().clear();
      expect(await store().read('b'), isNull);
      expect(keys.values, isEmpty);
    },
  );

  for (final clear in [false, true]) {
    test(
      'blocked old position cannot survive ${clear ? 'logout' : 'revocation'}',
      () async {
        final paused = PausedKeys();
        keys = paused;
        addTearDown(() {
          if (!paused.release.isCompleted) paused.release.complete();
        });
        final resourceStore = store();
        await resourceStore.write(package('a'));
        final oldWrite = resourceStore.writePosition('a', {
          'book': 1,
          'chapter': 1,
        });
        await paused.started.future;
        if (clear) {
          await resourceStore.clear().timeout(const Duration(seconds: 2));
        } else {
          await resourceStore.remove('a').timeout(const Duration(seconds: 2));
        }
        final newWrite = clear
            ? null
            : resourceStore.writePosition('b', {'book': 2, 'chapter': 3});
        paused.release.complete();
        await oldWrite;
        if (newWrite != null) await newWrite;
        final position = await resourceStore.readPosition();
        if (clear) {
          expect(position, isNull);
        } else {
          expect(position?['resourceId'], 'b');
          expect(position?['reference'], {'book': 2, 'chapter': 3});
        }
      },
    );
  }

  test(
    'offline identity is isolated by origin and distinguishes guests',
    () async {
      final first = OfflineIdentityStore(
        origin: Uri.parse('https://example.test'),
        storage: keys,
      );
      final other = OfflineIdentityStore(
        origin: Uri.parse('https://other.test'),
        storage: keys,
      );
      expect(await first.read(), isNull);
      await first.write(null, null);
      expect((await first.read())?['owner'], isNull);
      expect(await other.read(), isNull);
      await first.write('reader', 'session-digest');
      expect((await first.read())?['fingerprint'], 'session-digest');
      await first.clear();
      expect(await first.read(), isNull);
    },
  );
}
