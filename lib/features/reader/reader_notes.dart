import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/json.dart';
import '../search/search_screen.dart';

class ReaderNotes extends StatefulWidget {
  const ReaderNotes({
    super.key,
    required this.reference,
    required this.resourceId,
    required this.initialState,
    required this.onFilters,
    required this.onOpen,
    required this.onCreate,
  });
  final String reference, resourceId, initialState;
  final void Function(String query, String tag, bool current) onFilters;
  final void Function(String id) onOpen;
  final VoidCallback onCreate;
  @override
  State<ReaderNotes> createState() => _ReaderNotesState();
}

class _ReaderNotesState extends State<ReaderNotes> {
  late String _query =
      Uri.splitQueryString(widget.initialState)['notesQuery'] ?? '';
  late String _tag =
      Uri.splitQueryString(widget.initialState)['notesTag'] ?? '';
  late bool _current =
      Uri.splitQueryString(widget.initialState)['notesFilter'] == 'current';
  Future<dynamic>? _request;
  void _load() {
    _request = AppScope.of(context).api.get(
      Uri(
        path: '/api/documents',
        queryParameters: {
          if (_query.isNotEmpty) 'q': _query,
          if (_tag.isNotEmpty) 'tag': _tag,
          if (_current) ...{
            'passage': widget.reference,
            'resource': widget.resourceId,
          },
        },
      ).toString(),
    );
  }

  void _change() {
    widget.onFilters(_query, _tag, _current);
    setState(_load);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_request == null) _load();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.all(16),
        child: SearchBox(
          initialValue: _query,
          label: 'Eigene Notizen und Dokumente durchsuchen',
          onSearch: (value) {
            _query = value;
            _change();
          },
        ),
      ),
      SwitchListTile(
        title: Text('Nur zu ${widget.reference}'),
        value: _current,
        onChanged: (value) {
          _current = value;
          _change();
        },
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.tonalIcon(
              onPressed: widget.onCreate,
              icon: const Icon(Icons.add),
              label: const Text('Neue Notiz'),
            ),
            if (_query.isNotEmpty)
              TextButton(
                onPressed: () {
                  _query = '';
                  _change();
                },
                child: const Text('Suche zurücksetzen'),
              ),
          ],
        ),
      ),
      Expanded(
        child: FutureBuilder<dynamic>(
          future: _request,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(
                child: TextButton(
                  onPressed: () => setState(_load),
                  child: Text('Erneut versuchen: ${snapshot.error}'),
                ),
              );
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final data = asMap(snapshot.data),
                tags = asMaps(asMap(snapshot.data)['tags']);
            final tagValues = {
              for (final tag in tags) asString(tag['path']),
              if (_tag.isNotEmpty) _tag,
            };
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: _tag,
                  decoration: const InputDecoration(labelText: 'Schlagwort'),
                  items: [
                    const DropdownMenuItem(
                      value: '',
                      child: Text(
                        'Alle Schlagwörter',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    ...tagValues.map(
                      (tag) => DropdownMenuItem(
                        value: tag,
                        child: Text(tag, overflow: TextOverflow.ellipsis),
                      ),
                    ),
                  ],
                  onChanged: (value) {
                    _tag = value ?? '';
                    _change();
                  },
                ),
                const SizedBox(height: 12),
                if (asMaps(data['documents']).isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'Keine Notizen oder Dokumente für diese Auswahl.',
                    ),
                  ),
                for (final document in asMaps(data['documents']))
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(asString(document['title'], 'Ohne Titel')),
                    subtitle: Text(asString(document['excerpt'])),
                    onTap: () => widget.onOpen(asString(document['id'])),
                  ),
                if (data['truncated'] == true)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'Die ersten 100 Einträge werden angezeigt. Grenze die Auswahl mit Suche oder Schlagwort weiter ein.',
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    ],
  );
}
