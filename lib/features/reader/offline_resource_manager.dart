import 'dart:async';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/api_client.dart';
import 'offline_resource_store.dart';

/// Manages one origin/account scope. Call [reconcile] on a successful online
/// session refresh, and discard the manager immediately when identity changes.
class OfflineResourceManager {
  OfflineResourceManager({
    required this.api,
    required this.userId,
    FlutterSecureStorage? storage,
    Future<Directory> Function()? directory,
  }) : _identityGeneration = api.offlineIdentityGeneration,
       store = OfflineResourceStore(
         origin: api.origin,
         userId: userId,
         storage: storage,
         directory: directory,
       );

  final AppApi api;
  final String? userId;
  final int _identityGeneration;
  final OfflineResourceStore store;
  Future<void> _tail = Future.value();

  Future<T> _serial<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  bool get isCurrentAccount {
    final id = asString(asMap(api.bootstrap['user'])['id']);
    return api.offlineIdentityGeneration == _identityGeneration &&
        api.bootstrap.containsKey('user') &&
        (id.isEmpty ? null : id) == userId;
  }

  void _checkCurrentAccount() {
    if (!isCurrentAccount) {
      throw const ApiException(
        'Das Konto hat sich geändert. Bitte die Offline-Auswahl erneut öffnen.',
      );
    }
  }

  void _checkOwner(Json response) {
    _checkCurrentAccount();
    if (!response.containsKey('owner') || response['owner'] != userId) {
      throw const ApiException(
        'Die Offline-Antwort gehört nicht zum aktuellen Konto.',
      );
    }
  }

  Future<({List<Json> resources, Object? lexiconError})> _catalog() async {
    _checkCurrentAccount();
    final response = await api.get('/api/app/offline/resources');
    if (response is! Map) {
      throw const FormatException('Invalid offline catalog');
    }
    final data = asMap(response);
    _checkOwner(data);
    if (data['version'] != 1 || data['resources'] is! List) {
      throw const FormatException('Invalid offline catalog');
    }
    final result = <Json>[];
    final seen = <String>{};
    for (final value in data['resources'] as List) {
      if (value is! Map) {
        throw const FormatException('Invalid offline resource');
      }
      final resource = asMap(value);
      final id = resource['id'];
      if (id is! String ||
          id.isEmpty ||
          id == '.' ||
          id == '..' ||
          id.contains('/') ||
          id.contains('\\') ||
          !seen.add(id) ||
          !['bible', 'commentary', 'xrefs'].contains(resource['kind'])) {
        throw const FormatException('Invalid offline resource');
      }
      result.add(resource);
    }
    Object? lexiconError;
    try {
      final lexiconResources = <Json>[];
      final rawLexicons = await api.get('/api/app/offline/v2/lexicons');
      if (rawLexicons is! Map) {
        throw const FormatException('Invalid offline lexicon catalog');
      }
      final lexicons = asMap(rawLexicons);
      _checkOwner(lexicons);
      if (lexicons['version'] != 2 || lexicons['resources'] is! List) {
        throw const FormatException('Invalid offline lexicon catalog');
      }
      for (final value in lexicons['resources'] as List) {
        if (value is! Map) {
          throw const FormatException('Invalid offline resource');
        }
        final resource = asMap(value);
        final id = resource['id'];
        if (id is! String ||
            id.isEmpty ||
            id == '.' ||
            id == '..' ||
            id.contains('/') ||
            id.contains('\\') ||
            !seen.add(id) ||
            resource['kind'] != 'lexicon') {
          throw const FormatException('Invalid offline resource');
        }
        lexiconResources.add(resource);
      }
      result.addAll(lexiconResources);
    } catch (error) {
      lexiconError = error;
      _checkCurrentAccount();
    }
    return (resources: result, lexiconError: lexiconError);
  }

  bool _olderServer(Object? error) =>
      error is ApiException && error.status == 404;

  /// Lists the current server-authorized resources without changing downloads.
  Future<List<Json>> catalog() => _serial(() async {
    final catalog = await _catalog();
    return catalog.resources;
  });

  /// Removes downloads no longer authorized by a successfully validated catalog.
  /// Each successfully verified catalogue can revoke its own package type.
  Future<List<Json>> reconcile() => _serial(() async {
    final catalog = await _catalog();
    final resources = catalog.resources;
    final allowed = resources
        .map((resource) => resource['id'] as String)
        .toSet();
    final local = await store.ids();
    _checkCurrentAccount();
    var unverifiedLexicon = false;
    for (final id in local) {
      _checkCurrentAccount();
      if (catalog.lexiconError != null) {
        final package = await store.read(id);
        _checkCurrentAccount();
        if (package?['version'] == 2 &&
            asMap(package?['resource'])['kind'] == 'lexicon') {
          unverifiedLexicon = true;
          continue;
        }
      }
      if (!allowed.contains(id)) {
        await store.remove(id, validate: _checkCurrentAccount);
      }
    }
    _checkCurrentAccount();
    if (unverifiedLexicon) {
      throw const ApiException(
        'Die Freigabe der gespeicherten Offline-Lexika konnte nicht geprüft werden.',
      );
    }
    if (catalog.lexiconError != null && !_olderServer(catalog.lexiconError)) {
      throw catalog.lexiconError!;
    }
    return resources;
  });

  /// Rechecks the catalog and the package owner before replacing a download.
  Future<void> download(String id) => _serial(() async {
    final catalog = await _catalog();
    final resources = catalog.resources;
    final allowed = resources
        .where((resource) => resource['id'] == id)
        .firstOrNull;
    if (allowed == null) {
      if (catalog.lexiconError != null && !_olderServer(catalog.lexiconError)) {
        throw catalog.lexiconError!;
      }
      throw const ApiException(
        'Dieses Werk ist nicht für die Offline-Nutzung freigegeben.',
      );
    }
    final isLexicon = allowed['kind'] == 'lexicon';
    final prefix = isLexicon
        ? '/api/app/offline/v2/lexicons'
        : '/api/app/offline/resources';
    final raw = await api.get('$prefix/${Uri.encodeComponent(id)}');
    if (raw is! Map) throw const FormatException('Invalid offline package');
    final package = asMap(raw);
    _checkOwner(package);
    final resource = package['resource'];
    if (resource is! Map ||
        resource['id'] != id ||
        resource['kind'] != allowed['kind']) {
      throw const FormatException('Invalid offline package');
    }
    if (isLexicon) {
      final entries = package['entries'];
      final strongs = <String>{};
      if (package['version'] != 2 ||
          entries is! List ||
          entries.any((entry) {
            if (entry is! Map ||
                entry['strong'] is! String ||
                !RegExp(r'^[GH][0-9]+$').hasMatch(entry['strong'] as String) ||
                !strongs.add(entry['strong'] as String) ||
                !['grc', 'hbo'].contains(entry['language']) ||
                entry['lemma'] is! String ||
                entry['seeAlso'] is! List ||
                (entry['seeAlso'] as List).any((item) => item is! String)) {
              return true;
            }
            for (final key in [
              'transliteration',
              'pronunciation',
              'definitionHtml',
              'derivationHtml',
              'kjvDefinitionHtml',
            ]) {
              if (entry[key] != null && entry[key] is! String) return true;
            }
            return entry['germanTranslation'] != null &&
                entry['germanTranslation'] is! Map;
          })) {
        throw const FormatException('Invalid offline lexicon package');
      }
    } else if (package['version'] != 1 ||
        package['chapters'] is! List ||
        (package['chapters'] as List).any(
          (chapter) => chapter is! Map || chapter['resourceId'] != id,
        )) {
      throw const FormatException('Invalid offline package');
    }
    await store.write(package, validate: _checkCurrentAccount);
  });

  Future<void> remove(String id) => _serial(() async {
    _checkCurrentAccount();
    await store.remove(id, validate: _checkCurrentAccount);
  });
}
