import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/api_client.dart';

/// Encrypted packages are scoped to one server and one account (or the guest).
/// This store does not decide whether a resource is licensed for offline use:
/// callers must validate the server's current grant before writing a package.
class OfflineResourceStore {
  OfflineResourceStore({
    required Uri origin,
    required this.userId,
    FlutterSecureStorage? storage,
    Future<Directory> Function()? directory,
  }) : _scope = jsonEncode([
         origin.origin,
         userId == null ? ['guest'] : ['account', userId],
       ]),
       _storage = storage ?? const FlutterSecureStorage(),
       _directory = directory ?? getApplicationSupportDirectory;

  final String? userId;
  final String _scope;
  final FlutterSecureStorage _storage;
  final Future<Directory> Function() _directory;
  static final _operations = <String, Future<void>>{};
  static const maxPackageBytes = 32 * 1024 * 1024;
  final _cipher = AesGcm.with256bits();

  Future<String> _hash(String value) async =>
      (await Sha256().hash(utf8.encode(value))).bytes
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();

  Future<String> get _scopeHash => _hash(_scope);
  Future<Directory> _root() async {
    final base = await _directory();
    final root = Directory('${base.path}/offline-v1/${await _scopeHash}');
    await root.create(recursive: true);
    return root;
  }

  Future<File> _file(String id) async =>
      File('${(await _root()).path}/${await _hash(id)}.package');
  Future<String> get _keyName async =>
      'akribos.offline.key.v1.${await _scopeHash}';
  Future<String> get _indexName async =>
      'akribos.offline.index.v1.${await _scopeHash}';
  Future<String> get _positionName async =>
      'akribos.offline.position.v1.${await _scopeHash}';

  Future<Json?> readPosition() => _serial(() async {
    final raw = await _storage.read(key: await _positionName);
    if (raw == null) return null;
    final value = asMap(jsonDecode(raw));
    if (value['version'] != 1 ||
        value['resourceId'] is! String ||
        value['reference'] is! Map) {
      throw const FormatException('Invalid offline position');
    }
    return value;
  });

  Future<void> writePosition(String resourceId, Json reference) {
    if (resourceId.isEmpty ||
        asInt(reference['book']) < 1 ||
        asInt(reference['chapter']) < 1) {
      throw const FormatException('Invalid offline position');
    }
    final value = jsonEncode({
      'version': 1,
      'resourceId': resourceId,
      'reference': reference,
    });
    return _serial(
      () async => _storage.write(key: await _positionName, value: value),
    );
  }

  Future<List<String>> _ids() async {
    final raw = await _storage.read(key: await _indexName);
    if (raw == null) return [];
    final data = jsonDecode(raw);
    if (data is! List || data.any((item) => item is! String)) {
      throw const FormatException('Invalid offline index');
    }
    return data.cast<String>();
  }

  Future<List<String>> ids() => _serial(_ids);

  Future<SecretKey?> _key({bool create = false}) async {
    final keyName = await _keyName;
    final encoded = await _storage.read(key: keyName);
    if (encoded != null) {
      final bytes = base64Decode(encoded);
      if (bytes.length != 32) {
        throw const FormatException('Invalid offline key');
      }
      return SecretKey(bytes);
    }
    if (!create) return null;
    final key = await _cipher.newSecretKey();
    await _storage.write(
      key: keyName,
      value: base64Encode(await key.extractBytes()),
    );
    return key;
  }

  Future<T> _serial<T>(Future<T> Function() action) async {
    final id = await _scopeHash;
    final previous = _operations[id];
    final completed = Completer<void>();
    _operations[id] = completed.future;
    try {
      try {
        await previous;
      } catch (_) {
        /* Previous failure is reported to its caller. */
      }
      return await action();
    } finally {
      completed.complete();
      if (identical(_operations[id], completed.future)) _operations.remove(id);
    }
  }

  Future<void> write(
    Json package, {
    void Function()? validate,
  }) => _serial(() async {
    validate?.call();
    final resource = asMap(package['resource']);
    final id = asString(resource['id']);
    final supported =
        (package['version'] == 1 && package['chapters'] is List) ||
        (package['version'] == 2 &&
            resource['kind'] == 'lexicon' &&
            package['entries'] is List);
    if (!supported || package['owner'] != userId || id.isEmpty) {
      throw const FormatException('Invalid offline package');
    }
    final bytes = utf8.encode(jsonEncode(package));
    if (bytes.length > maxPackageBytes) {
      throw const FormatException('Offline package too large');
    }
    final key = (await _key(create: true))!;
    final box = await _cipher.encrypt(
      bytes,
      secretKey: key,
      aad: utf8.encode('$_scope\n$id'),
    );
    final file = await _file(id);
    final random = Random.secure();
    final temp = File(
      '${file.path}.${List.generate(16, (_) => random.nextInt(256)).map((b) => b.toRadixString(16).padLeft(2, '0')).join()}.tmp',
    );
    var committed = false;
    try {
      await temp.writeAsString(
        jsonEncode({
          'version': 1,
          'nonce': base64Encode(box.nonce),
          'ciphertext': base64Encode(box.cipherText),
          'mac': base64Encode(box.mac.bytes),
        }),
        flush: true,
      );
      validate?.call();
      await temp.rename(file.path);
      committed = true;
      final ids = await _ids();
      if (!ids.contains(id)) {
        await _storage.write(
          key: await _indexName,
          value: jsonEncode([...ids, id]),
        );
      }
      // The identity can change while file or secure-storage I/O is pending.
      // Remove a stale write while still holding the scope lock, before a new
      // manager is allowed to replace the same package.
      validate?.call();
    } catch (error, stack) {
      var invalid = false;
      try {
        validate?.call();
      } catch (_) {
        invalid = true;
      }
      if (committed && invalid) {
        if (await file.exists()) await file.delete();
        final currentIds = await _ids();
        currentIds.remove(id);
        await _storage.write(
          key: await _indexName,
          value: jsonEncode(currentIds),
        );
      }
      Error.throwWithStackTrace(error, stack);
    } finally {
      if (await temp.exists()) await temp.delete();
    }
  });

  Future<Json?> read(String id) => _serial(() async {
    final file = await _file(id);
    if (!await file.exists()) return null;
    if (await file.length() > (maxPackageBytes * 4 ~/ 3) + 1024) {
      throw const FormatException('Offline package too large');
    }
    final key = await _key();
    if (key == null) throw const FormatException('Offline key missing');
    final envelope = asMap(jsonDecode(await file.readAsString()));
    if (envelope['version'] != 1) {
      throw const FormatException('Invalid offline envelope');
    }
    final box = SecretBox(
      base64Decode(asString(envelope['ciphertext'])),
      nonce: base64Decode(asString(envelope['nonce'])),
      mac: Mac(base64Decode(asString(envelope['mac']))),
    );
    final plaintext = await _cipher.decrypt(
      box,
      secretKey: key,
      aad: utf8.encode('$_scope\n$id'),
    );
    final package = asMap(jsonDecode(utf8.decode(plaintext)));
    final resource = asMap(package['resource']);
    final supported =
        (package['version'] == 1 && package['chapters'] is List) ||
        (package['version'] == 2 &&
            resource['kind'] == 'lexicon' &&
            package['entries'] is List);
    if (!supported || package['owner'] != userId || resource['id'] != id) {
      throw const FormatException('Invalid offline package');
    }
    return package;
  });

  Future<void> remove(String id, {void Function()? validate}) =>
      _serial(() async {
        validate?.call();
        final file = await _file(id);
        validate?.call();
        if (await file.exists()) await file.delete();
        final ids = await _ids();
        ids.remove(id);
        await _storage.write(key: await _indexName, value: jsonEncode(ids));
      });

  Future<void> clear() => _serial(() async {
    final root = await _root();
    if (await root.exists()) await root.delete(recursive: true);
    await _storage.delete(key: await _keyName);
    await _storage.delete(key: await _indexName);
    await _storage.delete(key: await _positionName);
  });
}

/// Last server-confirmed account for a cold start. The marker is removed at an
/// authentication boundary before any new account can use the cached data.
class OfflineIdentityStore {
  OfflineIdentityStore({required this.origin, FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();
  final Uri origin;
  final FlutterSecureStorage _storage;

  Future<String> get _name async {
    final digest = await Sha256().hash(utf8.encode(origin.origin));
    return 'akribos.offline.identity.v1.${digest.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
  }

  Future<void> write(
    String? owner,
    String? fingerprint, {
    int fontScale = 100,
  }) async => _storage.write(
    key: await _name,
    value: jsonEncode({
      'version': 1,
      'owner': owner,
      'fingerprint': fingerprint,
      'fontScale': fontScale,
    }),
  );

  /// Null means no confirmed identity. A guest identity has `owner: null`.
  Future<Json?> read() async {
    final raw = await _storage.read(key: await _name);
    if (raw == null) return null;
    final value = asMap(jsonDecode(raw));
    if (value['version'] != 1 ||
        !value.containsKey('owner') ||
        !value.containsKey('fingerprint') ||
        (value['owner'] != null && value['owner'] is! String) ||
        (value['fingerprint'] != null && value['fingerprint'] is! String) ||
        (value['owner'] != null && value['fingerprint'] == null)) {
      throw const FormatException('Invalid offline identity');
    }
    return value;
  }

  Future<void> clear() async => _storage.delete(key: await _name);
}
