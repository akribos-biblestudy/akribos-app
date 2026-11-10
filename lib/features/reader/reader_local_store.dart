import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/api_client.dart';
import 'reader_state.dart';
import 'reader_companion.dart';

/// Stores only navigation state, never Bible text, cookies or server workspace IDs.
/// Secure storage remains on this installation; every origin/account has its own key.
class ReaderLocalStore {
  ReaderLocalStore({
    required Uri origin,
    required this.userId,
    FlutterSecureStorage? storage,
  }) : scopeKey = base64Url.encode(
         utf8.encode(
           jsonEncode([
             origin.origin,
             userId == null ? ['guest'] : ['account', userId],
           ]),
         ),
       ),
       _storage = storage ?? const FlutterSecureStorage();

  final String? userId;
  final String scopeKey;
  final FlutterSecureStorage _storage;
  static final _writes = <String, Future<void>>{};
  String get storageKey => 'akribos.reader.local.v1.$scopeKey';

  bool acceptsUser(dynamic user) =>
      (asString(asMap(user)['id']).isEmpty
          ? null
          : asString(asMap(user)['id'])) ==
      userId;

  Future<Json?> read() async {
    await _writes[storageKey];
    final value = await _storage.read(key: storageKey);
    if (value == null) return null;
    try {
      final snapshot = asMap(jsonDecode(value));
      final path = asString(snapshot['path']);
      if (snapshot['version'] != 1 || !_validPath(path)) {
        throw const FormatException();
      }
      return {
        'path': localReaderAddress(path),
        'updatedAt': snapshot['updatedAt'],
        'layoutSizes': asMap(snapshot['layoutSizes']),
        'versePerLine': snapshot['versePerLine'] == true,
        'companion': ReaderCompanion.fromJson(snapshot['companion']).toJson(),
      };
    } catch (_) {
      throw const ApiException(
        'Die lokal gespeicherten Tabs konnten nicht gelesen werden.',
      );
    }
  }

  Future<void> write(
    String path, {
    Json layoutSizes = const {},
    bool versePerLine = false,
    ReaderCompanion companion = const ReaderCompanion(),
    void Function()? validate,
  }) {
    if (!_validPath(path)) {
      throw const ApiException(
        'Die lokalen Tabs enthalten keine gültige Reader-Adresse.',
      );
    }
    // Freeze the value before waiting: a later scroll must not mutate this write.
    final value = jsonEncode({
      'version': 1,
      'updatedAt': DateTime.now().microsecondsSinceEpoch,
      'path': localReaderAddress(path),
      'layoutSizes': layoutSizes,
      'versePerLine': versePerLine,
      'companion': companion.toJson(),
    });
    final prior = _writes[storageKey];
    final task = () async {
      try {
        await prior;
      } catch (_) {
        // A successful retry replaces only this account's previous snapshot.
      }
      validate?.call();
      final previous = validate == null
          ? null
          : await _storage.read(key: storageKey);
      validate?.call();
      await _storage.write(key: storageKey, value: value);
      try {
        validate?.call();
      } catch (_) {
        if (previous == null) {
          await _storage.delete(key: storageKey);
        } else {
          await _storage.write(key: storageKey, value: previous);
        }
        rethrow;
      }
    }();
    _writes[storageKey] = task;
    // Keep only pending writes; read errors remain visible to the caller.
    task.then(
      (_) {
        if (identical(_writes[storageKey], task)) _writes.remove(storageKey);
      },
      onError: (Object _, StackTrace _) {
        if (identical(_writes[storageKey], task)) _writes.remove(storageKey);
      },
    );
    return task;
  }

  static bool _validPath(String path) {
    final uri = Uri.tryParse(path);
    return path.length <= 1000000 &&
        path.startsWith('/') &&
        !path.startsWith('//') &&
        !path.contains('\\') &&
        uri != null &&
        !uri.hasScheme &&
        !uri.hasAuthority &&
        uri.queryParameters.containsKey('layout');
  }
}

/// Ordinary passage links keep this device's tabs; explicit Reader snapshots are
/// deliberately opened as a new local view. Neither path carries server versions.
String localReaderStartPath(String requested, Json? saved, Json bootstrap) {
  final target = Uri.parse(requested);
  if (target.queryParameters.containsKey('layout')) {
    return localReaderAddress(requested);
  }
  final stored = asString(saved?['path']);
  if (stored.isNotEmpty) {
    final source = Uri.parse(stored);
    return localReaderAddress(
      target.path.isEmpty || target.path == '/'
          ? stored
          : '${target.path}?${source.query}',
    );
  }
  final resources = asMaps(bootstrap['readerResources']);
  final bible =
      resources.where((item) => item['kind'] == 'bible').firstOrNull ??
      asMaps(bootstrap['bibles']).firstOrNull;
  final path = target.path.isEmpty || target.path == '/'
      ? '/Joh1'
      : target.path;
  final resource = asString(bible?['id']);
  return '$path?layout=single${resource.isEmpty ? '' : '&tab=1.1:${Uri.encodeComponent(resource)}:A:Joh1&active=1.1'}&focus=1';
}
