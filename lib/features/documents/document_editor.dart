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
import 'web_editor.dart';
import 'web_editor_controller.dart';

import 'package:url_launcher/url_launcher.dart';

class DocumentEditor extends StatefulWidget {
  const DocumentEditor({super.key, required this.path, this.webEditorBuilder});
  final String path;

  /// Tests supply a protocol peer; production always uses the isolated HTTPS page.
  final Widget Function(
    BuildContext,
    WebEditorController,
    Json?,
    bool,
    VoidCallback,
  )?
  webEditorBuilder;

  @override
  State<DocumentEditor> createState() => _DocumentEditorState();
}

class _DocumentEditorState extends State<DocumentEditor>
    with WidgetsBindingObserver {
  final _title = TextEditingController();
  final _body = TextEditingController();
  WebEditorController? _web;
  Json? _restore;
  bool _recoverLocal = false;
  int _webGeneration = 0;
  final _detailsRevision = ValueNotifier<int>(0);
  final _storage = const FlutterSecureStorage();
  Json? _data;
  Json _links = {};
  DocumentDraft? _draft;
  Future<bool>? _saving;
  Future<void> _draftWrites = Future.value();
  String? _draftKey;
  String? _queuedDraftSignature;
  bool _paused = false;
  String? _error;
  bool _loading = true;
  bool _preview = false;
  bool _busy = false;
  bool _initialized = false;
  bool _active = true;
  bool _seenWebInitialized = false;
  Future<void>? _backgrounding;
  bool _conflict = false;
  bool _draftStorageError = false;
  bool _draftReadFailed = false;
  bool _webSaveError = false;
  late AppScope _scope;

  String get _id => Uri.parse(widget.path).path.split('/').last;
  bool get _isSermon => asMap(_data?['document'])['kind'] == 'sermon';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scope = AppScope.of(context);
    _scope.setNavigationGuard(this, _beforeNavigate);
    final active = TickerMode.valuesOf(context).enabled;
    if (_active != active && _web?.initialized == true) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(_setActive(active));
      });
    }
    _active = active;
    if (!_initialized) {
      _initialized = true;
      _load(recover: true);
    }
  }

  Future<void> _setActive(bool active) async {
    if (_web?.initialized != true || _paused == !active) return;
    try {
      await _web!.command(active ? 'resume' : 'pause');
      _paused = !active;
      _webChanged();
      await _draftWrites;
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  @override
  void dispose() {
    if (_initialized) _scope.setNavigationGuard(this, null);
    WidgetsBinding.instance.removeObserver(this);
    _web?.removeListener(_webChanged);
    _web?.dispose();
    _title.dispose();
    _body.dispose();
    _detailsRevision.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _backgrounding ??= _background().whenComplete(
        () => _backgrounding = null,
      );
    } else if (state == AppLifecycleState.resumed && _active) {
      unawaited(
        (_backgrounding ?? Future<void>.value()).then((_) => _setActive(true)),
      );
    }
  }

  Future<void> _background() async {
    if (_paused) return;
    await _save(lock: true);
    await _setActive(false);
  }

  void _setSource(String markdown) {
    // Flutter records undo baselines only for valid selections. This also makes
    // the first menu insertion undoable before the source field was focused.
    _body.value = TextEditingValue(
      text: markdown,
      selection: const TextSelection.collapsed(offset: 0),
    );
  }

  Future<void> _load({bool recover = false}) async {
    _draftReadFailed = false;
    _recoverLocal = false;
    try {
      final data = await _scope.api.page(widget.path);
      if (!mounted) return;
      final document = asMap(data['document']);
      _draft = DocumentDraft(
        title: asString(document['title']),
        markdown: asString(document['bodyMarkdown']),
        revision: asInt(document['revision']),
      );
      _title.text = _draft!.title;
      _setSource(_draft!.markdown);
      if (recover) _preview = _scope.eInk && _draft!.markdown.trim().isNotEmpty;
      _draftKey =
          'document-draft:${_scope.api.origin.origin}:${asMap(data['user'])['id']}:$_id';
      setState(() => _data = data);
      if (recover) await _recoverDraft();
      if (!mounted) return;
      if (_draftReadFailed) {
        setState(() => _loading = false);
        return;
      }
      _createWeb(restore: _recoverLocal ? _draft!.snapshot() : null);
      setState(() {
        _loading = false;
      });
      _detailsRevision.value++;
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
        _recoverLocal = true;
        _draft!.title = _title.text = asString(saved['title']);
        _draft!.markdown = asString(saved['markdown']);
        _setSource(_draft!.markdown);
        // Retain the original revision: a stale draft must encounter the normal
        // server conflict instead of overwriting a newer remote document.
        _draft!.revision = asInt(saved['revision']);
        _preview = false;
        setState(() {});
      } else {
        await _storage.delete(key: _draftKey!);
      }
    } catch (_) {
      _draftReadFailed = true;
      if (mounted) {
        setState(
          () => _error = 'Der lokale Entwurf konnte nicht gelesen werden.',
        );
      }
    }
  }

  void _setBusy(bool value) {
    if (!mounted) return;
    setState(() => _busy = value);
    _detailsRevision.value++;
  }

  void _createWeb({Json? restore}) {
    _web?.removeListener(_webChanged);
    _web?.dispose();
    _restore = restore;
    _seenWebInitialized = false;
    _paused = false;
    _webGeneration++;
    _web = WebEditorController(
      documentId: _id,
      userId: asString(asMap(_data?['user'])['id']),
    )..addListener(_webChanged);
    _web!.onNavigate = (path) => unawaited(_openWebLink(path));
  }

  void _webChanged() {
    final web = _web;
    if (!mounted || web == null || !web.initialized) return;
    if (!_seenWebInitialized) {
      _seenWebInitialized = true;
      if (!_active) unawaited(_setActive(false));
    }
    final snapshot = web.snapshot;
    if (snapshot != null) {
      final saved = web.savedSnapshot;
      if (saved != null) _draft!.acknowledge(saved, asInt(saved['revision']));
      _draft!.title = _title.text = asString(snapshot['title']);
      _draft!.markdown = asString(snapshot['markdown']);
      _setSource(_draft!.markdown);
      _draft!.revision = asInt(snapshot['revision']);
      _conflict = snapshot['status'] == 'conflict';
      if (snapshot['status'] == 'saved') {
        _data?['document'] = {
          ...asMap(_data?['document']),
          'title': _draft!.title,
          'bodyMarkdown': _draft!.markdown,
          'revision': _draft!.revision,
        };
      }
      _persistDraft();
    }
    setState(() {
      if (web.error != null) _error = web.error;
      if (snapshot?['status'] == 'error') {
        _webSaveError = true;
        _error = 'Änderungen konnten nicht gespeichert werden. Bitte erneut speichern.';
      } else if (snapshot?['status'] == 'saved' && _webSaveError) {
        _webSaveError = false;
        if (!_draftStorageError) _error = null;
      }
      if (_conflict) _error = 'Der Serverstand hat sich geändert. Bitte die Fassungen vergleichen.';
    });
  }

  Future<void> _openWebLink(String path) async {
    final parsed = Uri.tryParse(path);
    if (parsed == null) return;
    final uri = _scope.api.origin.resolveUri(parsed);
    if (!['https', 'http', 'mailto'].contains(uri.scheme) ||
        uri.userInfo.isNotEmpty) {
      return;
    }
    try {
      if (uri.scheme != 'mailto' && uri.origin == _scope.api.origin.origin) {
        if (uri.path.startsWith('/app/editor/')) return;
        await _scope.open(
          '${uri.path}${uri.hasQuery ? '?${uri.query}' : ''}${uri.hasFragment ? '#${uri.fragment}' : ''}',
        );
      } else if (await _beforeNavigate() &&
          mounted &&
          await confirmAction(
            context,
            'Externen Link öffnen?',
            uri.toString(),
          )) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } finally {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _active) unawaited(_setActive(true));
      });
    }
  }

  Future<void> _retryEditor() async {
    if (!mounted) return;
    if (_web?.initialized == true &&
        _web?.failed == true &&
        !await confirmAction(
          context,
          'Gesicherten Entwurf erneut laden?',
          'Der Editor antwortet nicht mehr. Der zuletzt gesicherte Entwurf bleibt erhalten; die allerletzten Eingaben konnten möglicherweise noch nicht übertragen werden.',
        )) {
      return;
    }
    if (!mounted) return;
    // A failed/unknown bridge never silently replaces the secured local draft.
    final restore = _draft?.dirty == true ? _draft!.snapshot() : null;
    setState(() {
      _error = null;
      _createWeb(restore: restore);
    });
  }

  void _persistDraft() {
    if (_draftKey == null || _draft == null) return;
    final key = _draftKey!;
    final value = _draft!.dirty ? jsonEncode(_draft!.snapshot()) : null;
    final signature = '$key:$value';
    if (_queuedDraftSignature == signature && !_draftStorageError) return;
    _queuedDraftSignature = signature;
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

  Future<bool> _save({bool lock = false}) async {
    if (_saving != null) {
      if (!await _saving!) return false;
      if (!lock) return true;
    }
    if (_web?.initialized != true) {
      return _draft?.dirty != true && _web?.snapshot == null;
    }
    final completer = Completer<bool>();
    _saving = completer.future;
    if (mounted) setState(() {});
    try {
      if (lock) {
        await _web!.command('prepareMutation');
      } else {
        await _web!.flush();
      }
      _webChanged();
      await _draftWrites;
      if (mounted) {
        setState(() {
          _error = null;
          _conflict = false;
        });
      }
      completer.complete(_draft?.dirty != true);
    } catch (error) {
      if (mounted) setState(() => _error = 'Speichern nicht möglich: $error');
      completer.complete(false);
    } finally {
      _saving = null;
      if (mounted) setState(() {});
    }
    return completer.future;
  }

  Future<bool> _beforeNavigate() async {
    if (await _save(lock: true) && !(_draft?.dirty ?? false)) {
      if (_web?.initialized == true) {
        try {
          await _web!.command('pause');
          _paused = true;
        } catch (_) {
          return false;
        }
      }
      return true;
    }
    var captured = false;
    try {
      await _web?.command('snapshot');
      _webChanged();
      captured = _web?.initialized == true;
    } catch (_) {
      /* Never claim the last keystroke is secured after a timeout. */
    }
    _persistDraft();
    await _draftWrites;
    if (!mounted) return false;
    final choice = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Änderungen sind noch nicht gespeichert'),
        content: Text(
          captured && !_draftStorageError
              ? 'Dein Text wurde als lokaler Entwurf gesichert. Du kannst erneut speichern, hierbleiben oder die lokalen Änderungen ausdrücklich verwerfen.'
              : 'Die neuesten Eingaben konnten nicht vollständig gesichert werden. Bitte bleibe hier und versuche erneut zu speichern. Verwerfen entfernt die lokalen Änderungen ausdrücklich.',
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
            onPressed: captured && !_draftStorageError
                ? () => Navigator.pop(context, 'keep')
                : null,
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
      _draft?.discard();
      _title.text = _draft?.title ?? _title.text;
      _setSource(_draft?.markdown ?? _body.text);
      _persistDraft();
      await _draftWrites;
      if (!mounted) return false;
      setState(() => _createWeb());
      return true;
    }
    if (choice == 'keep') {
      _persistDraft();
      await _draftWrites;
      if (_draftStorageError) return false;
      try {
        await _web!.command('pause');
        _paused = true;
      } catch (_) {
        return false;
      }
      return true;
    }
    if (choice == 'save') {
      if (await _save(lock: true)) {
        await _setActive(false);
        return true;
      }
    }
    await _setActive(true);
    return false;
  }

  Future<void> _resolveConflict() async {
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
      _setSource(_draft!.markdown);
      _data!['document'] = current;
      _persistDraft();
      setState(() {
        _error = null;
        _conflict = false;
      });
      setState(
        () =>
            _createWeb(restore: choice == 'local' ? _draft!.snapshot() : null),
      );
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }

  Future<void> _withMutation(Future<void> Function() operation) async {
    if (_busy || _web?.initialized != true) return;
    _setBusy(true);
    var prepared = false;
    var attempted = false;
    Object? failure;
    try {
      await _web!.command('prepareMutation');
      prepared = true;
      _webChanged();
      await _draftWrites;
      attempted = true;
      await operation();
    } catch (error) {
      failure = error;
    }
    // Even a partial attachment batch may have advanced the revision. Re-read
    // while input is still locked; never retry an uncertain mutation silently.
    if (prepared && attempted && mounted) {
      try {
        final data = await _scope.api.page(widget.path);
        if (mounted) {
          await _web!.command('finishMutation', {
            'document': asMap(data['document']),
          });
          prepared = false;
          _data = data;
          _detailsRevision.value++;
          _webChanged();
        }
      } catch (error) {
        failure ??= error;
      }
    }
    if (prepared) {
      try {
        await _web!.command('cancelMutation');
      } catch (error) {
        failure ??= error;
      }
    }
    if (failure != null && mounted) setState(() => _error = '$failure');
    _setBusy(false);
  }

  Future<void> _mutate(String action, Json fields) => _withMutation(() async {
    final result = await _scope.api.action(widget.path, action, {
      ...fields,
      'revision': _draft!.revision,
    });
    if (!result.isSuccess) {
      throw StateError(
        asString(
          result.data['message'],
          'Die Änderung konnte nicht gespeichert werden.',
        ),
      );
    }
  });

  Future<bool> _flush() => _save();

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
    await _withMutation(() async {
      await _scope.api.send(
        'PATCH',
        '/api/documents/$_id',
        data: {
          // The metadata endpoint requires the already flushed canonical text.
          // Input remains locked; this is not an independent text save queue.
          ..._draft!.snapshot(),
          ...fields,
          'sermonDate': fields['sermonDate'] == ''
              ? null
              : fields['sermonDate'],
        },
      );
    });
  }

  Future<void> _upload() async {
    if (!await _save() || !mounted) return;
    final result = await FilePicker.pickFiles();
    if (result.isEmpty || !mounted) return;
    await _withMutation(() async {
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
    });
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
    await _withMutation(() async {
      await _scope.api.send(
        'DELETE',
        '/api/documents/$_id/attachments/${attachment['id']}?revision=${_draft!.revision}',
      );
    });
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
    try {
      await _web?.command('blur');
    } catch (_) {
      return;
    }
    if (!mounted) return;
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

  Future<void> _insertMenu() async {
    try {
      await _web!.command('blur');
    } catch (_) {
      return;
    }
    if (!mounted) return;
    final kind = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .65,
        minChildSize: .35,
        maxChildSize: .9,
        builder: (context, scroll) => ListView(
          controller: scroll,
          children: [
            for (final item in const <(String, String)>[
              ('paragraph', 'Absatz'),
              ('heading-1', 'Überschrift 1'),
              ('heading-2', 'Überschrift 2'),
              ('heading-3', 'Überschrift 3'),
              ('bullet-list', 'Aufzählung'),
              ('ordered-list', 'Nummerierte Liste'),
              ('quote', 'Zitat'),
              ('code-block', 'Codeblock'),
              ('divider', 'Trennlinie'),
              ('table', 'Tabelle'),
              ('footnote', 'Fußnote'),
              ('bible', 'Bibeltext zitieren'),
            ])
              ListTile(
                title: Text(item.$2),
                onTap: () => Navigator.pop(context, item.$1),
              ),
          ],
        ),
      ),
    );
    if (kind == null || !mounted) return;
    try {
      await _web!.command('insert', {'kind': kind});
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }

  Widget _optionsMenu() => PopupMenuButton<String>(
    tooltip: 'Dokumentoptionen',
    enabled: !_busy,
    onSelected: (value) async {
      if (value == 'insert') {
        await _insertMenu();
      } else if (value == 'undo' || value == 'redo') {
        try {
          await _web!.command(value);
        } catch (error) {
          if (mounted) showError(context, error);
        }
      } else if (value == 'details') {
        await _showDetails();
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
        const PopupMenuItem(value: 'insert', child: Text('Einfügen …')),
        PopupMenuItem(
          value: 'undo',
          enabled: _web?.snapshot?['canUndo'] == true,
          child: const Text('Rückgängig'),
        ),
        PopupMenuItem(
          value: 'redo',
          enabled: _web?.snapshot?['canRedo'] == true,
          child: const Text('Wiederholen'),
        ),
        const PopupMenuItem(value: 'details', child: Text('Details')),
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
                      await Clipboard.setData(ClipboardData(text: _body.text));
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

  Future<void> _changeMode(bool reading) async {
    if (_busy || _web?.initialized != true || reading == _preview) return;
    if (!await _save(lock: true) || !mounted) {
      await _setActive(true);
      return;
    }
    try {
      await _web!.setMode(reading);
      await _web!.command('cancelMutation');
      await _draftWrites;
      if (mounted) setState(() => _preview = reading);
    } catch (error) {
      try {
        await _web!.command('cancelMutation');
      } catch (_) {
        /* keep original error */
      }
      if (mounted) setState(() => _error = '$error');
    }
  }

  Widget _header(String saveLabel) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        key: const Key('document-header-actions'),
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: SegmentedButton<bool>(
                  key: const Key('document-mode'),
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: false, label: Text('Bearbeiten')),
                    ButtonSegment(value: true, label: Text('Lesen')),
                  ],
                  selected: {_preview},
                  onSelectionChanged: _busy || _web?.initialized != true
                      ? null
                      : (values) => _changeMode(values.single),
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: saveLabel,
            onPressed: _saving != null || _busy ? null : _save,
            icon: Icon(
              _saving != null || _web?.snapshot?['status'] == 'saving'
                  ? Icons.sync
                  : _draft!.dirty
                  ? Icons.save_outlined
                  : Icons.cloud_done_outlined,
            ),
          ),
          _optionsMenu(),
        ],
      ),
      if (_error != null) _errorBanner(),
    ],
  );

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Center(
        child: _data == null
            ? const CircularProgressIndicator()
            : const Text('Entwurf wird geprüft …'),
      );
    }
    if (_data == null || _web == null) {
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
    final saveLabel = _saving != null || _web?.snapshot?['status'] == 'saving'
        ? 'Speichert …'
        : _draft!.dirty
        ? 'Speichern'
        : 'Gespeichert';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: _header(saveLabel),
        ),
        Expanded(
          key: const Key('document-text-surface'),
          child: KeyedSubtree(
            key: ValueKey(_webGeneration),
            child:
                widget.webEditorBuilder?.call(
                  context,
                  _web!,
                  _restore,
                  _preview,
                  _retryEditor,
                ) ??
                WebEditor(
                  api: _scope.api,
                  controller: _web!,
                  restore: _restore,
                  readOnly: _preview,
                  onRetry: _retryEditor,
                ),
          ),
        ),
      ],
    );
  }
}
