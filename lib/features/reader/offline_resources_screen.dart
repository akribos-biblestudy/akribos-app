import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import 'offline_resource_manager.dart';

/// Lets the current account download, inspect and remove its offline works.
class OfflineResourcesScreen extends StatefulWidget {
  const OfflineResourcesScreen({
    super.key,
    required this.manager,
    this.onChanged,
    this.onReadOffline,
  });

  final OfflineResourceManager manager;
  final VoidCallback? onChanged;
  final VoidCallback? onReadOffline;

  @override
  State<OfflineResourcesScreen> createState() => _OfflineResourcesScreenState();
}

class _OfflineResourcesScreenState extends State<OfflineResourcesScreen> {
  List<Json> _available = [];
  Map<String, Json> _saved = {};
  bool _loading = true;
  bool _busy = false;
  Object? _error;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void didUpdateWidget(OfflineResourcesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.manager, widget.manager)) {
      _available = [];
      _saved = {};
      _error = null;
      _busy = false;
      _refresh();
    }
  }

  Future<Map<String, Json>> _readSaved(OfflineResourceManager manager) async {
    final result = <String, Json>{};
    for (final id in await manager.store.ids()) {
      final package = await manager.store.read(id);
      if (package != null) result[id] = asMap(package['resource']);
    }
    return result;
  }

  bool _current(int generation) => mounted && generation == _generation;

  bool _identityValid(OfflineResourceManager manager) {
    return manager.isCurrentAccount;
  }

  Future<void> _refresh() async {
    final generation = ++_generation;
    final manager = widget.manager;
    setState(() {
      _loading = true;
      _error = null;
    });
    Map<String, Json> saved = {};
    var reconciled = false;
    try {
      if (!_identityValid(manager)) {
        throw const ApiException('Das Konto hat sich geändert.');
      }
      saved = await _readSaved(manager);
      final available = await manager.reconcile();
      reconciled = true;
      final verifiedSaved = await _readSaved(manager);
      if (!_current(generation)) return;
      if (saved.length != verifiedSaved.length ||
          saved.keys.any((id) => !verifiedSaved.containsKey(id))) {
        widget.onChanged?.call();
      }
      setState(() {
        _available = available;
        _saved = verifiedSaved;
      });
    } catch (error) {
      if (!_current(generation)) return;
      var after = <String, Json>{};
      var available = <Json>[];
      if (_identityValid(manager)) {
        try {
          after = await _readSaved(manager);
        } catch (_) {
          // Leave the list empty if local state cannot be verified.
        }
        try {
          available = await manager.catalog();
        } catch (_) {
          // A failed v1 catalog must not invent any available works.
        }
      }
      if (!_current(generation)) return;
      if (reconciled ||
          saved.length != after.length ||
          saved.keys.any((id) => !after.containsKey(id))) {
        widget.onChanged?.call();
      }
      setState(() {
        _available = _identityValid(manager) ? available : [];
        _saved = _identityValid(manager) ? after : {};
        _error = error;
      });
    } finally {
      if (_current(generation)) setState(() => _loading = false);
    }
  }

  Future<void> _change(String id, {required bool remove}) async {
    if (_busy || _loading) return;
    final manager = widget.manager;
    final generation = _generation;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (remove) {
        await manager.remove(id);
      } else {
        await manager.download(id);
      }
      final saved = await _readSaved(manager);
      if (!_current(generation)) return;
      setState(() => _saved = saved);
      widget.onChanged?.call();
    } catch (error) {
      if (_current(generation)) {
        setState(() {
          if (!_identityValid(manager)) {
            _available = [];
            _saved = {};
          }
          _error = error;
        });
      }
    } finally {
      if (_current(generation)) setState(() => _busy = false);
    }
  }

  String _errorMessage(Object error) => error is ApiException
      ? error.message
      : 'Die Offline-Werke konnten nicht aktualisiert werden. Bitte erneut versuchen.';

  @override
  Widget build(BuildContext context) {
    final resources = <String, Json>{
      for (final resource in _available) asString(resource['id']): resource,
      for (final entry in _saved.entries)
        if (!_available.any((resource) => resource['id'] == entry.key))
          entry.key: entry.value,
    };
    return Scaffold(
      appBar: AppBar(title: const Text('Offline-Werke')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'Lade freigegebene Werke auf dieses Gerät herunter, um sie ohne Internet zu lesen.',
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: _loading || _busy ? null : _refresh,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Freigaben aktualisieren'),
                ),
              ),
              if (widget.onReadOffline != null) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                    onPressed: !_loading && !_busy && _saved.isNotEmpty
                        ? widget.onReadOffline
                        : null,
                    icon: const Icon(Icons.menu_book_outlined),
                    label: const Text('Offline lesen'),
                  ),
                ),
              ],
              if (_loading || _busy) ...[
                const SizedBox(height: 12),
                const LinearProgressIndicator(),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    _errorMessage(_error!),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ],
              if (!_loading && resources.isEmpty) ...[
                const SizedBox(height: 20),
                Text(
                  _error == null
                      ? 'Zurzeit sind keine Werke für die Offline-Nutzung freigegeben.'
                      : 'Keine gespeicherten Werke verfügbar.',
                ),
              ],
              for (final entry in resources.entries) ...[
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          asString(
                            entry.value['selectionTitle'],
                            asString(entry.value['name'], entry.key),
                          ),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _saved.containsKey(entry.key)
                              ? 'Auf diesem Gerät gespeichert'
                              : 'Zum Download verfügbar',
                        ),
                        const SizedBox(height: 8),
                        if (_saved.containsKey(entry.key))
                          OutlinedButton.icon(
                            onPressed: _loading || _busy
                                ? null
                                : () => _change(entry.key, remove: true),
                            icon: const Icon(Icons.delete_outline),
                            label: const Text('Entfernen'),
                          )
                        else
                          FilledButton.tonalIcon(
                            onPressed: _loading || _busy
                                ? null
                                : () => _change(entry.key, remove: false),
                            icon: const Icon(Icons.download_outlined),
                            label: const Text('Herunterladen'),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
