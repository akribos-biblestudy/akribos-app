import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/api_client.dart';
import '../../widgets/common.dart';
import '../../widgets/remote_page.dart';
import 'document_editor.dart';
import 'document_import.dart';
import 'document_widgets.dart';
import '../reader/books.dart';

class DocumentsScreen extends StatelessWidget {
  const DocumentsScreen({super.key, required this.path});
  final String path;

  @override
  Widget build(BuildContext context) {
    final pathname = Uri.parse(path).path;
    if (pathname == '/notes/import') return DocumentImportScreen(path: path);
    if (pathname.startsWith('/notes/published/')) {
      return RemotePage(
        path: path,
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
    if (pathname.startsWith('/notes/')) return DocumentEditor(path: path);
    return RemotePage(
      path: path,
      builder: (context, data, reload) {
        if (pathname == '/sermons/templates') {
          return _Templates(data: data, reload: reload);
        }
        return _Library(
          path: path,
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
          FeatureField(
            'template',
            'Vorlage',
            value: 'default',
            options: {
              'default': 'Akribos-Standardvorlage',
              'empty': 'Leeres Dokument',
              ...itemOptions(data['templates'], label: 'name'),
            },
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
          'kind',
          'Dokumentart',
          value: asString(filters['kind']),
          options: const {
            '': 'Alle Arten',
            'note': 'Notizen',
            'sermon': 'Ausarbeitungen',
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

  Future<void> _column(
    BuildContext context,
    String action, {
    Json? column,
  }) async {
    final board = asMap(data['board']);
    Json fields = {};
    if (action == 'create' || action == 'rename') {
      final values = await editFeatureFields(
        context,
        action == 'create'
            ? 'Neuer Vorbereitungsschritt'
            : 'Schritt umbenennen',
        [
          FeatureField(
            'name',
            'Name',
            value: asString(column?['name']),
            required: true,
          ),
        ],
      );
      if (values == null || !context.mounted) return;
      fields = values;
    }
    if (action == 'delete') {
      final targets = asMaps(board['columns'])
          .where((row) => row['id'] != column?['id'])
          .toList();
      if (targets.isEmpty) return;
      final values = await editFeatureFields(context, 'Schritt entfernen', [
        FeatureField(
          'targetId',
          'Ausarbeitungen verschieben nach',
          value: asString(targets.first['id']),
          options: itemOptions(targets, label: 'name'),
        ),
      ], submit: 'Entfernen und verschieben');
      if (values == null || !context.mounted) return;
      fields = values;
    }
    await runAction(context, '/sermons', 'columns', {
      ...fields,
      'columnAction': action,
      'columnId': column?['id'] ?? '',
      'boardRevision': board['revision'],
    }, reload: reload);
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
                onSelected: (value) {
                  if (value == 'column') {
                    _column(context, 'create');
                  } else {
                    AppScope.of(context).open(value);
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: '/notes/import',
                    child: Text('Dokumente importieren'),
                  ),
                  if (sermons) ...[
                    const PopupMenuItem(
                      value: '/sermons/templates',
                      child: Text('Vorlagen verwalten'),
                    ),
                    const PopupMenuItem(
                      value: 'column',
                      child: Text('Vorbereitungsschritt hinzufügen'),
                    ),
                  ],
                  PopupMenuItem(
                    value: deleted ? '/notes' : '/notes?deleted=1',
                    child: Text(deleted ? 'Zur Bibliothek' : 'Papierkorb'),
                  ),
                ],
              ),
            ],
          ),
          if (Uri.parse(path).hasQuery)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () =>
                    AppScope.of(context).open(sermons ? '/sermons' : '/notes'),
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
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              asString(column['name']),
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ),
                          PopupMenuButton<String>(
                            tooltip: 'Schritt bearbeiten',
                            onSelected: (action) =>
                                _column(context, action, column: column),
                            itemBuilder: (_) => const [
                              PopupMenuItem(
                                value: 'rename',
                                child: Text('Umbenennen'),
                              ),
                              PopupMenuItem(
                                value: 'left',
                                child: Text('Nach links'),
                              ),
                              PopupMenuItem(
                                value: 'right',
                                child: Text('Nach rechts'),
                              ),
                              PopupMenuItem(
                                value: 'delete',
                                child: Text('Entfernen'),
                              ),
                            ],
                          ),
                        ],
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

class _Templates extends StatelessWidget {
  const _Templates({required this.data, required this.reload});
  final Json data;
  final Future<void> Function() reload;

  Future<void> _edit(BuildContext context, [Json? template]) async {
    final api = AppScope.of(context).api;
    final fields = await editFeatureFields(
      context,
      template == null ? 'Neue Vorlage' : 'Vorlage bearbeiten',
      [
        FeatureField(
          'name',
          'Name',
          value: asString(template?['name']),
          required: true,
        ),
        FeatureField(
          'bodyMarkdown',
          'Gliederung (Markdown)',
          value: asString(template?['bodyMarkdown']),
          lines: 12,
        ),
      ],
      onSubmit: (fields) async {
        final result = await api.action(
          '/sermons/templates',
          template == null ? 'create' : 'update',
          {...fields, if (template != null) 'id': template['id']},
        );
        if (!result.isSuccess) throw ApiException(result.message);
      },
    );
    if (fields == null || !context.mounted) return;
    await reload();
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      FeatureHeading(
        'Ausarbeitungsvorlagen',
        subtitle: 'Ein guter Anfang für deine nächste Vorbereitung.',
        actions: [
          FilledButton.icon(
            onPressed: () => _edit(context),
            icon: const Icon(Icons.add),
            label: const Text('Vorlage'),
          ),
        ],
      ),
      for (final template in asMaps(data['templates']))
        Card(
          child: ListTile(
            leading: const Icon(Icons.description_outlined),
            title: Text(asString(template['name'])),
            onTap: () => _edit(context, template),
            trailing: IconButton(
              tooltip: 'Vorlage löschen',
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                if (!await _confirm(
                  context,
                  'Vorlage löschen? Bestehende Ausarbeitungen bleiben erhalten.',
                )) {
                  return;
                }
                if (!context.mounted) return;
                await runAction(context, '/sermons/templates', 'delete', {
                  'id': template['id'],
                }, reload: reload);
              },
            ),
          ),
        ),
      if (asMaps(data['templates']).isEmpty)
        const EmptyFeature('Lege deine erste eigene Gliederung an.'),
    ],
  );
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
