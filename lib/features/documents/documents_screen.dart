import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/api_client.dart';
import '../../widgets/common.dart';
import '../../widgets/remote_page.dart';
import 'document_editor.dart';
import 'document_widgets.dart';
import '../reader/books.dart';

const notesLibraryPath = '/notes?kind=note';

/// Removed mobile tools must never reach their API pages or the document editor.
/// Keep the note kind explicit for compatibility with older mixed libraries.
String mobileDocumentPath(String path) {
  final uri = Uri.parse(path);
  if (uri.path == '/notes/import' || uri.path.startsWith('/notes/import/')) {
    return notesLibraryPath;
  }
  if (uri.path == '/sermons/templates' ||
      uri.path.startsWith('/sermons/templates/')) {
    return '/sermons';
  }
  if (uri.path == '/notes') {
    return uri
        .replace(queryParameters: {...uri.queryParameters, 'kind': 'note'})
        .toString();
  }
  return path;
}

class DocumentsScreen extends StatelessWidget {
  const DocumentsScreen({super.key, required this.path});
  final String path;

  @override
  Widget build(BuildContext context) {
    final effectivePath = mobileDocumentPath(path);
    final pathname = Uri.parse(effectivePath).path;
    if (pathname.startsWith('/notes/published/')) {
      return RemotePage(
        path: effectivePath,
        builder: (context, data, reload) {
          final publication = asMap(data['publication']);
          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              FeatureHeading(
                asString(publication['title']),
                subtitle: asString(publication['authorName']),
              ),
              if (asString(publication['excerpt']).isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(asString(publication['excerpt'])),
                ),
              HtmlContent(html: asString(publication['bodyHtml'])),
              if (publication['tags'] is List &&
                  (publication['tags'] as List).isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 24),
                  child: ExpansionTile(
                    leading: const Icon(Icons.label_outline),
                    title: const Text('Tags'),
                    children: [
                      Wrap(
                        spacing: 8,
                        children: [
                          for (final tag in publication['tags'] as List)
                            Chip(
                              label: Text(
                                tag is Map
                                    ? asString(tag['path'])
                                    : asString(tag),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      );
    }
    if (pathname.startsWith('/notes/')) {
      return DocumentEditor(path: effectivePath);
    }
    return RemotePage(
      path: effectivePath,
      builder: (context, data, reload) {
        return _Library(
          path: effectivePath,
          data: data,
          reload: reload,
          sermons: pathname == '/sermons',
        );
      },
    );
  }
}

class _Library extends StatelessWidget {
  const _Library({
    required this.path,
    required this.data,
    required this.reload,
    required this.sermons,
  });
  final String path;
  final Json data;
  final Future<void> Function() reload;
  final bool sermons;

  Future<void> _create(BuildContext context) async {
    final fields = await editFeatureFields(
      context,
      sermons ? 'Neue Ausarbeitung' : 'Neue Notiz',
      [
        const FeatureField('title', 'Titel', required: true),
        FeatureField(
          'passage',
          'Bibelstelle (optional)',
          value: Uri.parse(path).queryParameters['reference'] ?? '',
        ),
        if (sermons) ...[
          const FeatureField(
            'format',
            'Format',
            value: 'sermon',
            options: sermonFormats,
          ),
          const FeatureField('date', 'Geplanter Termin (JJJJ-MM-TT)'),
          const FeatureField('series', 'Serie (optional)'),
        ],
      ],
      submit: 'Anlegen',
    );
    if (fields == null || !context.mounted) return;
    await runAction(context, sermons ? '/sermons' : '/notes', 'create', {
      ...fields,
      'kind': sermons ? 'sermon' : 'note',
      'returnTo': path,
      if (Uri.parse(path).queryParameters['bible'] case final String bible)
        'resourceId': bible,
    }, reload: reload);
  }

  Future<void> _filter(BuildContext context) async {
    final filters = asMap(data['filters']);
    final fields = await editFeatureFields(context, 'Bibliothek filtern', [
      FeatureField('q', 'Suchtext', value: asString(filters['q'])),
      if (sermons) ...[
        FeatureField(
          'status',
          'Vorbereitungsschritt',
          value: asString(filters['status']),
          options: itemOptions(
            asMap(data['board'])['columns'],
            label: 'name',
            empty: 'Alle Schritte',
          ),
        ),
        FeatureField(
          'format',
          'Format',
          value: asString(filters['format']),
          options: {'': 'Alle Formate', ...sermonFormats},
        ),
        FeatureField('series', 'Serie', value: asString(filters['series'])),
      ] else ...[
        FeatureField('tag', 'Tag / Untertag', value: asString(filters['tag'])),
        FeatureField(
          'passage',
          'Bibelstelle',
          value: asString(filters['passage']),
        ),
        FeatureField(
          'book',
          'Bibelbuch',
          value: asString(filters['book']),
          options: {
            '': 'Alle Bücher',
            for (final book in bibleBooks) '${book.id}': book.name,
          },
        ),
        FeatureField(
          'resource',
          'Bibel für Stellenfilter',
          value: asString(filters['resourceId']),
          options: {
            '': 'Alle Bibeln',
            'canonical': 'Ohne Übersetzungsbindung',
            ...itemOptions(data['bibles'], label: 'tabTitle'),
          },
        ),
      ],
      FeatureField('year', 'Jahr', value: asString(filters['year'])),
    ], submit: 'Anwenden');
    if (fields == null || !context.mounted) return;
    final params = <String, String>{
      if (!sermons) 'kind': 'note',
      for (final entry in fields.entries)
        if (asString(entry.value).isNotEmpty) entry.key: asString(entry.value),
      if (filters['deleted'] == true) 'deleted': '1',
    };
    await AppScope.of(context).open(
      Uri(
        path: sermons ? '/sermons' : '/notes',
        queryParameters: params.isEmpty ? null : params,
      ).toString(),
    );
  }

  Widget _documentCard(
    BuildContext context,
    Json document, {
    bool deleted = false,
  }) {
    final columns = asMaps(asMap(data['board'])['columns']);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: deleted
            ? null
            : () => AppScope.of(context).open(
                '/notes/${document['id']}?returnTo=${Uri.encodeComponent(path)}',
              ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    sermons || document['kind'] == 'sermon'
                        ? Icons.edit_note_rounded
                        : Icons.description_outlined,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      asString(document['title']),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Dokumentaktionen',
                    onSelected: (action) async {
                      if (action.startsWith('move:')) {
                        await runAction(context, '/sermons', 'move', {
                          'id': document['id'],
                          'revision': document['revision'],
                          'status': action.substring(5),
                        }, reload: reload);
                      } else {
                        if (action == 'softDelete' &&
                            !await _confirm(
                              context,
                              'In den Papierkorb verschieben?',
                            )) {
                          return;
                        }
                        if (!context.mounted) return;
                        await runAction(context, '/notes', action, {
                          'id': document['id'],
                          'revision': document['revision'],
                        }, reload: reload);
                      }
                    },
                    itemBuilder: (_) => [
                      if (sermons)
                        for (final column in columns)
                          PopupMenuItem(
                            value: 'move:${column['id']}',
                            child: Text('Verschieben: ${column['name']}'),
                          ),
                      PopupMenuItem(
                        value: deleted ? 'restore' : 'softDelete',
                        child: Text(
                          deleted ? 'Wiederherstellen' : 'In den Papierkorb',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              if (asString(document['plainText']).isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  asString(document['plainText']),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 12),
              Text(
                sermons
                    ? [
                        sermonFormats[document['sermonFormat']] ??
                            'Ausarbeitung',
                        shortDate(document['sermonDate']),
                        asString(document['sermonSeries']),
                      ].where((part) => part.isNotEmpty).join(' · ')
                    : shortDate(document['updatedAt']),
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final documents = asMaps(data[sermons ? 'sermons' : 'documents']);
    final deleted = asMap(data['filters'])['deleted'] == true;
    final pagination = asMap(data['pagination']);
    final columns = asMaps(asMap(data['board'])['columns']);
    return RefreshIndicator(
      onRefresh: reload,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('Notizen'),
                  avatar: const Icon(Icons.description_outlined, size: 18),
                  selected: !sermons,
                  onSelected: (selected) {
                    if (selected) AppScope.of(context).open(notesLibraryPath);
                  },
                ),
                ChoiceChip(
                  label: const Text('Ausarbeitungen'),
                  avatar: const Icon(Icons.edit_note_rounded, size: 18),
                  selected: sermons,
                  onSelected: (selected) {
                    if (selected) AppScope.of(context).open('/sermons');
                  },
                ),
              ],
            ),
          ),
          FeatureHeading(
            sermons
                ? 'Vorbereitung'
                : deleted
                ? 'Papierkorb'
                : 'Meine Notizen',
            subtitle: sermons
                ? 'Gedanken sammeln. Gemeinsam weiterdenken.'
                : 'Deine Gedanken zum Bibeltext.',
            actions: [
              FilledButton.icon(
                onPressed: () => _create(context),
                icon: const Icon(Icons.add),
                label: Text(sermons ? 'Ausarbeitung' : 'Notiz'),
              ),
              IconButton(
                onPressed: () => _filter(context),
                icon: const Icon(Icons.tune),
                tooltip: 'Filtern',
              ),
              PopupMenuButton<String>(
                tooltip: 'Weitere Optionen',
                onSelected: (value) => AppScope.of(context).open(value),
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: deleted
                        ? notesLibraryPath
                        : '/notes?kind=note&deleted=1',
                    child: Text(deleted ? 'Zur Bibliothek' : 'Papierkorb'),
                  ),
                ],
              ),
            ],
          ),
          if (Uri.parse(path).queryParameters.keys.any((key) => key != 'kind'))
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () =>
                    AppScope.of(context)
                        .open(sermons ? '/sermons' : notesLibraryPath),
                icon: const Icon(Icons.filter_alt_off_outlined),
                label: const Text('Filter zurücksetzen'),
              ),
            ),
          if (data['filterError'] != null)
            const Text(
              'Ein Filter war ungültig. Bitte prüfe die Filterauswahl.',
            ),
          if (sermons)
            LayoutBuilder(
              builder: (context, constraints) {
                Widget boardColumn(Json column) => SizedBox(
                  width: constraints.maxWidth >= 720
                      ? 300
                      : constraints.maxWidth,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        asString(column['name']),
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      for (final document in documents.where(
                        (item) => item['sermonStatus'] == column['id'],
                      ))
                        _documentCard(context, document),
                      const SizedBox(height: 16),
                    ],
                  ),
                );
                return constraints.maxWidth >= 720
                    ? SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (final column in columns)
                              Padding(
                                padding: const EdgeInsets.only(right: 16),
                                child: boardColumn(column),
                              ),
                          ],
                        ),
                      )
                    : Column(children: columns.map(boardColumn).toList());
              },
            )
          else ...[
            if (documents.isEmpty)
              const EmptyFeature('Hier sind noch keine Dokumente.'),
            for (final document in documents)
              _documentCard(context, document, deleted: deleted),
            if (asInt(pagination['pageCount']) > 1)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    tooltip: 'Vorherige Seite',
                    onPressed: asInt(pagination['page']) > 1
                        ? () => _page(context, asInt(pagination['page']) - 1)
                        : null,
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Text('${pagination['page']} / ${pagination['pageCount']}'),
                  IconButton(
                    tooltip: 'Nächste Seite',
                    onPressed:
                        asInt(pagination['page']) <
                            asInt(pagination['pageCount'])
                        ? () => _page(context, asInt(pagination['page']) + 1)
                        : null,
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
          ],
        ],
      ),
    );
  }

  void _page(BuildContext context, int page) {
    final uri = Uri.parse(path);
    AppScope.of(context).open(
      uri
          .replace(queryParameters: {...uri.queryParameters, 'page': '$page'})
          .toString(),
    );
  }
}

Future<bool> _confirm(BuildContext context, String message) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Bestätigen'),
          ),
        ],
      ),
    ) ??
    false;
