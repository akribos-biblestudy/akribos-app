import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/app_scope.dart';
import '../../core/api_client.dart';
import '../../widgets/common.dart';
import 'document_draft.dart';
import 'document_widgets.dart';
import 'rich_markdown_controller.dart';
import 'rich_markdown_editor.dart';
import '../reader/books.dart';
import '../reader/verse_text.dart';

class DocumentEditor extends StatefulWidget {
  const DocumentEditor({super.key, required this.path});
  final String path;

  @override
  State<DocumentEditor> createState() => _DocumentEditorState();
}

class _DocumentEditorState extends State<DocumentEditor>
    with WidgetsBindingObserver {
  final _title = TextEditingController();
  final _body = TextEditingController();
  final _rich = RichMarkdownController(markdown: '');
  final _editorScroll = ScrollController();
  final _editorFocus = FocusNode();
  final _detailsRevision = ValueNotifier<int>(0);
  final _storage = const FlutterSecureStorage();
  Json? _data;
  Json _links = {};
  DocumentDraft? _draft;
  Timer? _timer;
  Future<bool>? _saving;
  Future<void> _draftWrites = Future.value();
  String? _draftKey;
  String? _error;
  bool _loading = true;
  bool _preview = false;
  bool _busy = false;
  bool _recovering = false;
  bool _initialized = false;
  bool _conflict = false;
  bool _draftStorageError = false;
  late AppScope _scope;

  String get _id => Uri.parse(widget.path).path.split('/').last;
  bool get _isSermon => asMap(_data?['document'])['kind'] == 'sermon';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _title.addListener(_changed);
    _body.addListener(_bodyChanged);
    _rich.addListener(_syncRichBody);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scope = AppScope.of(context);
    _scope.setNavigationGuard(this, _beforeNavigate);
    if (!_initialized) {
      _initialized = true;
      _load(recover: true);
    }
  }

  @override
  void dispose() {
    if (_initialized) _scope.setNavigationGuard(this, null);
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _title.dispose();
    _body.dispose();
    _rich.dispose();
    _editorScroll.dispose();
    _editorFocus.dispose();
    _detailsRevision.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _syncRichBody();
      _persistDraft();
      unawaited(_save());
    }
  }

  Future<void> _load({bool recover = false}) async {
    try {
      final data = await _scope.api.page(widget.path);
      if (!mounted) return;
      final document = asMap(data['document']);
      _recovering = true;
      _draft = DocumentDraft(
        title: asString(document['title']),
        markdown: asString(document['bodyMarkdown']),
        revision: asInt(document['revision']),
      );
      _title.text = _draft!.title;
      _body.text = _draft!.markdown;
      if (recover) _preview = _scope.eInk && _draft!.markdown.trim().isNotEmpty;
      _draftKey =
          'document-draft:${_scope.api.origin.origin}:${asMap(data['user'])['id']}:$_id';
      _recovering = false;
      setState(() {
        _data = data;
        _loading = false;
        _error = null;
      });
      _detailsRevision.value++;
      if (recover) await _recoverDraft();
      try {
        final links = asMap(await _scope.api.get('/api/documents/$_id/links'));
        if (mounted) {
          setState(() => _links = links);
          _detailsRevision.value++;
        }
      } catch (_) {
        /* Link discovery must not block editing the document. */
      }
    } on AppRedirect catch (redirect) {
      if (mounted) await _scope.open(redirect.location);
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '$error';
        });
      }
    }
  }

  Future<void> _recoverDraft() async {
    try {
      final raw = await _storage.read(key: _draftKey!);
      if (raw == null || !mounted) return;
      final saved = asMap(jsonDecode(raw));
      if (saved['title'] == _draft!.title &&
          saved['markdown'] == _draft!.markdown) {
        return;
      }
      final restore = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('Lokalen Entwurf wiederherstellen?'),
          content: Text(
            asInt(saved['revision']) == _draft!.revision
                ? 'Auf diesem Gerät gibt es noch ungespeicherte Änderungen.'
                : 'Auf diesem Gerät gibt es einen Entwurf. Der Serverstand hat sich inzwischen geändert. Der Entwurf wird zur Prüfung geöffnet und nicht automatisch überschrieben.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Serverstand verwenden'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Entwurf öffnen'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      if (restore == true) {
        _recovering = true;
        _draft!.title = _title.text = asString(saved['title']);
        _draft!.markdown = _body.text = asString(saved['markdown']);
        // Retain the original revision: a stale draft must encounter the normal
        // server conflict instead of overwriting a newer remote document.
        _draft!.revision = asInt(saved['revision']);
        _preview = false;
        _recovering = false;
        setState(() {});
      } else {
        await _storage.delete(key: _draftKey!);
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Der lokale Entwurf konnte nicht gelesen werden.',
        );
      }
    }
  }

  // The source controller is the persistence boundary. Quill selections never
  // notify this bridge; loads/recovery replace source without starting autosave.
  void _bodyChanged() {
    if (_rich.markdown != _body.text) _rich.setMarkdown(_body.text);
    _changed();
  }

  void _syncRichBody() {
    final markdown = _rich.markdown;
    if (markdown == _body.text) return;
    _body.value = TextEditingValue(
      text: markdown,
      selection: TextSelection.collapsed(offset: markdown.length),
    );
  }

  void _setBusy(bool value) {
    if (!mounted) return;
    setState(() => _busy = value);
    _detailsRevision.value++;
  }

  void _changed() {
    if (_recovering || _draft == null) return;
    if (_draft!.title == _title.text && _draft!.markdown == _body.text) return;
    _draft!.title = _title.text;
    _draft!.markdown = _body.text;
    _persistDraft();
    _timer?.cancel();
    _timer = Timer(
      const Duration(milliseconds: 1200),
      () => unawaited(_save()),
    );
    setState(() {});
  }

  void _persistDraft() {
    if (_draftKey == null || _draft == null) return;
    final key = _draftKey!;
    final value = _draft!.dirty ? jsonEncode(_draft!.snapshot()) : null;
    _draftWrites = _draftWrites
        .then((_) async {
          if (value == null) {
            await _storage.delete(key: key);
          } else {
            await _storage.write(key: key, value: value);
          }
          _draftStorageError = false;
        })
        .catchError((Object error) {
          _draftStorageError = true;
          if (mounted) {
            setState(
              () => _error = 'Der lokale Entwurf konnte nicht gesichert werden. Bitte online speichern.',
            );
          }
        });
  }

  Future<bool> _save() async {
    // Read the current editor synchronously before capturing the request, also
    // when a lifecycle event/navigation follows the last keystroke immediately.
    _syncRichBody();
    _timer?.cancel();
    while (_saving != null) {
      if (!await _saving!) return false;
    }
    if (_draft == null || !_draft!.dirty) return true;
    final submitted = _draft!.snapshot();
    final completer = Completer<bool>();
    _saving = completer.future;
    if (mounted) setState(() {});
    try {
      final response = asMap(
        await _scope.api.send('PATCH', '/api/documents/$_id', data: submitted),
      );
      final document = asMap(response['document']);
      if (document.isEmpty) {
        throw StateError('Das Dokument wurde nicht bestätigt.');
      }
      _draft!.acknowledge(submitted, asInt(document['revision']));
      _data?['document'] = document;
      _persistDraft();
      if (mounted) {
        setState(() {
          _error = null;
          _conflict = false;
        });
      }
      completer.complete(true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = 'Speichern nicht möglich: $error';
          _conflict = error is ApiException && error.status == 409;
        });
      }
      completer.complete(false);
    } finally {
      _saving = null;
      if (mounted) setState(() {});
    }
    return completer.future;
  }

  Future<bool> _beforeNavigate() async {
    if (await _save() && !(_draft?.dirty ?? false)) return true;
    if (!mounted) return false;
    final choice = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Änderungen sind noch nicht gespeichert'),
        content: const Text(
          'Dein Text bleibt als lokaler Entwurf erhalten. Du kannst erneut speichern, hierbleiben oder die lokalen Änderungen ausdrücklich verwerfen.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'stay'),
            child: const Text('Hierbleiben'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'discard'),
            child: const Text('Verwerfen'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'keep'),
            child: const Text('Auf Gerät behalten und verlassen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'save'),
            child: const Text('Erneut speichern'),
          ),
        ],
      ),
    );
    if (choice == 'discard') {
      _timer?.cancel();
      _draft?.discard();
      _recovering = true;
      _title.text = _draft?.title ?? _title.text;
      _body.text = _draft?.markdown ?? _body.text;
      _recovering = false;
      _persistDraft();
      await _draftWrites;
      return true;
    }
    if (choice == 'keep') {
      _timer?.cancel();
      _persistDraft();
      await _draftWrites;
      if (_draftStorageError) return false;
      return true;
    }
    if (choice == 'save') return await _save() && !(_draft?.dirty ?? false);
    return false;
  }

  Future<void> _resolveConflict() async {
    _timer?.cancel();
    try {
      final response = asMap(await _scope.api.get('/api/documents/$_id'));
      final current = asMap(response['document']);
      if (current.isEmpty || !mounted) return;
      final local = _draft!.snapshot();
      final choice = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Fassungen vergleichen'),
          content: SizedBox(
            width: 720,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Auf dem Server: ${current['title']}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  SelectableText(asString(current['bodyMarkdown'])),
                  const Divider(height: 32),
                  Text(
                    'Dein Entwurf: ${local['title']}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  SelectableText(asString(local['markdown'])),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Zurück zum Entwurf'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, 'server'),
              child: const Text('Serverfassung übernehmen'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, 'local'),
              child: const Text('Server durch meinen Entwurf ersetzen'),
            ),
          ],
        ),
      );
      if (choice == null || !mounted) return;
      _recovering = true;
      _draft = DocumentDraft(
        title: asString(current['title']),
        markdown: asString(current['bodyMarkdown']),
        revision: asInt(current['revision']),
      );
      if (choice == 'local') {
        _draft!.title = asString(local['title']);
        _draft!.markdown = asString(local['markdown']);
      }
      _title.text = _draft!.title;
      _body.text = _draft!.markdown;
      _data!['document'] = current;
      _recovering = false;
      _persistDraft();
      setState(() {
        _error = null;
        _conflict = false;
      });
      if (choice == 'local') await _save();
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }

  Future<void> _mutate(String action, Json fields) async {
    if (_busy) return;
    _setBusy(true);
    try {
      if (!await _flush() || !mounted) return;
      final result = await runAction(context, widget.path, action, {
        ...fields,
        'revision': _draft!.revision,
      });
      if (result?.isSuccess == true && mounted) await _load();
    } finally {
      _setBusy(false);
    }
  }

  Future<bool> _flush() async {
    do {
      if (!await _save()) return false;
    } while (_draft?.dirty == true);
    return true;
  }

  Future<void> _form(
    String title,
    String action,
    List<FeatureField> fields, {
    Json extra = const {},
  }) async {
    final values = await editFeatureFields(context, title, fields);
    if (values != null && mounted) await _mutate(action, {...extra, ...values});
  }

  Future<void> _metadata() async {
    final doc = asMap(_data?['document']);
    final fields = await editFeatureFields(context, 'Ausarbeitung planen', [
      FeatureField(
        'sermonStatus',
        'Vorbereitungsschritt',
        value: asString(doc['sermonStatus']),
        options: itemOptions(
          asMap(_data?['sermonBoard'])['columns'],
          label: 'name',
        ),
      ),
      FeatureField(
        'sermonFormat',
        'Format',
        value: asString(doc['sermonFormat']),
        options: sermonFormats,
      ),
      FeatureField(
        'sermonDate',
        'Termin (JJJJ-MM-TT)',
        value: calendarDate(doc['sermonDate']),
      ),
      FeatureField(
        'sermonSeries',
        'Serie',
        value: asString(doc['sermonSeries']),
      ),
    ]);
    if (fields == null || !mounted) return;
    _setBusy(true);
    try {
      if (!await _flush()) return;
      await _scope.api.send(
        'PATCH',
        '/api/documents/$_id',
        data: {
          ..._draft!.snapshot(),
          ...fields,
          'sermonDate': fields['sermonDate'] == ''
              ? null
              : fields['sermonDate'],
        },
      );
      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      _setBusy(false);
    }
  }

  void _insert(String markdown) {
    if (_busy || _preview) return;
    _rich.insertMarkdown(markdown);
    _editorFocus.requestFocus();
  }

  Future<void> _quoteBible() async {
    final bibles = asMaps(_data?['bibles']);
    if (bibles.isEmpty) return;
    final fields = await editFeatureFields(context, 'Bibeltext zitieren', [
      FeatureField(
        'bible',
        'Übersetzung',
        value: asString(bibles.first['id']),
        options: itemOptions(bibles, label: 'tabTitle'),
      ),
      FeatureField(
        'book',
        'Buch',
        value: '43',
        options: {for (final book in bibleBooks) '${book.id}': book.name},
      ),
      const FeatureField('chapter', 'Kapitel', value: '3', required: true),
      const FeatureField('verse', 'Von Vers', value: '16', required: true),
      const FeatureField('end', 'Bis Vers (optional)'),
    ], submit: 'Zitat einfügen');
    if (fields == null || !mounted) return;
    try {
      final book = asInt(fields['book']);
      final chapter = asInt(fields['chapter']);
      final start = asInt(fields['verse']);
      final end = asInt(fields['end'], start);
      if (chapter < 1 || start < 1 || end < start) {
        throw StateError('Bitte einen gültigen Versbereich eingeben.');
      }
      final response = asMap(
        await _scope.api.get(
          '/api/reader/bibles/${Uri.encodeComponent(asString(fields['bible']))}/$book/$chapter',
        ),
      );
      final verses = asMaps(response['verses'])
          .where(
            (verse) =>
                asInt(verse['verse']) <= end &&
                asInt(verse['verseEnd'], asInt(verse['verse'])) >= start,
          )
          .toList();
      if (verses.isEmpty) {
        throw StateError('Für diesen Versbereich ist kein Text verfügbar.');
      }
      final reference = referenceLabel({
        'book': book,
        'chapter': chapter,
        'verse': start,
        if (end != start) 'verseEnd': end,
      });
      final text = verses
          .map(
            (verse) =>
                '${verse['verse']} ${versePlainText(verse['segments'] as List? ?? [])}',
          )
          .join(' ');
      final label = asString(
        bibles.firstWhere(
          (bible) => bible['id'] == fields['bible'],
        )['tabTitle'],
      );
      _insert(
        '\n> $text\n>\n> [$reference](/${Uri.encodeComponent(reference)}) · $label\n\n',
      );
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }

  Future<void> _linkDocument() async {
    final search = await editFeatureFields(
      context,
      'Eigene Gedanken verknüpfen',
      [const FeatureField('query', 'Titel oder Suchbegriff')],
      submit: 'Suchen',
    );
    if (search == null || !mounted) return;
    try {
      final result = asMap(
        await _scope.api.get(
          '/api/documents?q=${Uri.encodeComponent(asString(search['query']))}',
        ),
      );
      final documents = asMaps(result['documents'])
          .where((doc) => doc['id'] != _id)
          .toList();
      if (!mounted) return;
      if (documents.isEmpty) {
        showError(context, 'Keine passenden Dokumente gefunden.');
        return;
      }
      final selected = await editFeatureFields(context, 'Dokument auswählen', [
        FeatureField(
          'id',
          'Dokument',
          value: asString(documents.first['id']),
          options: itemOptions(documents),
        ),
      ], submit: 'Verknüpfen');
      if (selected == null || !mounted) return;
      final document = documents.firstWhere(
        (doc) => doc['id'] == selected['id'],
      );
      final title = asString(document['title'])
          .replaceAll('[', r'\[')
          .replaceAll(']', r'\]');
      _insert('[$title](/notes/${document['id']})');
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }

  Future<void> _upload() async {
    if (!await _save() || !mounted) return;
    final result = await FilePicker.pickFiles();
    if (result.isEmpty || !mounted) return;
    _setBusy(true);
    try {
      if (!await _flush()) return;
      for (final file in result) {
        final size = await file.length();
        if (size == null || size > 50 * 1024 * 1024) {
          throw StateError('Eine Anlage darf höchstens 50 MiB groß sein.');
        }
        final bytes = await file.readAsBytes();
        final response = asMap(
          await _scope.api.send(
            'POST',
            '/api/documents/$_id/attachments',
            data: FormData.fromMap({
              'revision': _draft!.revision,
              'file': MultipartFile.fromBytes(bytes, filename: file.name),
            }),
          ),
        );
        _draft!.revision = asInt(response['revision']);
      }
      await _load();
    } catch (error) {
      // Reload lists after a partial batch, retaining the already saved text.
      await _load();
      if (mounted) {
        setState(
          () => _error =
              'Einige Anlagen konnten nicht gespeichert werden: $error',
        );
      }
    } finally {
      _setBusy(false);
    }
  }

  Future<void> _deleteAttachment(Json attachment) async {
    if (!await _save() || !mounted) return;
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Anlage entfernen?'),
        content: Text(asString(attachment['filename'])),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Entfernen'),
          ),
        ],
      ),
    );
    if (approved != true) return;
    if (!mounted) return;
    _setBusy(true);
    try {
      if (!await _flush()) return;
      await _scope.api.send(
        'DELETE',
        '/api/documents/$_id/attachments/${attachment['id']}?revision=${_draft!.revision}',
      );
      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      _setBusy(false);
    }
  }

  Future<void> _export(String format) async {
    if (!await _flush() || !mounted) return;
    try {
      await _scope.api.download('/notes/$_id/export.$format');
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  Widget _details() {
    final data = _data!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_isSermon)
          Card(
            child: ListTile(
              leading: const Icon(Icons.event_note),
              title: const Text('Planung'),
              subtitle: Text(
                [
                  sermonFormats[asMap(data['document'])['sermonFormat']] ??
                      'Ausarbeitung',
                  shortDate(asMap(data['document'])['sermonDate']),
                  asString(asMap(data['document'])['sermonSeries']),
                ].where((value) => value.isNotEmpty).join(' · '),
              ),
              trailing: const Icon(Icons.edit_outlined),
              onTap: _metadata,
            ),
          ),
        Card(
          child: ExpansionTile(
            leading: const Icon(Icons.label_outline),
            title: const Text('Tags'),
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final tag in asMaps(data['tags']))
                      Chip(label: Text(asString(tag['path']))),
                    ActionChip(
                      label: const Text('Bearbeiten'),
                      avatar: const Icon(Icons.edit, size: 16),
                      onPressed: () => _form('Tags bearbeiten', 'syncTags', [
                        FeatureField(
                          'tags',
                          'Tags, durch Komma getrennt',
                          value: asMaps(data['tags'])
                              .map((tag) => asString(tag['path']))
                              .join(', '),
                        ),
                      ]),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Card(
          child: ExpansionTile(
            initiallyExpanded: true,
            leading: const Icon(Icons.menu_book),
            title: const Text('Bibelstellen'),
            children: [
              for (final passage in asMaps(data['passages']))
                ListTile(
                  title: Text(asString(passage['reference'])),
                  onTap: () => _scope.open(
                    '/${Uri.encodeComponent(asString(passage['reference']))}',
                  ),
                  trailing: IconButton(
                    tooltip: 'Bibelstelle entfernen',
                    icon: const Icon(Icons.close),
                    onPressed: () =>
                        _mutate('removePassage', {'passageId': passage['id']}),
                  ),
                ),
              TextButton.icon(
                onPressed: () => _form('Bibelstelle verknüpfen', 'addPassage', [
                  const FeatureField(
                    'passage',
                    'Bibelstelle, z. B. Joh 3,16–18',
                    required: true,
                  ),
                  FeatureField(
                    'resourceId',
                    'Übersetzung',
                    options: itemOptions(
                      data['bibles'],
                      label: 'tabTitle',
                      empty: 'Übersetzungsunabhängig',
                    ),
                  ),
                ]),
                icon: const Icon(Icons.add),
                label: const Text('Bibelstelle hinzufügen'),
              ),
            ],
          ),
        ),
        if (_isSermon) ...[
          Card(
            child: ExpansionTile(
              leading: const Icon(Icons.attach_file),
              title: const Text('Anlagen'),
              children: [
                for (final file in asMaps(data['attachments']))
                  ListTile(
                    title: Text(asString(file['filename'])),
                    onTap: () => _scope.api.download(
                      '/api/documents/$_id/attachments/${file['id']}',
                    ),
                    trailing: IconButton(
                      tooltip: 'Anlage entfernen',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _deleteAttachment(file),
                    ),
                  ),
                TextButton.icon(
                  onPressed: _busy ? null : _upload,
                  icon: const Icon(Icons.upload_file),
                  label: const Text('Dateien hinzufügen'),
                ),
              ],
            ),
          ),
          Card(
            child: ExpansionTile(
              leading: const Icon(Icons.collections_bookmark_outlined),
              title: const Text('Stellensammlungen'),
              children: [
                for (final collection in asMaps(data['collections']))
                  ListTile(
                    title: Text(asString(collection['title'])),
                    onTap: () => _scope.open('/lists/${collection['id']}'),
                    trailing: IconButton(
                      tooltip: 'Verknüpfung lösen',
                      icon: const Icon(Icons.link_off),
                      onPressed: () => _mutate('collection', {
                        'collectionAction': 'remove',
                        'listId': collection['id'],
                      }),
                    ),
                  ),
                if (asMaps(data['availableCollections']).isNotEmpty)
                  TextButton.icon(
                    onPressed: () => _form(
                      'Sammlung verknüpfen',
                      'collection',
                      [
                        FeatureField(
                          'listId',
                          'Sammlung',
                          value: asString(
                            asMaps(data['availableCollections']).first['id'],
                          ),
                          options: itemOptions(data['availableCollections']),
                        ),
                      ],
                      extra: {'collectionAction': 'add'},
                    ),
                    icon: const Icon(Icons.link),
                    label: const Text('Vorhandene verknüpfen'),
                  ),
                TextButton.icon(
                  onPressed: () => _form(
                    'Neue Sammlung',
                    'collection',
                    [const FeatureField('title', 'Titel', required: true)],
                    extra: {'collectionAction': 'create'},
                  ),
                  icon: const Icon(Icons.add),
                  label: const Text('Anlegen und verknüpfen'),
                ),
              ],
            ),
          ),
          Card(
            child: ExpansionTile(
              leading: const Icon(Icons.history),
              title: const Text('Bereits gehalten'),
              children: [
                for (final delivery in asMaps(data['sermonDeliveries']))
                  ListTile(
                    title: Text(asString(delivery['location'])),
                    subtitle: Text(shortDate(delivery['date'])),
                    trailing: IconButton(
                      tooltip: 'Durchführung entfernen',
                      icon: const Icon(Icons.close),
                      onPressed: () => _mutate('removeDelivery', {
                        'deliveryId': delivery['id'],
                      }),
                    ),
                  ),
                TextButton.icon(
                  onPressed: () =>
                      _form('Durchführung festhalten', 'addDelivery', [
                        FeatureField(
                          'date',
                          'Datum (JJJJ-MM-TT)',
                          value: calendarDate(DateTime.now().toIso8601String()),
                          required: true,
                        ),
                        const FeatureField('location', 'Ort', required: true),
                      ]),
                  icon: const Icon(Icons.add),
                  label: const Text('Durchführung hinzufügen'),
                ),
              ],
            ),
          ),
        ],
        if (asMaps(_links['incoming']).isNotEmpty ||
            asMaps(_links['outgoing']).isNotEmpty)
          Card(
            child: ExpansionTile(
              leading: const Icon(Icons.link),
              title: const Text('Verknüpfte Gedanken'),
              children: [
                for (final link in [
                  ...asMaps(_links['incoming']),
                  ...asMaps(_links['outgoing']),
                ])
                  ListTile(
                    title: Text(asString(link['title'])),
                    onTap: () => _scope.open('/notes/${link['id']}'),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Future<void> _showDetails() async {
    _editorFocus.unfocus();
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .75,
        minChildSize: .35,
        maxChildSize: .95,
        builder: (context, scrollController) => ValueListenableBuilder<int>(
          valueListenable: _detailsRevision,
          builder: (context, _, child) => AbsorbPointer(
            absorbing: _busy,
            child: SingleChildScrollView(
              controller: scrollController,
              padding: EdgeInsets.fromLTRB(
                16,
                0,
                16,
                24 + MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: _details(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _insertMenu() => PopupMenuButton<Object>(
    tooltip: 'Einfügen',
    enabled: !_busy,
    icon: const Icon(Icons.add),
    onSelected: (value) async {
      if (_busy || _preview) return;
      if (value == 'bible') {
        await _quoteBible();
      } else if (value == 'document') {
        await _linkDocument();
      } else if (value is RichMarkdownBlock) {
        await insertRichMarkdownBlock(context, _rich, value);
      }
    },
    itemBuilder: (_) => const [
      PopupMenuItem(value: RichMarkdownBlock.paragraph, child: Text('Absatz')),
      PopupMenuItem(
        value: RichMarkdownBlock.heading1,
        child: Text('Überschrift 1'),
      ),
      PopupMenuItem(
        value: RichMarkdownBlock.heading2,
        child: Text('Überschrift 2'),
      ),
      PopupMenuItem(
        value: RichMarkdownBlock.heading3,
        child: Text('Überschrift 3'),
      ),
      PopupMenuItem(
        value: RichMarkdownBlock.bulletedList,
        child: Text('Aufzählung'),
      ),
      PopupMenuItem(
        value: RichMarkdownBlock.numberedList,
        child: Text('Nummerierte Liste'),
      ),
      PopupMenuItem(value: RichMarkdownBlock.quote, child: Text('Zitat')),
      PopupMenuItem(value: RichMarkdownBlock.code, child: Text('Codeblock')),
      PopupMenuItem(value: RichMarkdownBlock.rule, child: Text('Trennlinie')),
      PopupMenuItem(value: RichMarkdownBlock.table, child: Text('Tabelle')),
      PopupMenuItem(value: RichMarkdownBlock.footnote, child: Text('Fußnote')),
      PopupMenuDivider(),
      PopupMenuItem(value: 'bible', child: Text('Bibeltext zitieren')),
      PopupMenuItem(value: 'document', child: Text('Eigene Notiz verknüpfen')),
    ],
  );

  Widget _optionsMenu() => PopupMenuButton<String>(
    tooltip: 'Dokumentoptionen',
    enabled: !_busy,
    onSelected: (value) async {
      if (value == 'undo' || value == 'redo') {
        if (_preview || _busy) return;
        if (value == 'undo') {
          _rich.quill.undo();
        } else {
          _rich.quill.redo();
        }
      } else if (value == 'kind') {
        await _form('Dokumentart ändern', 'changeKind', [
          FeatureField(
            'kind',
            'Dokumentart',
            value: _isSermon ? 'sermon' : 'note',
            options: const {'note': 'Notiz', 'sermon': 'Ausarbeitung'},
          ),
        ]);
      } else {
        await _export(value);
      }
    },
    itemBuilder: (_) => [
      if (!_preview) ...[
        PopupMenuItem(
          value: 'undo',
          enabled: _rich.quill.hasUndo,
          child: const Text('Rückgängig'),
        ),
        PopupMenuItem(
          value: 'redo',
          enabled: _rich.quill.hasRedo,
          child: const Text('Wiederholen'),
        ),
        const PopupMenuDivider(),
      ],
      const PopupMenuItem(value: 'md', child: Text('Markdown exportieren')),
      const PopupMenuItem(value: 'docx', child: Text('Word exportieren')),
      const PopupMenuItem(value: 'pdf', child: Text('PDF exportieren')),
      if (!_preview)
        const PopupMenuItem(value: 'kind', child: Text('Dokumentart ändern')),
    ],
  );

  Widget _errorBanner() => ConstrainedBox(
    constraints: const BoxConstraints(maxHeight: 180),
    child: SingleChildScrollView(
      child: Card(
        color: Theme.of(context).colorScheme.errorContainer,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_error!),
              Wrap(
                spacing: 8,
                children: [
                  if (!_preview) ...[
                    TextButton(
                      onPressed: _save,
                      child: const Text('Speichern wiederholen'),
                    ),
                    if (_conflict)
                      TextButton(
                        onPressed: _resolveConflict,
                        child: const Text('Fassungen vergleichen'),
                      ),
                  ],
                  TextButton(
                    onPressed: () async {
                      await Clipboard.setData(
                        ClipboardData(text: _rich.markdown),
                      );
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Entwurf kopiert.')),
                        );
                      }
                    },
                    child: const Text('Entwurf kopieren'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _header(String saveLabel) {
    final titleStyle = Theme.of(context).textTheme.headlineSmall;
    final titleHeight =
        MediaQuery.textScalerOf(context).scale(titleStyle?.fontSize ?? 24) *
            (titleStyle?.height ?? 1.3) *
            2 +
        40;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SegmentedButton<bool>(
              key: const Key('document-mode'),
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: false, label: Text('Bearbeiten')),
                ButtonSegment(value: true, label: Text('Lesen')),
              ],
              selected: {_preview},
              onSelectionChanged: _busy
                  ? null
                  : (values) {
                      FocusScope.of(context).unfocus();
                      // Read the same local model, even offline. Switching view
                      // neither changes its content nor replaces its history.
                      setState(() => _preview = values.single);
                    },
            ),
            // Reserve the action slots in reading mode so switching
            // modes keeps the editor at the same vertical position.
            if (_preview)
              const SizedBox(width: 48, height: 48)
            else
              _insertMenu(),
            if (_preview)
              const SizedBox(width: 48, height: 48)
            else
              IconButton(
                tooltip: 'Details',
                onPressed: _busy ? null : _showDetails,
                icon: const Icon(Icons.tune),
              ),
            _optionsMenu(),
          ],
        ),
        SizedBox(
          height: titleHeight,
          child: Row(
            children: [
              Expanded(
                child: _preview
                    ? Text(
                        _title.text,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.headlineSmall,
                      )
                    : TextField(
                        controller: _title,
                        enabled: !_busy,
                        minLines: 1,
                        maxLines: 2,
                        keyboardType: TextInputType.text,
                        textInputAction: TextInputAction.done,
                        decoration: InputDecoration(
                          labelText: _isSermon
                              ? 'Titel der Ausarbeitung'
                              : 'Titel',
                        ),
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
              ),
              if (_preview)
                const SizedBox(width: 48, height: 48)
              else
                IconButton(
                  tooltip: saveLabel,
                  onPressed: _saving != null || _busy ? null : _save,
                  icon: Icon(
                    _saving != null
                        ? Icons.sync
                        : _draft!.dirty
                        ? Icons.save_outlined
                        : Icons.cloud_done_outlined,
                  ),
                ),
            ],
          ),
        ),
        if (_error != null) _errorBanner(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_data == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error ?? 'Dokument nicht verfügbar.'),
            TextButton(
              onPressed: () => _load(recover: true),
              child: const Text('Erneut versuchen'),
            ),
          ],
        ),
      );
    }
    final saveLabel = _saving != null
        ? 'Speichert …'
        : _draft!.dirty
        ? 'Speichern'
        : 'Gespeichert';
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: LayoutBuilder(
            builder: (context, constraints) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: constraints.maxHeight * .6,
                  ),
                  child: SingleChildScrollView(child: _header(saveLabel)),
                ),
                Expanded(
                  child: RichMarkdownEditor(
                    key: const Key('document-rich-editor'),
                    controller: _rich,
                    readOnly: _preview || _busy,
                    scrollController: _editorScroll,
                    focusNode: _editorFocus,
                    fontScale: (asInt(_data!['readerFontScale'], 100) / 100)
                        .clamp(.7, 2),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
