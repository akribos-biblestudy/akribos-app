import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/json.dart';
import '../documents/document_widgets.dart';
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
    this.notesOnly = false,
  });
  final String reference, resourceId, initialState;
  final bool notesOnly;
  final void Function(String query, String tag, bool current) onFilters;
  final void Function(String id) onOpen;
  final VoidCallback onCreate;
  @override
  State<ReaderNotes> createState() => ReaderNotesState();
}

class ReaderNotesState extends State<ReaderNotes> {
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
          if (widget.notesOnly) 'kind': 'note',
          if (_query.isNotEmpty) 'q': _query,
          if (_tag.isNotEmpty) 'tag': _tag,
          if (_current) ...{
            'passage': widget.reference,
            if (widget.resourceId.isNotEmpty) 'resource': widget.resourceId,
          },
        },
      ).toString(),
    );
  }

  void reload() => setState(_load);

  @override
  void didUpdateWidget(ReaderNotes oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.notesOnly != oldWidget.notesOnly ||
        (_current &&
            (widget.reference != oldWidget.reference ||
                widget.resourceId != oldWidget.resourceId))) {
      _load();
    }
  }

  void _change() {
    widget.onFilters(_query, _tag, _current);
    setState(_load);
  }

  Future<void> _filter() async {
    final fields = await editFeatureFields(context, 'Notizen filtern', [
      FeatureField('tag', 'Tag / Untertag', value: _tag),
    ], submit: 'Anwenden');
    if (fields == null || !mounted) return;
    _tag = asString(fields['tag']).trim();
    _change();
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
          label: widget.notesOnly
              ? 'Eigene Notizen durchsuchen'
              : 'Eigene Notizen und Dokumente durchsuchen',
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
            TextButton.icon(
              onPressed: _filter,
              icon: const Icon(Icons.tune),
              label: Text(_tag.isEmpty ? 'Filtern' : 'Tagfilter aktiv'),
            ),
            if (_tag.isNotEmpty)
              IconButton(
                onPressed: () {
                  _tag = '';
                  _change();
                },
                icon: const Icon(Icons.filter_alt_off_outlined),
                tooltip: 'Tagfilter zurücksetzen',
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
            // FutureBuilder retains the old snapshot while a new request waits.
            // Do not show notes from the previous chapter or a revoked session.
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
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
            final data = asMap(snapshot.data);
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (asMaps(data['documents']).isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      widget.notesOnly
                          ? 'Keine Notizen für diese Auswahl.'
                          : 'Keine Notizen oder Dokumente für diese Auswahl.',
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
