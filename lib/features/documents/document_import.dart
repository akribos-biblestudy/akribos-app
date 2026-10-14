import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/app_scope.dart';
import '../../widgets/common.dart';
import '../../widgets/remote_page.dart';
import 'document_widgets.dart';

class DocumentImportScreen extends StatefulWidget {
  const DocumentImportScreen({super.key, required this.path});
  final String path;
  @override
  State<DocumentImportScreen> createState() => _DocumentImportScreenState();
}

class _DocumentImportScreenState extends State<DocumentImportScreen> {
  Json? _preview;
  bool _busy = false;
  int _maximumBytes = 16 * 1024 * 1024;
  int _maximumFiles = 100;

  Future<void> _pick() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['md', 'markdown', 'docx', 'zip'],
    );
    if (files.isEmpty || !mounted) return;
    setState(() {
      _busy = true;
      _preview = null;
    });
    try {
      final api = AppScope.of(context).api;
      final uploads = <AppUpload>[];
      if (files.length > _maximumFiles) {
        throw StateError('Bitte höchstens $_maximumFiles Dateien auswählen.');
      }
      var total = 0;
      for (final file in files) {
        final size = await file.length();
        total += size ?? 0;
        if (size == null || total > _maximumBytes) {
          throw StateError('Die ausgewählte Datei ist zu groß.');
        }
        uploads.add(
          AppUpload(
            field: 'file',
            name: file.name,
            bytes: await file.readAsBytes(),
          ),
        );
      }
      final result = await api.uploadAction(
        '/notes/import',
        'preview',
        {},
        uploads,
      );
      if (!mounted) return;
      if (result.isSuccess) {
        setState(() => _preview = result.data);
      } else {
        showError(context, result.message);
      }
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirm() async {
    if (_preview?['canImport'] != true || _busy) return;
    setState(() => _busy = true);
    try {
      await runAction(context, '/notes/import', 'confirm', {
        'sourcePackage': _preview!['sourcePackage'],
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => RemotePage(
    path: widget.path,
    builder: (context, data, reload) {
      _maximumBytes = asInt(data['maxArchiveBytes'], 16 * 1024 * 1024);
      _maximumFiles = asInt(data['maxFiles'], 100);
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          FeatureHeading(
            'Dokumente importieren',
            subtitle: 'Word, Markdown und Obsidian.',
            actions: [
              FilledButton.icon(
                onPressed: _busy ? null : _pick,
                icon: const Icon(Icons.upload_file),
                label: const Text('Dateien auswählen'),
              ),
            ],
          ),
          const Text(
            'Wähle Word- oder Markdown-Dateien aus. Einen Obsidian-Export kannst du als ZIP auswählen. Prüfe anschließend die Vorschau, bevor die Dokumente in deinem Konto angelegt werden.',
          ),
          const SizedBox(height: 16),
          if (_busy) const LinearProgressIndicator(),
          if (data['limitations'] is List)
            ExpansionTile(
              title: const Text('Hinweise zum Import'),
              children: [
                for (final limitation in data['limitations'] as List)
                  ListTile(
                    leading: const Icon(Icons.info_outline),
                    title: Text('$limitation'),
                  ),
              ],
            ),
          if (_preview != null) ...[
            for (final preview in asMaps(_preview!['previews']))
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        asString(preview['title']),
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 6),
                      Text(asString(preview['sourceFilename'])),
                      Text(preview['kind'] == 'sermon' ? 'Predigt' : 'Notiz'),
                      if (preview['tags'] is List)
                        Wrap(
                          spacing: 6,
                          children: [
                            for (final tag in preview['tags'] as List)
                              Chip(label: Text('$tag')),
                          ],
                        ),
                      for (final passage in asMaps(preview['passages']))
                        Text(
                          '${asString(passage['reference'])}'
                          '${passage['resourceId'] == null ? '' : ' · ${passage['resourceId']}'}',
                        ),
                      if (preview['sermon'] is Map)
                        Text(
                          [
                                sermonFormats[asString(
                                  asMap(preview['sermon'])['format'],
                                )],
                                asMap(preview['sermon'])['statusName'],
                                asMap(preview['sermon'])['date'],
                                asMap(preview['sermon'])['series'],
                              ]
                              .where(
                                (value) => value != null && '$value'.isNotEmpty,
                              )
                              .join(' · '),
                        ),
                      if (preview['warnings'] is List)
                        for (final warning in preview['warnings'] as List)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Text(
                              warning is Map
                                  ? asString(
                                      warning['message'],
                                      warning.toString(),
                                    )
                                  : '$warning',
                            ),
                          ),
                      const Divider(height: 28),
                      HtmlContent(html: asString(preview['html'])),
                    ],
                  ),
                ),
              ),
            if (_preview!['canImport'] != true)
              const Text(
                'Der Import enthält noch Fehler. Prüfe die Quelldateien und lade sie erneut hoch.',
              ),
            for (final issue in asMaps(_preview!['issues']))
              ListTile(
                leading: const Icon(Icons.error_outline),
                title: Text(switch (asString(issue['code'])) {
                  'invalidPassage' =>
                    'Ungültige Bibelstelle: ${issue['reference']}',
                  'invalidResource' =>
                    'Nicht verfügbare Bibel: ${issue['resourceId']} (${issue['reference']})',
                  'invalidTag' => 'Ungültiges Schlagwort: ${issue['tag']}',
                  'tooManyTags' =>
                    'Höchstens ${issue['maximum']} Schlagwörter pro Dokument.',
                  'tooManyPassages' =>
                    'Höchstens ${issue['maximum']} Bibelstellen pro Dokument.',
                  _ => 'Die Quelldatei konnte nicht übernommen werden.',
                }),
              ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _busy || _preview!['canImport'] != true
                  ? null
                  : _confirm,
              icon: const Icon(Icons.check),
              label: const Text('Geprüfte Dokumente importieren'),
            ),
          ],
        ],
      );
    },
  );
}
