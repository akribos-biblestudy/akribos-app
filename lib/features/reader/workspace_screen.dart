import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/json.dart';
import '../../widgets/common.dart';
import '../../widgets/remote_page.dart';
import 'reader_dialogs.dart';

class WorkspaceScreen extends StatefulWidget {
  const WorkspaceScreen({super.key, this.snapshot, this.path = '/workspaces'});
  final Json? snapshot;
  final String path;
  @override
  State<WorkspaceScreen> createState() => _WorkspaceScreenState();
}

class _WorkspaceScreenState extends State<WorkspaceScreen> {
  Future<dynamic>? _request;
  bool _busy = false;
  String? get _openingId {
    final parts = Uri.parse(widget.path).pathSegments;
    return parts.length == 2 && parts.first == 'workspaces' ? parts.last : null;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_openingId == null) {
      _request ??= AppScope.of(context).api.get('/api/reader/workspaces');
    }
  }

  void _reload() => setState(
    () => _request = AppScope.of(context).api.get('/api/reader/workspaces'),
  );
  Future<String?> _name(String title, [String value = '']) =>
      showDialog<String>(
        context: context,
        builder: (context) => ReaderTextDialog(
          title: title,
          initial: value,
          maxLength: 80,
          requireValue: true,
          submitLabel: 'Speichern',
        ),
      );

  Future<void> _change(String method, String path, Json fields) async {
    setState(() => _busy = true);
    try {
      await AppScope.of(context).api.send(method, path, data: fields);
      if (mounted) _reload();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _activate(String id) async {
    final scope = AppScope.of(context);
    setState(() => _busy = true);
    try {
      final response = await scope.api.action('/workspaces/$id', 'default', {});
      if (!mounted) return;
      if (!response.isRedirect) {
        showError(context, response.message);
        return;
      }
      if (ModalRoute.of(context) is PopupRoute) Navigator.pop(context);
      await scope.open(response.location!);
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => _openingId != null
      ? RemotePage(
          path: widget.path,
          builder: (context, data, reload) => ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                asString(data['name'], 'Arbeitsbereich'),
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 16),
              const Text(
                'Öffne diesen Arbeitsbereich, um seine gespeicherte Ansicht auf diesem Gerät zu laden.',
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _busy ? null : () => _activate(_openingId!),
                icon: const Icon(Icons.dashboard_outlined),
                label: const Text('Arbeitsbereich öffnen'),
              ),
            ],
          ),
        )
      : FutureBuilder<dynamic>(
          future: _request,
          builder: (context, state) {
            if (state.hasError) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('${state.error}'),
                    TextButton(
                      onPressed: _reload,
                      child: const Text('Erneut versuchen'),
                    ),
                  ],
                ),
              );
            }
            if (!state.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final items = asMaps(asMap(state.data)['workspaces']);
            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  'Arbeitsbereiche',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'Benannte Ansichten stehen auf allen Geräten bereit. Jedes Gerät behält seine eigene laufende Ansicht.',
                  ),
                ),
                if (widget.snapshot != null)
                  FilledButton.icon(
                    onPressed: _busy
                        ? null
                        : () async {
                            final name = await _name(
                              'Aktuelle Ansicht speichern',
                            );
                            if (name != null && mounted) {
                              setState(() => _busy = true);
                              try {
                                final result = asMap(
                                  await AppScope.of(this.context).api.send(
                                    'POST',
                                    '/api/reader/workspaces',
                                    data: {
                                      'name': name,
                                      'snapshot': widget.snapshot,
                                    },
                                  ),
                                );
                                final saved = asMap(result['workspace']);
                                final id = saved['id'] ?? result['id'];
                                if (mounted && id != null) {
                                  await _activate('$id');
                                }
                                if (mounted) _reload();
                              } catch (error) {
                                if (mounted) {
                                  ScaffoldMessenger.of(this.context)
                                      .showSnackBar(
                                        SnackBar(content: Text('$error')),
                                      );
                                }
                              } finally {
                                if (mounted) setState(() => _busy = false);
                              }
                            }
                          },
                    icon: const Icon(Icons.add),
                    label: const Text('Neue Ansicht aus aktuellem Reader'),
                  ),
                if (_busy) const LinearProgressIndicator(),
                for (final workspace in items)
                  Card(
                    child: ListTile(
                      leading: Icon(
                        workspace['isActive'] == true
                            ? Icons.check_circle
                            : Icons.dashboard_outlined,
                      ),
                      title: Text(asString(workspace['name'])),
                      subtitle: workspace['isActive'] == true
                          ? const Text('Hier geöffnet')
                          : null,
                      onTap: _busy
                          ? null
                          : () => _activate(asString(workspace['id'])),
                      trailing: PopupMenuButton<String>(
                        enabled: !_busy,
                        onSelected: (action) async {
                          if (action == 'rename') {
                            final name = await _name(
                              'Arbeitsbereich umbenennen',
                              asString(workspace['name']),
                            );
                            if (name != null && mounted) {
                              await _change(
                                'PATCH',
                                '/api/reader/workspaces/${workspace['id']}',
                                {
                                  'name': name,
                                  'revision': workspace['revision'],
                                },
                              );
                            }
                          } else {
                            final confirmed = await showDialog<bool>(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: const Text('Arbeitsbereich löschen?'),
                                content: Text(
                                  '„${workspace['name']}“ wird auf allen Geräten entfernt.',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(context, false),
                                    child: const Text('Abbrechen'),
                                  ),
                                  FilledButton(
                                    onPressed: () =>
                                        Navigator.pop(context, true),
                                    child: const Text('Löschen'),
                                  ),
                                ],
                              ),
                            );
                            if (confirmed == true && mounted) {
                              await _change(
                                'DELETE',
                                '/api/reader/workspaces/${workspace['id']}',
                                {'revision': workspace['revision']},
                              );
                            }
                          }
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: 'rename',
                            child: Text('Umbenennen'),
                          ),
                          PopupMenuItem(
                            value: 'delete',
                            enabled: workspace['isActive'] != true,
                            child: const Text('Löschen'),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        );
}

Future<void> showWorkspaces(BuildContext context, {Json? snapshot}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => readerOverlayScope(
        context,
        SizedBox(
          height: MediaQuery.sizeOf(sheetContext).height * .85,
          child: WorkspaceScreen(snapshot: snapshot),
        ),
      ),
    );
