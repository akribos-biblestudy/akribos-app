import 'dart:async';
import 'dart:convert';

import 'package:akribos_app/core/api_client.dart';
import 'package:akribos_app/features/reader/reader_local_store.dart';
import 'package:akribos_app/features/reader/reader_companion.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

class ControlledStorage extends FlutterSecureStorage {
  final values = <String, String>{};
  final calls = <String>[];
  Completer<void>? pause;
  bool fail = false;
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
    calls.add(value!);
    await pause?.future;
    if (fail) throw const ApiException('Lokaler Speicher nicht verfügbar');
    values[key] = value;
  }

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
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const first = '/Joh1?layout=single&tab=1.1:BIBLE:A:Joh1&active=1.1&focus=1';
  const second =
      '/Joh3,16?layout=single&tab=1.1:BIBLE:A:Joh3,16&active=1.1&focus=1&search=1.1:Liebe';
  ReaderLocalStore store(
    FlutterSecureStorage storage, {
    String? user = 'reader',
    String server = 'https://akribos.de',
  }) => ReaderLocalStore(
    origin: Uri.parse(server),
    userId: user,
    storage: storage,
  );

  test(
    'fresh app instances restore only this origin and account on this device',
    () async {
      final storage = ControlledStorage();
      final sizes = <String, dynamic>{
        'single': {
          'columns': [1.0],
        },
      };
      await store(storage).write(second, layoutSizes: sizes);
      expect(await store(storage).read(), {
        'path': second,
        'layoutSizes': sizes,
        'versePerLine': false,
        'companion': const ReaderCompanion().toJson(),
      });
      expect(await store(storage, user: 'another').read(), isNull);
      expect(await store(storage, user: null).read(), isNull);
      expect(
        await store(storage, server: 'https://other.example').read(),
        isNull,
      );
      expect(await store(ControlledStorage()).read(), isNull);
      expect(
        storage.values.keys.single,
        startsWith('akribos.reader.local.v1.'),
      );
    },
  );

  test(
    'missing display preference defaults to flow and explicit choices restore',
    () async {
      final storage = ControlledStorage();
      final target = store(storage);
      storage.values[target.storageKey] = jsonEncode({
        'version': 1,
        'path': first,
      });
      expect((await target.read())?['versePerLine'], isFalse);
      await target.write(first, versePerLine: true);
      expect((await store(storage).read())?['versePerLine'], isTrue);
      await target.write(second, versePerLine: false);
      expect((await store(storage).read())?['versePerLine'], isFalse);
      expect(await store(storage, user: 'another').read(), isNull);
    },
  );

  test(
    'writes from different instances are serialized and freeze their snapshot',
    () async {
      final storage = ControlledStorage()..pause = Completer<void>();
      final sizes = <String, dynamic>{
        'single': {
          'columns': [1.0],
        },
      };
      final old = store(storage).write(first, layoutSizes: sizes);
      await Future<void>.delayed(Duration.zero);
      final recent = store(storage).write(second);
      sizes.clear();
      var readCompleted = false;
      final read = store(storage).read().then((value) {
        readCompleted = true;
        return value;
      });
      await Future<void>.delayed(Duration.zero);
      expect(storage.calls.length, 1);
      expect(readCompleted, isFalse);
      storage.pause!.complete();
      await Future.wait([old, recent]);
      expect(asMap(jsonDecode(storage.calls.first))['layoutSizes'], isNotEmpty);
      expect((await read)?['path'], second);
    },
  );

  test('companion settings persist only for this origin/account', () async {
    final storage = ControlledStorage();
    const companion = ReaderCompanion(
      enabled: true,
      onLeft: true,
      resourceId: 'COMMENTARY',
    );
    await store(storage).write(second, companion: companion);
    expect((await store(storage).read())?['companion'], companion.toJson());
    expect(await store(storage, user: 'another').read(), isNull);
    expect(await store(storage, server: 'https://other.test').read(), isNull);
    expect(await store(storage, user: null).read(), isNull);
  });

  test('failed persistence stays visible, preserves the prior snapshot and permits retry', () async {
    final storage = ControlledStorage();
    await store(storage).write(first);
    storage.fail = true;
    await expectLater(
      store(storage).write(second),
      throwsA(isA<ApiException>()),
    );
    expect((await store(storage).read())?['path'], first);
    storage.fail = false;
    await store(storage).write(second);
    expect((await store(storage).read())?['path'], second);
  });

  test('corrupt and external snapshots cannot overwrite a valid saved view silently', () async {
    final storage = ControlledStorage();
    final target = store(storage);
    await target.write(first);
    expect(
      () => target.write('https://evil.test/Joh1?layout=single'),
      throwsA(isA<ApiException>()),
    );
    expect(
      () => target.write('//evil.test/Joh1?layout=single'),
      throwsA(isA<ApiException>()),
    );
    expect((await target.read())?['path'], first);
    storage.values[target.storageKey] = '{broken';
    await expectLater(target.read(), throwsA(isA<ApiException>()));
    expect(storage.values[target.storageKey], '{broken');
  });
}
