import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api_client.dart';
import '../../core/app_scope.dart';
import '../../widgets/common.dart';
import '../../widgets/remote_page.dart';
import '../search/search_screen.dart';
import 'books.dart';
import 'reader_dialogs.dart';
import 'reader_controller.dart';
import 'reader_lexicon_sheet.dart';
import 'reader_group_badge.dart';
import 'reader_tab_card.dart';
import 'highlight_dialog.dart';
import 'reader_notes.dart';
import 'reader_layout.dart';
import 'reader_state.dart';
import 'verse_text.dart';
import 'workspace_screen.dart';

class ReaderScreen extends StatelessWidget {
  const ReaderScreen({
    super.key,
    required this.path,
    this.controller,
    this.active = true,
  });
  final String path;
  final ReaderController? controller;
  final bool active;
  @override
  Widget build(BuildContext context) => RemotePage(
    path: path,
    builder: (context, data, reload) => _ReaderView(
      data: data,
      path: path,
      reload: reload,
      controller: controller,
      active: active,
    ),
  );
}

class _ReaderView extends StatefulWidget {
  const _ReaderView({
    required this.data,
    required this.path,
    required this.reload,
    required this.controller,
    required this.active,
  });
  final Json data;
  final String path;
  final Future<void> Function() reload;
  final ReaderController? controller;
  final bool active;
  @override
  State<_ReaderView> createState() => _ReaderViewState();
}

class _ReaderViewState extends State<_ReaderView> with WidgetsBindingObserver {
  late Json _data, _workspace, _searches;
  late String _savedState, _savedPath, _filterState;
  AppScope? _scope;
  Timer? _timer;
  Future<bool>? _saving;
  final _panes = <String, GlobalKey<_ChapterPaneState>>{};
  final _chapterCaches = <String, _ChapterCache>{};
  final _pendingPositions = <String, Json>{};
  final _columnsByTab = <String, Json>{};
  final _lexiconTabs = <String, Json>{};
  final _displayedTabs = <String, String>{};
  final _deferredPositions = <String, Json>{};
  final _activations = <Json>[];
  final _pageControllers = <String, PageController>{};
  Future<bool>? _switching;
  bool _activationInFlight = false;
  bool _discardPending = false;
  bool _phoneSplit = false;
  List<double> _phoneRatios = [.5, .5];
  List<String> _phoneSplitTiles = [];
  Json? _failedActivation;
  bool _busy = false, _dirty = false;
  bool _viewFiltersDirty = false;
  int _revision = 0;
  String? _saveError;
  String? _mobileTile;
  void _adopt([Json? incoming]) {
    _data = asMap(jsonDecode(jsonEncode(incoming ?? widget.data)));
    adoptReaderSelection(_data, _data);
    _workspace = asMap(_data['workspace']);
    _searches = asMap(_data['searchQueries']);
    _savedState = asString(_data['readerState']);
    _filterState = _savedState;
    _savedPath = '/${referenceLabel(asMap(_data['reference']))}';
    _mobileTile = asString(_workspace['focusedTileId']);
    for (final column in asMaps(_data['columns'])) {
      final tile = asMaps(
        _workspace['tiles'],
      ).firstWhere((tile) => tile['id'] == column['tileId'], orElse: () => {});
      final tab = activeTab(tile);
      _columnsByTab['${tab['id']}:${tab['resourceId']}'] = column;
    }
    _dirty = false;
    _viewFiltersDirty = false;
    _pendingPositions.clear();
  }

  @override
  void initState() {
    super.initState();
    _adopt();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final firstLoad = _scope == null;
    _scope = AppScope.of(context);
    _scope!.setNavigationGuard(this, widget.active ? _flush : null);
    _bindController();
    if (firstLoad) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _follow());
    }
  }

  @override
  void didUpdateWidget(_ReaderView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data != widget.data) _adopt();
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.detach(this);
      _bindController();
    }
    if (oldWidget.active != widget.active) {
      _scope?.setNavigationGuard(this, widget.active ? _flush : null);
      if (widget.active) unawaited(_follow());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _scope?.setNavigationGuard(this, null);
    widget.controller?.detach(this);
    for (final controller in _pageControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!widget.active) return;
    if (state == AppLifecycleState.inactive) {
      unawaited(_flush());
    }
    if (state == AppLifecycleState.resumed) {
      unawaited(_follow());
    }
  }

  String get _state => encodeReaderState(_workspace, _searches, _filterState);
  Json get _snapshot => {
    'readerState': _state,
    'layoutSizes': _workspace['layoutSizes'] ?? {},
  };
  void _bindController() {
    widget.controller?.attach(this, showTabs: _showTabs, flush: _flush);
  }

  Future<bool> _flush() async {
    if (_discardPending) return true;
    if (_switching != null && !await _switching!) return false;
    if (_failedActivation != null) return false;
    return _flushPositions();
  }

  Future<bool> _flushPositions() {
    for (final pane in _panes.values) {
      pane.currentState?.capturePosition();
    }
    _timer?.cancel();
    if (_saving != null) return _saving!;
    final task = _save();
    _saving = task;
    task.whenComplete(() => _saving = null);
    return task;
  }

  Future<bool> _save() async {
    if (!_dirty || _data['readerWorkspaceDetached'] == true) return true;
    try {
      while (_dirty && mounted) {
        final revision = _revision;
        Json result;
        if (_data['workspaceId'] != null && _data['user'] != null) {
          final snapshot = _snapshot;
          final positions = _pendingPositions.isNotEmpty;
          Future<Json> persist({required bool resume}) async {
            final response = asMap(
              await _scope!.api.send(
                'PUT',
                '/api/reader/workspaces/${_data['workspaceId']}/view',
                data: {
                  'snapshot': snapshot,
                  if (resume) 'resume': true,
                  'workspaceVersion': _data['workspaceVersion'],
                  'workspaceContentVersion': _data['workspaceContentVersion'],
                },
              ),
            );
            if (response['saved'] != true) {
              throw ApiException(
                asString(
                  response['message'],
                  'Die Ansicht wurde nicht gespeichert. Bitte den aktuellen Stand neu laden.',
                ),
              );
            }
            adoptReaderSelection(_data, response);
            return response;
          }

          // The view API intentionally treats changed references as detached
          // unless resumed. Resume keeps the server's searches/notes filters;
          // publish changed filters separately against its returned version.
          result = await persist(resume: positions);
          if (positions && _viewFiltersDirty) {
            result = await persist(resume: false);
          }
        } else {
          // Guests use the same validated mutation as explicit chapter navigation.
          result = {};
          final pending = Map<String, Json>.from(_pendingPositions);
          for (final entry in pending.entries) {
            final response = await _scope!.api.action(
              readerActionPath(_savedPath, _data, readerState: _savedState),
              'setTabReference',
              entry.value,
            );
            if (!response.isSuccess) throw ApiException(response.message);
            result = response.data;
            _savedState = asString(result['readerState'], _savedState);
            _savedPath = asString(result['path'], _savedPath);
          }
          if (pending.isEmpty && _searches.isNotEmpty) {
            // Search URL state remains shareable for guests; named persistence requires an account.
            result = {};
          }
        }
        adoptReaderSelection(_data, result);
        if (revision == _revision) {
          _dirty = false;
          _viewFiltersDirty = false;
          _pendingPositions.clear();
          _savedState = _state;
          _savedPath = Uri.parse(readerPath(_workspace, _state)).path;
        }
      }
      if (mounted) setState(() => _saveError = null);
      return true;
    } catch (error) {
      if (mounted) setState(() => _saveError = '$error');
      return false;
    }
  }

  Future<void> _follow() async {
    if (!mounted ||
        !widget.active ||
        _busy ||
        _data['workspaceId'] == null ||
        _data['readerWorkspaceDetached'] == true) {
      return;
    }
    if (!await _flush() || !mounted) return;
    setState(() => _busy = true);
    try {
      final result = asMap(
        await _scope!.api.send(
          'POST',
          '/api/reader/workspaces/${_data['workspaceId']}/follow',
          data: {
            'workspaceVersion': _data['workspaceVersion'],
            'workspaceContentVersion': _data['workspaceContentVersion'],
          },
        ),
      );
      if (!mounted) return;
      adoptReaderSelection(_data, result);
      if (result['readerState'] != null && result['readerState'] != _state) {
        await _reloadView('${result['path']}?${result['readerState']}');
      }
    } catch (error) {
      if (mounted) setState(() => _saveError = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _position(Json tile, Json tab, Json reference) {
    final currentTile = asMaps(_workspace['tiles'])
        .firstWhere((item) => item['id'] == tile['id'], orElse: () => {});
    if (currentTile.isEmpty) return;
    if (_activationInFlight || activeTab(currentTile)['id'] != tab['id']) {
      _deferredPositions[asString(tab['id'])] = reference;
      return;
    }
    if (_busy) return;
    if (jsonEncode(activeTab(currentTile)['reference']) ==
        jsonEncode(reference)) {
      return;
    }
    updateReadingPosition(
      _workspace,
      asString(tile['id']),
      asString(tab['id']),
      reference,
    );
    _pendingPositions[asString(tab['id'])] = {
      'tileId': tile['id'],
      'tabId': tab['id'],
      'reference': referenceLabel(reference),
    };
    _dirty = true;
    _revision++;
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 700), _flush);
    if (tab['linkSet'] != null) {
      for (final otherTile in asMaps(_workspace['tiles'])) {
        final other = activeTab(otherTile);
        if (other['id'] != tab['id'] && other['linkSet'] == tab['linkSet']) {
          _panes[asString(other['id'])]?.currentState?.align(reference);
        }
      }
    }
  }

  Future<void> _mutate(String action, Json fields) async {
    if (_busy || !await _flush() || !mounted) return;
    setState(() => _busy = true);
    try {
      final path = readerPath(_workspace, _state);
      final response = await _scope!.api.action(
        readerActionPath(path, _data, readerState: _state),
        action,
        fields,
      );
      if (!mounted) return;
      if (response.isRedirect) {
        await _scope!.open(response.location!);
      } else if (!response.isSuccess) {
        throw ApiException(response.message);
      } else if (response.data['readerState'] != null) {
        await _reloadView(
          '${response.data['path'] ?? Uri.parse(path).path}?${response.data['readerState']}',
          mobileTile: response.data['tileId'] as String?,
        );
      } else {
        await _reloadView(readerPath(_workspace, _state));
      }
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Json _shownTab(Json tile) => asMaps(tile['tabs']).firstWhere(
    (tab) =>
        tab['id'] ==
        (_displayedTabs[asString(tile['id'])] ?? tile['activeTabId']),
    orElse: () => activeTab(tile),
  );

  Json _studyTab(Json tab) {
    final key = asString(tab['id']);
    final study = <String, dynamic>{
      'resourceId': tab['resourceId'],
      'lookup': tab['lookup'],
      'studyContext': tab['studyContext'],
    };
    if (jsonEncode(_lexiconTabs[key]) != jsonEncode(study)) {
      _lexiconTabs[key] = study;
    }
    return _lexiconTabs[key]!;
  }

  void _activateTab(String tileId, String tabId) {
    if (_busy) return;
    final tile = asMaps(_workspace['tiles'])
        .firstWhere((item) => item['id'] == tileId);
    if (_shownTab(tile)['id'] == tabId && _mobileTile == tileId) return;
    // Capture the departing viewport before replacing it. Saving remains serial.
    for (final pane in _panes.values) {
      pane.currentState?.capturePosition();
    }
    setState(() {
      _displayedTabs[tileId] = tabId;
      _mobileTile = tileId;
      _failedActivation = null;
      _saveError = null;
    });
    // A burst of swipes only needs the most recent unsent choice in each tile.
    _activations.removeWhere((item) => item['tileId'] == tileId);
    _activations.add({'tileId': tileId, 'tabId': tabId});
    if (_switching == null) {
      final task = _commitActivations();
      _switching = task;
      task.whenComplete(() {
        _switching = null;
        if (mounted) setState(() {});
      });
    }
  }

  Future<bool> _commitActivations() async {
    while (_activations.isNotEmpty && mounted) {
      final selection = _activations.removeAt(0);
      try {
        if (!await _flushPositions()) {
          throw const ApiException(
            'Die bisherige Leseposition konnte nicht gespeichert werden.',
          );
        }
        if (!mounted) return false;
        final tileId = asString(selection['tileId']),
            tabId = asString(selection['tabId']);
        final tile = asMaps(_workspace['tiles'])
            .firstWhere((item) => item['id'] == tileId);
        final predicted = asMap(jsonDecode(jsonEncode(_workspace)));
        activateReaderTab(predicted, tileId, tabId);
        final expectedState = encodeReaderState(
          predicted,
          _searches,
          _filterState,
        );
        _activationInFlight = true;
        final response = await _scope!.api.action(
          readerActionPath(
            readerPath(_workspace, _state),
            _data,
            readerState: _state,
          ),
          'activateTab',
          {
            ...selection,
            'currentReference': referenceLabel(
              asMap(activeTab(tile)['reference']),
            ),
          },
        );
        _activationInFlight = false;
        if (!mounted) return false;
        if (!response.isSuccess) throw ApiException(response.message);
        final returnedState = asString(response.data['readerState']);
        final targetTab = activeTab(
          asMaps(predicted['tiles']).firstWhere((item) => item['id'] == tileId),
        );
        final targetResource = asMaps(_data['readerResources']).firstWhere(
          (item) => item['id'] == targetTab['resourceId'],
          orElse: () => {},
        );
        final needsArticle =
            targetResource['kind'] == 'lexicon' &&
            asString(targetTab['lookup']).isNotEmpty &&
            !RegExp(r'^[GH]\d+$').hasMatch(asString(targetTab['lookup'])) &&
            !_columnsByTab.containsKey('$tabId:${targetTab['resourceId']}');
        if (returnedState == expectedState && !needsArticle) {
          setState(() {
            _workspace = predicted;
            _data['workspace'] = predicted;
            adoptReaderSelection(_data, response.data);
            _savedState = returnedState;
            _savedPath = asString(
              response.data['path'],
              Uri.parse(readerPath(predicted, returnedState)).path,
            );
            _data['readerState'] = returnedState;
          });
        } else {
          // Resource removal or server normalization must win over the preview.
          await _reloadView(
            '${response.data['path']}?$returnedState',
            mobileTile: _mobileTile,
          );
        }
        if (_displayedTabs[tileId] == tabId) _displayedTabs.remove(tileId);
        final reference = _deferredPositions.remove(tabId);
        if (reference != null) {
          updateReadingPosition(_workspace, tileId, tabId, reference);
          _pendingPositions[tabId] = {
            ...selection,
            'reference': referenceLabel(reference),
          };
          _dirty = true;
          _revision++;
        }
      } catch (error) {
        _activationInFlight = false;
        if (mounted) {
          setState(() {
            _failedActivation = _activations.isNotEmpty
                ? _activations.last
                : selection;
            _activations.clear();
            _displayedTabs.clear();
            _mobileTile = asString(_workspace['focusedTileId']);
            _saveError = 'Tabwechsel nicht gespeichert: $error';
            _showSelectedPage();
          });
        }
        return false;
      }
    }
    final focus = _workspace['focusedTileId'];
    for (final tile in asMaps(_workspace['tiles'])) {
      final tab = activeTab(tile), tabId = asString(activeTab(tile)['id']);
      final reference = _deferredPositions.remove(tabId);
      if (reference == null) continue;
      updateReadingPosition(_workspace, asString(tile['id']), tabId, reference);
      _pendingPositions[tabId] = {
        'tileId': tile['id'],
        'tabId': tab['id'],
        'reference': referenceLabel(reference),
      };
      _dirty = true;
      _revision++;
    }
    _workspace['focusedTileId'] = focus;
    return _flushPositions();
  }

  Future<void> _retrySave() async {
    final failed = _failedActivation;
    if (failed == null) {
      await _flush();
      return;
    }
    _activateTab(asString(failed['tileId']), asString(failed['tabId']));
  }

  Future<void> _reloadView(String path, {String? mobileTile}) async {
    var destination = path;
    for (var redirects = 0; redirects < 6; redirects++) {
      try {
        final data = await _scope!.api.page(destination);
        if (mounted) {
          setState(() {
            _adopt(data);
            if (mobileTile != null) _mobileTile = mobileTile;
            _showSelectedPage();
          });
        }
        return;
      } on AppRedirect catch (redirect) {
        destination = redirect.location;
      }
    }
    throw const ApiException(
      'Die Reader-Adresse konnte nicht aufgelöst werden.',
    );
  }

  Future<String?> _ask(
    String title, {
    String initial = '',
    String? hint,
    int lines = 1,
  }) => showDialog<String>(
    context: context,
    builder: (context) => ReaderTextDialog(
      title: title,
      initial: initial,
      hint: hint,
      lines: lines,
    ),
  );

  Rect get _shareOrigin {
    final box = context.findRenderObject()! as RenderBox;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  Future<void> _notes() async {
    if (!await _flush() || !mounted) return;
    final tiles = asMaps(_workspace['tiles']);
    final tile = tiles.firstWhere(
      (tile) => tile['id'] == _mobileTile,
      orElse: () => tiles.first,
    );
    final tab = activeTab(tile);
    final reference = referenceLabel(asMap(tab['reference']));
    final selected = asMaps(
      _data['readerResources'],
    ).firstWhere((item) => item['id'] == tab['resourceId'], orElse: () => {});
    final resource = selected['kind'] == 'bible'
        ? asString(tab['resourceId'])
        : asString(
            _data['defaultBibleId'],
            asString(asMaps(_data['bibles']).firstOrNull?['id']),
          );
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => readerOverlayScope(
        context,
        SizedBox(
          height: MediaQuery.sizeOf(sheetContext).height * .85,
          child: ReaderNotes(
            reference: reference,
            resourceId: resource,
            initialState: _state,
            onFilters: (query, tag, current) {
              final parts = _filterState
                  .split('&')
                  .where(
                    (part) =>
                        !RegExp(r'^(notesQuery|notesTag|notesFilter)=')
                            .hasMatch(part),
                  )
                  .toList();
              if (query.isNotEmpty) {
                parts.add('notesQuery=${Uri.encodeComponent(query)}');
              }
              if (tag.isNotEmpty) {
                parts.add('notesTag=${Uri.encodeComponent(tag)}');
              }
              if (current) parts.add('notesFilter=current');
              _filterState = parts.join('&');
              _viewFiltersDirty = true;
              _dirty = true;
              _revision++;
              _flush();
            },
            onOpen: (id) {
              Navigator.pop(sheetContext);
              _scope!.open('/notes/$id');
            },
            onCreate: () {
              Navigator.pop(sheetContext);
              _scope!.open(
                '/notes?reference=${Uri.encodeComponent(reference)}&bible=${Uri.encodeComponent(resource)}',
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _goTo(Json tile, Json tab) async {
    final value = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _PassagePicker(initial: asMap(tab['reference'])),
    );
    if (value != null) {
      await _mutate('setTabReference', {
        'tileId': tile['id'],
        'tabId': tab['id'],
        'reference': value,
      });
    }
  }

  Future<void> _chooseResource(Json tile, {Json? replace}) async {
    final resources = asMaps(_data['readerResources']);
    final resource = await showModalBottomSheet<Json>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (context) => SizedBox(
        height: MediaQuery.sizeOf(context).height * .75,
        child: ListView(
          children: [
            const ListTile(title: Text('Werk auswählen')),
            for (final item in resources)
              ListTile(
                title: Text(
                  asString(item['selectionTitle'], asString(item['name'])),
                ),
                subtitle: Text(
                  asString(
                    item['selectionSubtitle'],
                    asString(item['language']),
                  ),
                ),
                onTap: () => Navigator.pop(context, item),
              ),
          ],
        ),
      ),
    );
    if (resource != null) {
      await _mutate(replace == null ? 'addTab' : 'replaceTabResource', {
        'tileId': tile['id'],
        if (replace != null) 'tabId': replace['id'],
        'resource': resource['id'],
      });
    }
  }

  Future<void> _word(
    Json tile,
    Json tab,
    Json reference,
    Json word,
    int position,
  ) async {
    final ids = strongNumbers(word);
    if (ids.isEmpty) return;
    final selected = ids.length == 1
        ? ids.first
        : await showModalBottomSheet<String>(
            context: context,
            showDragHandle: true,
            builder: (context) => SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    title: Text(asString(word['text'])),
                    subtitle: Text(asString(word['morph'])),
                  ),
                  for (final id in ids)
                    ListTile(
                      title: Text(id),
                      onTap: () => Navigator.pop(context, id),
                    ),
                ],
              ),
            ),
          );
    if (selected == null || !mounted) return;
    final result = await showReaderLexiconSheet(
      context,
      strong: selected,
      lexiconId: preferredReaderLexicon(
        workspace: _workspace,
        resources: asMaps(_data['readerResources']),
        sourceTileId: asString(tile['id']),
        sourceTab: tab,
        strong: selected,
      ),
      sourceResourceId: asString(tab['resourceId']),
      reference: reference,
      word: asString(word['text']),
      wordPosition: position,
    );
    if (result == null || !mounted) return;
    if (result['reference'] is Map) {
      await _mutate('openBibleReference', {
        'reference': referenceLabel(asMap(result['reference'])),
        if (tab['linkSet'] != null) 'linkSet': tab['linkSet'],
      });
    } else if (result['path'] is String) {
      await _scope!.open(asString(result['path']));
    }
  }

  Future<void> _verseMenu(
    Json tab,
    Json chapter,
    Json cell,
    Json reference,
  ) async {
    final ref = referenceLabel(reference);
    final plain = versePlainText(cell['segments'] as List? ?? []);
    final existingHighlights = asMaps(chapter['highlights'])
        .where(
          (highlight) =>
              asInt(reference['verse']) >= asInt(highlight['verse']) &&
              asInt(reference['verse']) <=
                  asInt(highlight['endVerse'], asInt(highlight['verse'])) &&
              (highlight['resourceId'] == null ||
                  highlight['resourceId'] == tab['resourceId']),
        )
        .toList();
    final result = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(ref),
              subtitle: Text(
                plain,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('Vers kopieren'),
              onTap: () => Navigator.pop(context, 'copy'),
            ),
            ListTile(
              leading: const Icon(Icons.share),
              title: const Text('Vers teilen'),
              onTap: () => Navigator.pop(context, 'share'),
            ),
            ListTile(
              leading: const Icon(Icons.note_add_outlined),
              title: const Text('Notiz zu dieser Stelle'),
              onTap: () => Navigator.pop(context, 'note'),
            ),
            if (_data['user'] == null)
              ListTile(
                leading: const Icon(Icons.login),
                title: const Text('Zum Markieren und Sammeln anmelden'),
                onTap: () => Navigator.pop(context, 'login'),
              ),
            if (_data['user'] != null) ...[
              const Divider(),
              ListTile(
                leading: const Icon(Icons.format_color_text),
                title: const Text('Wörter oder Versabschnitt markieren'),
                onTap: () => Navigator.pop(context, 'partial'),
              ),
              for (var index = 0; index < existingHighlights.length; index++)
                ListTile(
                  leading: const Icon(Icons.format_color_reset),
                  title: Text(
                    'Markierung „${existingHighlights[index]['name'] ?? 'Markierung'}“ entfernen',
                  ),
                  onTap: () => Navigator.pop(context, 'removeRange:$index'),
                ),
              for (final style in asMaps(_data['highlightStyles']))
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: verseColor(asString(style['color'])),
                    radius: 12,
                  ),
                  title: Text(asString(style['name'], 'Markieren')),
                  onTap: () =>
                      Navigator.pop(context, 'highlight:${style['id']}'),
                ),
              ListTile(
                leading: const Icon(Icons.format_color_reset),
                title: const Text('Markierung entfernen'),
                onTap: () => Navigator.pop(context, 'removeHighlight'),
              ),
              ListTile(
                leading: const Icon(Icons.add),
                title: const Text('Neue Sammlung mit diesem Vers'),
                onTap: () => Navigator.pop(context, 'newList'),
              ),
              for (final list in asMaps(_data['lists']))
                ListTile(
                  leading: Icon(
                    asMaps(chapter['markedVerses']).any(
                          (entry) =>
                              entry['listId'] == list['id'] &&
                              entry['verse'] == reference['verse'],
                        )
                        ? Icons.playlist_add_check
                        : Icons.playlist_add,
                  ),
                  title: Text(asString(list['title'])),
                  subtitle: Text(
                    asMaps(chapter['markedVerses']).any(
                          (entry) =>
                              entry['listId'] == list['id'] &&
                              entry['verse'] == reference['verse'],
                        )
                        ? 'Vers enthalten · Tippen zum Entfernen'
                        : 'Vers hinzufügen',
                  ),
                  onTap: () => Navigator.pop(context, 'list:${list['id']}'),
                ),
            ],
          ],
        ),
      ),
    );
    if (result == null || !mounted) return;
    if (result == 'copy') {
      await Clipboard.setData(ClipboardData(text: '$plain ($ref)'));
    } else if (result == 'share') {
      await SharePlus.instance.share(
        ShareParams(
          text: '$plain ($ref)\n${_scope!.api.origin.resolve('/$ref')}',
          sharePositionOrigin: _shareOrigin,
        ),
      );
    } else if (result == 'login') {
      await _scope!.open('/login');
    } else if (result == 'note') {
      await _scope!.open(
        '/notes?reference=${Uri.encodeComponent(ref)}&bible=${Uri.encodeComponent(asString(tab['resourceId']))}',
      );
    } else if (result.startsWith('highlight:')) {
      await _mutate('setHighlight', {
        'reference': ref,
        'styleId': result.substring(10),
      });
    } else if (result == 'partial') {
      final range = await showDialog<Json>(
        context: context,
        builder: (context) => HighlightDialog(
          chapter: chapter,
          cell: cell,
          styles: asMaps(_data['highlightStyles']),
        ),
      );
      if (range != null) {
        await _mutate('setHighlight', {
          'reference': ref,
          'resourceId': tab['resourceId'],
          ...range,
        });
      }
    } else if (result.startsWith('removeRange:')) {
      final highlight = existingHighlights[int.parse(result.substring(12))];
      await _mutate('removeHighlight', {
        'reference': referenceLabel({
          ...asMap(chapter['reference']),
          'verse': highlight['verse'],
        }),
        if (asInt(highlight['endVerse']) > asInt(highlight['verse']))
          'endVerse': highlight['endVerse'],
        if (highlight['resourceId'] != null) ...{
          'resourceId': highlight['resourceId'],
          'startWord': highlight['startWord'],
          'endWord': highlight['endWord'],
        },
      });
    } else if (result == 'removeHighlight') {
      await _mutate('removeHighlight', {'reference': ref});
    } else if (result == 'newList') {
      final title = await _ask('Neue Sammlung', hint: 'Name der Sammlung');
      if (title != null && title.trim().isNotEmpty) {
        await _mutate('addToList', {
          'reference': ref,
          'title': title,
          'listId': '',
        });
      }
    } else if (result.startsWith('list:')) {
      final id = result.substring(5);
      final marked = asMaps(chapter['markedVerses']).any(
        (item) => item['listId'] == id && item['verse'] == reference['verse'],
      );
      await _mutate(marked ? 'removeFromList' : 'addToList', {
        'reference': ref,
        'listId': id,
      });
    }
  }

  Future<void> _search(Json tile, Json tab, Json resource) async {
    final lookup = resource['kind'] == 'lexicon';
    final query = await _ask(
      lookup ? 'Lexikoneintrag öffnen' : 'In diesem Werk suchen',
      initial: asString(lookup ? tab['lookup'] : _searches[tab['id']]),
    );
    if (query == null) return;
    if (lookup) {
      await _mutate('setTabLookup', {
        'tileId': tile['id'],
        'tabId': tab['id'],
        'lookup': query,
        'clearLookup': query.isEmpty ? 'true' : 'false',
      });
    } else {
      setState(() {
        if (query.trim().isEmpty) {
          _searches.remove(tab['id']);
        } else {
          _searches[asString(tab['id'])] = query.trim();
        }
        _viewFiltersDirty = true;
        _dirty = true;
        _revision++;
      });
      await _flush();
    }
  }

  Future<void> _tabMenu(Json tile, Json tab, String action) async {
    if (action == 'replace') {
      await _chooseResource(tile, replace: tab);
    } else if (action == 'close') {
      await _mutate('closeTab', {
        'tileId': tile['id'],
        'tabId': tab['id'],
        'currentTabId': tab['id'],
        'currentReference': referenceLabel(asMap(tab['reference'])),
      });
    } else if (action.startsWith('link:')) {
      await _mutate('setTabLinkSet', {
        'tileId': tile['id'],
        'tabId': tab['id'],
        'linkSet': action.substring(5),
      });
    } else if (action == 'details') {
      final resource = asMaps(
        _data['readerResources'],
      ).firstWhere((item) => item['id'] == tab['resourceId'], orElse: () => {});
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (context) => SizedBox(
          height: MediaQuery.sizeOf(context).height * .8,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                asString(resource['name']),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              Text(
                '${resource['language']} · ${resource['sourceRevision'] ?? ''}',
              ),
              if (asString(resource['usageNotesHtml']).isNotEmpty)
                HtmlContent(html: asString(resource['usageNotesHtml'])),
              if (asString(resource['licenseHtml']).isNotEmpty)
                HtmlContent(html: asString(resource['licenseHtml'])),
            ],
          ),
        ),
      );
    } else if (action == 'earlier' || action == 'later') {
      final index = asMaps(tile['tabs'])
          .indexWhere((candidate) => candidate['id'] == tab['id']);
      await _mutate('moveTab', {
        'fromTileId': tile['id'],
        'tabId': tab['id'],
        'toTileId': tile['id'],
        'toIndex': index + (action == 'earlier' ? -1 : 2),
      });
    } else if (action.startsWith('move:')) {
      await _mutate('moveTab', {
        'fromTileId': tile['id'],
        'tabId': tab['id'],
        'toTileId': action.substring(5),
        'toIndex': 0,
      });
    }
  }

  String _resourceTitle(Json tab) {
    final resource = asMaps(
      _data['readerResources'],
    ).firstWhere((item) => item['id'] == tab['resourceId'], orElse: () => {});
    return asString(
      resource['tabTitle'],
      asString(resource['name'], asString(tab['resourceId'])),
    );
  }

  String _previewText(Json tab) {
    final key = '${tab['id']}:${tab['resourceId']}';
    final reference = asMap(tab['reference']);
    final chapter = _chapterCaches[key]?.chapters.firstWhere(
      (item) =>
          asMap(item['reference'])['book'] == reference['book'] &&
          asMap(item['reference'])['chapter'] == reference['chapter'],
      orElse: () => {},
    );
    final initial = chapter != null && chapter.isNotEmpty
        ? chapter
        : asMap(_columnsByTab[key]?['initialChapter']);
    final rows = asMaps(asMap(initial['chapter'])['rows']);
    final text = rows
        .where((row) => asInt(row['verse']) >= asInt(reference['verse'], 1))
        .take(3)
        .map((row) {
          final cell = (row['cells'] as List? ?? []).firstOrNull;
          return versePlainText(asMap(cell)['segments'] as List? ?? []);
        })
        .join(' ');
    if (text.isNotEmpty) return text;
    final commentary = asMaps(
      asMap(initial['referenceResources'])['commentaries'],
    ).firstOrNull;
    final entry = asMap(_columnsByTab[key]?['lexiconEntry']);
    return asString(commentary?['bodyHtml'], asString(entry['bodyHtml']))
        .replaceAll(RegExp(r'<[^>]*>'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  Future<void> _togglePhoneSplit(bool value) async {
    setState(() {
      _phoneSplit = value;
      final tiles = asMaps(_workspace['tiles']);
      final focused = tiles.indexWhere((tile) => tile['id'] == _mobileTile);
      final first = focused < 0 ? 0 : focused;
      _phoneSplitTiles = [
        if (tiles.isNotEmpty) asString(tiles[first]['id']),
        if (tiles.length > 1) asString(tiles[(first + 1) % tiles.length]['id']),
      ];
    });
    if (value && asMaps(_workspace['tiles']).length < 2) {
      await _mutate('setLayout', {'layout': 'rows-2'});
      if (mounted && asMaps(_workspace['tiles']).length < 2) {
        setState(() => _phoneSplit = false);
      }
    }
  }

  Future<void> _showTabs() async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheet) => readerOverlayScope(
        context,
        SizedBox(
          height: MediaQuery.sizeOf(sheet).height * .86,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Geöffnete Werke',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    PopupMenuButton<String>(
                      tooltip: 'Anordnung',
                      icon: const Icon(Icons.view_quilt_outlined),
                      onSelected: (layout) {
                        Navigator.pop(sheet);
                        _mutate('setLayout', {'layout': layout});
                      },
                      itemBuilder: (_) => readerLayouts.entries
                          .map(
                            (entry) => PopupMenuItem(
                              value: entry.key,
                              child: Text(entry.value),
                            ),
                          )
                          .toList(),
                    ),
                    IconButton(
                      tooltip: 'Fertig',
                      onPressed: () => Navigator.pop(sheet),
                      icon: const Icon(Icons.check),
                    ),
                  ],
                ),
              ),
              if (MediaQuery.sizeOf(context).width < 768)
                SwitchListTile.adaptive(
                  title: const Text('Geteilter Bildschirm'),
                  subtitle: const Text('Zwei Werke gleichzeitig lesen'),
                  value: _phoneSplit,
                  onChanged: (value) {
                    Navigator.pop(sheet);
                    _togglePhoneSplit(value);
                  },
                ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final tiles = asMaps(_workspace['tiles']);
                    final choices = <Json>[
                      for (final tile in tiles)
                        if (asMaps(tile['tabs']).isEmpty)
                          {'tile': tile, 'tab': <String, dynamic>{}}
                        else
                          ..._flatTabs([tile]),
                    ];
                    final scaler = MediaQuery.textScalerOf(context);
                    final columns =
                        constraints.maxWidth < 360 || scaler.scale(14) > 20
                        ? 1
                        : constraints.maxWidth < 640
                        ? 2
                        : (constraints.maxWidth / 230).floor().clamp(3, 5);
                    return GridView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        mainAxisExtent: ReaderTabCard.heightFor(scaler),
                      ),
                      itemCount: choices.length,
                      itemBuilder: (_, index) {
                        final tile = asMap(choices[index]['tile']),
                            tab = asMap(choices[index]['tab']);
                        if (tab.isEmpty) {
                          return OutlinedButton.icon(
                            onPressed: () {
                              Navigator.pop(sheet);
                              _chooseResource(tile);
                            },
                            icon: const Icon(Icons.add),
                            label: Text(
                              'Werk in Bereich ${tiles.indexOf(tile) + 1} hinzufügen',
                            ),
                          );
                        }
                        final resource = asMaps(_data['readerResources'])
                            .firstWhere(
                              (item) => item['id'] == tab['resourceId'],
                              orElse: () => {},
                            );
                        return ReaderTabCard(
                          title: _resourceTitle(tab),
                          reference: referenceLabel(asMap(tab['reference'])),
                          previewText: _previewText(tab),
                          resourceKind: asString(resource['kind']),
                          linkSet: tab['linkSet'] as String?,
                          eInk: _scope!.eInk,
                          selected:
                              _shownTab(tile)['id'] == tab['id'] &&
                              (MediaQuery.sizeOf(this.context).width >= 768 ||
                                  _phoneSplit ||
                                  _mobileTile == tile['id']),
                          onTap: () {
                            Navigator.pop(sheet);
                            _activateTab(
                              asString(tile['id']),
                              asString(tab['id']),
                            );
                            _showSelectedPage();
                          },
                          trailing: PopupMenuButton<String>(
                            tooltip: 'Werk verwalten',
                            onSelected: (value) {
                              Navigator.pop(sheet);
                              _tabMenu(tile, tab, value);
                            },
                            itemBuilder: (_) => [
                              const PopupMenuItem(
                                value: 'close',
                                child: Text('Schließen'),
                              ),
                              const PopupMenuItem(
                                value: 'replace',
                                child: Text('Werk wechseln'),
                              ),
                              const PopupMenuItem(
                                value: 'details',
                                child: Text('Informationen zum Werk'),
                              ),
                              const PopupMenuDivider(),
                              for (final group in ['', 'A', 'B', 'C', 'D', 'E'])
                                PopupMenuItem(
                                  value: 'link:$group',
                                  child: _groupChoice(tab, group),
                                ),
                              for (final other in tiles)
                                if (other['id'] != tile['id'])
                                  PopupMenuItem(
                                    value: 'move:${other['id']}',
                                    child: Text(
                                      'In Bereich ${tiles.indexOf(other) + 1} verschieben',
                                    ),
                                  ),
                              PopupMenuItem(
                                value: 'earlier',
                                enabled:
                                    asMaps(tile['tabs']).first['id'] !=
                                    tab['id'],
                                child: const Text('Nach vorne'),
                              ),
                              PopupMenuItem(
                                value: 'later',
                                enabled:
                                    asMaps(tile['tabs']).last['id'] !=
                                    tab['id'],
                                child: const Text('Nach hinten'),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                  child: Wrap(
                    spacing: 4,
                    children: [
                      PopupMenuButton<String>(
                        tooltip: 'Werk hinzufügen',
                        icon: const Icon(Icons.add),
                        onSelected: (id) {
                          Navigator.pop(sheet);
                          _chooseResource(
                            asMaps(_workspace['tiles'])
                                .firstWhere((tile) => tile['id'] == id),
                          );
                        },
                        itemBuilder: (_) => asMaps(_workspace['tiles'])
                            .asMap()
                            .entries
                            .map(
                              (entry) => PopupMenuItem(
                                value: asString(entry.value['id']),
                                child: Text(
                                  'Werk in Bereich ${entry.key + 1} hinzufügen',
                                ),
                              ),
                            )
                            .toList(),
                      ),

                      IconButton(
                        tooltip: 'Schrift verkleinern',
                        onPressed: () {
                          Navigator.pop(sheet);
                          _mutate('adjustFontSize', {'delta': -5});
                        },
                        icon: const Icon(Icons.text_decrease),
                      ),
                      IconButton(
                        tooltip: 'Schrift vergrößern',
                        onPressed: () {
                          Navigator.pop(sheet);
                          _mutate('adjustFontSize', {'delta': 5});
                        },
                        icon: const Icon(Icons.text_increase),
                      ),
                      if (_data['user'] != null)
                        IconButton(
                          tooltip: 'Arbeitsbereiche',
                          onPressed: () async {
                            Navigator.pop(sheet);
                            if (await _flush() && mounted) {
                              await showWorkspaces(
                                context,
                                snapshot: _snapshot,
                              );
                            }
                          },
                          icon: const Icon(Icons.workspaces_outline),
                        ),
                      if (_data['user'] != null)
                        IconButton(
                          tooltip: 'Eigene Notizen und Dokumente',
                          onPressed: () {
                            Navigator.pop(sheet);
                            _notes();
                          },
                          icon: const Icon(Icons.note_alt_outlined),
                        ),
                      IconButton(
                        tooltip: 'Ansicht teilen',
                        onPressed: () => SharePlus.instance.share(
                          ShareParams(
                            text: _scope!.api.origin
                                .resolve(readerPath(_workspace, _state))
                                .toString(),
                            sharePositionOrigin: _shareOrigin,
                          ),
                        ),
                        icon: const Icon(Icons.ios_share),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Json> _flatTabs(List<Json> tiles) => [
    for (final tile in tiles)
      for (final tab in asMaps(tile['tabs'])) {'tile': tile, 'tab': tab},
  ];

  void _showSelectedPage() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      for (final entry in _pageControllers.entries) {
        if (!entry.value.hasClients) continue;
        final tiles = asMaps(_workspace['tiles']);
        final choices = _flatTabs(
          entry.key == 'mobile'
              ? tiles
              : tiles.where((tile) => tile['id'] == entry.key).toList(),
        );
        final selected = choices.indexWhere(
          (item) =>
              _shownTab(asMap(item['tile']))['id'] ==
                  asMap(item['tab'])['id'] &&
              (entry.key != 'mobile' ||
                  asMap(item['tile'])['id'] == _mobileTile),
        );
        if (selected >= 0 && (entry.value.page ?? -1).round() != selected) {
          entry.value.jumpToPage(selected);
        }
      }
    });
  }

  Widget _resourcePages(List<Json> tiles, {required bool mobile}) {
    final choices = _flatTabs(tiles);
    if (choices.isEmpty) return _tile(tiles.first, mobile: mobile);
    final deckKey = mobile ? 'mobile' : asString(tiles.single['id']);
    final selected = choices.indexWhere(
      (item) =>
          _shownTab(asMap(item['tile']))['id'] == asMap(item['tab'])['id'] &&
          (!mobile || asMap(item['tile'])['id'] == _mobileTile),
    );
    final controller = _pageControllers.putIfAbsent(
      deckKey,
      () => PageController(initialPage: selected < 0 ? 0 : selected),
    );
    return PageView.builder(
      key: ValueKey('reader-pages:$deckKey'),
      controller: controller,
      itemCount: choices.length,
      physics: _busy
          ? const NeverScrollableScrollPhysics()
          : const PageScrollPhysics(),
      onPageChanged: (index) {
        final item = choices[index];
        _activateTab(
          asString(asMap(item['tile'])['id']),
          asString(asMap(item['tab'])['id']),
        );
      },
      findChildIndexCallback: (key) {
        if (key is! ValueKey<String>) return null;
        final index = choices.indexWhere(
          (item) => asMap(item['tab'])['id'] == key.value,
        );
        return index < 0 ? null : index;
      },
      itemBuilder: (_, index) {
        final item = choices[index],
            tile = asMap(item['tile']),
            tab = asMap(item['tab']);
        return _KeepReaderTab(
          key: ValueKey(asString(tab['id'])),
          child: _tile(tile, mobile: mobile, selectedTab: tab),
        );
      },
    );
  }

  Widget _groupChoice(Json tab, String group) {
    final link = group.isEmpty ? null : group;
    final selected = tab['linkSet'] == link;
    return Row(
      children: [
        ReaderGroupBadge(linkSet: link, selected: selected, eInk: _scope!.eInk),
        const SizedBox(width: 8),
        Expanded(
          child: Text(link == null ? 'Unabhängig lesen' : 'Tabgruppe $link'),
        ),
        if (selected) const Icon(Icons.check, size: 18),
      ],
    );
  }

  Widget _tabStrip(List<Json> tiles) => SizedBox(
    height: ReaderGroupBadge.heightFor(MediaQuery.textScalerOf(context)) + 16,
    child: ListView(
      scrollDirection: Axis.horizontal,
      children: [
        for (final item in _flatTabs(tiles))
          Builder(
            builder: (_) {
              final tile = asMap(item['tile']), tab = asMap(item['tab']);
              final selected = _shownTab(tile)['id'] == tab['id'];
              return DecoratedBox(
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: selected
                          ? Theme.of(context).colorScheme.primary
                          : Colors.transparent,
                      width: 2,
                    ),
                  ),
                ),
                child: TextButton(
                  onPressed: () {
                    _activateTab(asString(tile['id']), asString(tab['id']));
                    _showSelectedPage();
                  },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ReaderGroupBadge(
                        linkSet: tab['linkSet'] as String?,
                        eInk: _scope!.eInk,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _resourceTitle(tab),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
      ],
    ),
  );

  Widget _tile(Json tile, {bool mobile = false, Json? selectedTab}) {
    final tab = selectedTab ?? _shownTab(tile);
    if (tab.isEmpty) {
      return Center(
        child: FilledButton.tonalIcon(
          onPressed: () => _chooseResource(tile),
          icon: const Icon(Icons.add),
          label: const Text('Werk hinzufügen'),
        ),
      );
    }
    final resource = asMaps(
      _data['readerResources'],
    ).firstWhere((item) => item['id'] == tab['resourceId'], orElse: () => {});
    final column = _columnsByTab['${tab['id']}:${tab['resourceId']}'] ?? {};
    final query = asString(_searches[tab['id']]);
    final tabKey = asString(tab['id']);
    final paneKey = _panes.putIfAbsent(
      tabKey,
      () => GlobalKey<_ChapterPaneState>(),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () => _goTo(tile, tab),
                  child: Text(
                    '${_resourceTitle(tab)} · ${referenceLabel(asMap(tab['reference']))}',
                    maxLines: 1,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              IconButton(
                tooltip: resource['kind'] == 'lexicon'
                    ? 'Lexikoneintrag öffnen'
                    : 'In diesem Werk suchen',
                onPressed: () => _search(tile, tab, resource),
                icon: const Icon(Icons.search),
              ),
              PopupMenuButton<String>(
                tooltip: 'Tab-Einstellungen',
                onSelected: (action) => _tabMenu(tile, tab, action),
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'replace',
                    child: Text('Werk wechseln'),
                  ),
                  const PopupMenuItem(
                    value: 'close',
                    child: Text('Tab schließen'),
                  ),
                  const PopupMenuItem(
                    value: 'details',
                    child: Text('Informationen zum Werk'),
                  ),
                  PopupMenuItem(
                    value: 'earlier',
                    enabled: asMaps(tile['tabs']).first['id'] != tab['id'],
                    child: const Text('Tab nach vorne'),
                  ),
                  PopupMenuItem(
                    value: 'later',
                    enabled: asMaps(tile['tabs']).last['id'] != tab['id'],
                    child: const Text('Tab nach hinten'),
                  ),
                  const PopupMenuDivider(),
                  for (final link in ['', 'A', 'B', 'C', 'D', 'E'])
                    PopupMenuItem(
                      value: 'link:$link',
                      child: _groupChoice(tab, link),
                    ),
                  const PopupMenuDivider(),
                  for (final other in asMaps(_workspace['tiles']))
                    if (other['id'] != tile['id'])
                      PopupMenuItem(
                        value: 'move:${other['id']}',
                        child: Text(
                          'In Kachel ${asMaps(_workspace['tiles']).indexOf(other) + 1} verschieben',
                        ),
                      ),
                ],
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: ReaderGroupBadge(
                    linkSet: tab['linkSet'] as String?,
                    eInk: _scope!.eInk,
                  ),
                ),
              ),
            ],
          ),
          if (query.isNotEmpty)
            Material(
              color: Theme.of(context).colorScheme.secondaryContainer,
              child: ListTile(
                dense: true,
                title: Text('Suche: $query'),
                trailing: IconButton(
                  tooltip: 'Suche schließen',
                  icon: const Icon(Icons.close),
                  onPressed: () {
                    setState(() {
                      _searches.remove(tab['id']);
                      _viewFiltersDirty = true;
                      _dirty = true;
                      _revision++;
                    });
                    _flush();
                  },
                ),
              ),
            ),
          Expanded(
            child: query.isNotEmpty
                ? TabSearchPanel(
                    resourceId: asString(tab['resourceId']),
                    query: query,
                    onOpen: (reference) => _mutate('setTabReference', {
                      'tileId': tile['id'],
                      'tabId': tab['id'],
                      'reference': referenceLabel(reference),
                    }),
                  )
                : resource['kind'] == 'lexicon'
                ? LexiconStudy(
                    tab: _studyTab(tab),
                    entry: column['lexiconEntry'] is Map
                        ? asMap(column['lexiconEntry'])
                        : const {},
                    onOpen: (reference) => _mutate('openBibleReference', {
                      'reference': referenceLabel(reference),
                      if (tab['linkSet'] != null) 'linkSet': tab['linkSet'],
                    }),
                  )
                : _ChapterPane(
                    key: paneKey,
                    cache: _chapterCaches.putIfAbsent(
                      '$tabKey:${resource['id']}',
                      _ChapterCache.new,
                    ),
                    initial: asMap(column['initialChapter']),
                    active:
                        widget.active &&
                        _shownTab(tile)['id'] == tab['id'] &&
                        (!mobile || _mobileTile == tile['id']),
                    resource: resource,
                    reference: asMap(tab['reference']),
                    fontScale: asInt(_data['readerFontScale'], 100) / 100,
                    onPosition: (reference) => _position(tile, tab, reference),
                    onWord: (reference, word, position) =>
                        _word(tile, tab, reference, word, position),
                    onVerse: (chapter, cell, reference) =>
                        _verseMenu(tab, chapter, cell, reference),
                    onReference: (reference) => _mutate('openBibleReference', {
                      'reference': referenceLabel(reference),
                      if (tab['linkSet'] != null) 'linkSet': tab['linkSet'],
                    }),
                    onReferenceText: (reference) =>
                        _mutate('openBibleReference', {
                          'reference': reference,
                          if (tab['linkSet'] != null) 'linkSet': tab['linkSet'],
                        }),
                  ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tiles = asMaps(_workspace['tiles']);
    final selectedTile = tiles.firstWhere(
      (tile) => tile['id'] == _mobileTile,
      orElse: () => tiles.isEmpty ? {} : tiles.first,
    );
    widget.controller?.update(
      tabCount: _flatTabs(tiles).length,
      activeTitle: _resourceTitle(_shownTab(selectedTile)),
    );
    final colors = Theme.of(context).colorScheme;
    return Column(
      children: [
        if (widget.controller == null)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _showTabs,
              icon: const Icon(Icons.tab_outlined),
              label: Text('Tabs (${_flatTabs(tiles).length})'),
            ),
          ),
        if (_busy) const LinearProgressIndicator(minHeight: 2),
        if (_saveError != null)
          Material(
            color: colors.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  Expanded(child: Text(_saveError!)),
                  TextButton(
                    onPressed: _retrySave,
                    child: const Text('Erneut speichern'),
                  ),
                  IconButton(
                    tooltip: 'Gespeicherten Stand laden',
                    onPressed: () async {
                      if (await confirmAction(
                        context,
                        'Gespeicherten Stand laden?',
                        'Die noch nicht gespeicherte Leseposition und Suche werden verworfen.',
                      )) {
                        _dirty = false;
                        _viewFiltersDirty = false;
                        _failedActivation = null;
                        _pendingPositions.clear();
                        _deferredPositions.clear();
                        _discardPending = true;
                        try {
                          if (mounted) await _scope!.open('/');
                        } finally {
                          _discardPending = false;
                        }
                      }
                    },
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
            ),
          ),
        if (_data['readerWorkspaceDetached'] == true)
          const Padding(
            padding: EdgeInsets.all(8),
            child: Text(
              'Geteilte Ansicht · Dein gespeicherter Arbeitsbereich bleibt erhalten.',
            ),
          ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (tiles.isEmpty) {
                return const Center(child: Text('Kein Werk verfügbar.'));
              }
              if (constraints.maxWidth < 768) {
                if (_phoneSplit && tiles.length > 1) {
                  final shown = <Json>[];
                  for (final id in _phoneSplitTiles) {
                    final tile = tiles
                        .where((tile) => tile['id'] == id)
                        .firstOrNull;
                    if (tile != null) shown.add(tile);
                  }
                  for (final tile in tiles) {
                    if (shown.length < 2 && !shown.contains(tile)) {
                      shown.add(tile);
                    }
                  }
                  return ReaderSplit(
                    axis: Axis.vertical,
                    weights: _phoneRatios,
                    onResize: (sizes) => setState(() => _phoneRatios = sizes),
                    children: [
                      for (final tile in shown)
                        _resourcePages([tile], mobile: false),
                    ],
                  );
                }
                return _resourcePages(tiles, mobile: true);
              }
              final children = tiles
                  .map(
                    (tile) => Column(
                      children: [
                        _tabStrip([tile]),
                        Expanded(child: _resourcePages([tile], mobile: false)),
                      ],
                    ),
                  )
                  .toList();
              final layout = asString(_workspace['layout']);
              final columnCount = layout == 'single' || layout == 'rows-2'
                  ? 1
                  : layout == 'columns-3'
                  ? 3
                  : layout == 'columns-4'
                  ? 4
                  : 2;
              final rowCount =
                  [
                    'rows-2',
                    'left-full',
                    'right-full',
                    'grid-4',
                  ].contains(layout)
                  ? 2
                  : 1;
              void saveSizes(String axis, List<double> sizes) => _mutate(
                'setLayoutSize',
                {
                  'layout': layout,
                  'columns':
                      (axis == 'columns'
                              ? sizes
                              : readerTrackSizes(
                                  _workspace,
                                  'columns',
                                  columnCount,
                                ))
                          .join(','),
                  'rows':
                      (axis == 'rows'
                              ? sizes
                              : readerTrackSizes(_workspace, 'rows', rowCount))
                          .join(','),
                },
              );
              Widget row(List<Widget> items) => ReaderSplit(
                axis: Axis.horizontal,
                weights: readerTrackSizes(_workspace, 'columns', items.length),
                onResize: _busy ? null : (sizes) => saveSizes('columns', sizes),
                children: items,
              );
              Widget column(List<Widget> items) => ReaderSplit(
                axis: Axis.vertical,
                weights: readerTrackSizes(_workspace, 'rows', items.length),
                onResize: _busy ? null : (sizes) => saveSizes('rows', sizes),
                children: items,
              );
              return switch (_workspace['layout']) {
                'rows-2' => column(children),
                'left-full' when children.length == 3 => row([
                  children[0],
                  column(children.sublist(1)),
                ]),
                'right-full' when children.length == 3 => row([
                  column(children.sublist(0, 2)),
                  children[2],
                ]),
                'grid-4' when children.length == 4 => column([
                  row(children.sublist(0, 2)),
                  row(children.sublist(2)),
                ]),
                _ => row(children),
              };
            },
          ),
        ),
      ],
    );
  }
}

class _PassagePicker extends StatefulWidget {
  const _PassagePicker({required this.initial});
  final Json initial;
  @override
  State<_PassagePicker> createState() => _PassagePickerState();
}

class _PassagePickerState extends State<_PassagePicker> {
  late int _book = asInt(widget.initial['book'], 43);
  @override
  Widget build(BuildContext context) => SizedBox(
    height: MediaQuery.sizeOf(context).height * .8,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          SearchBox(
            label: 'Direkte Bibelstelle, z. B. Joh 3,16',
            onSearch: (value) => Navigator.pop(context, value),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<int>(
            initialValue: _book,
            decoration: const InputDecoration(labelText: 'Buch'),
            items: bibleBooks
                .map(
                  (book) =>
                      DropdownMenuItem(value: book.id, child: Text(book.name)),
                )
                .toList(),
            onChanged: (value) {
              if (value != null) setState(() => _book = value);
            },
          ),
          const SizedBox(height: 16),
          Expanded(
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 72,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
              ),
              itemCount: bibleBooks[_book - 1].chapters,
              itemBuilder: (context, index) => OutlinedButton(
                onPressed: () => Navigator.pop(
                  context,
                  referenceLabel({'book': _book, 'chapter': index + 1}),
                ),
                child: Text('${index + 1}'),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _KeepReaderTab extends StatefulWidget {
  const _KeepReaderTab({super.key, required this.child});
  final Widget child;
  @override
  State<_KeepReaderTab> createState() => _KeepReaderTabState();
}

class _KeepReaderTabState extends State<_KeepReaderTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

class _ChapterCache {
  final chapters = <Json>[];
  final requests = <String, Future<Json>>{};
  double offset = 0;
  String? anchorKey;
  Json? reference;
  double? fontScale;
}

class _ChapterPane extends StatefulWidget {
  const _ChapterPane({
    super.key,
    required this.initial,
    required this.cache,
    required this.resource,
    required this.reference,
    required this.onPosition,
    required this.onWord,
    required this.onVerse,
    required this.onReference,
    required this.onReferenceText,
    required this.active,
    this.fontScale = 1,
  });
  final Json initial, resource, reference;
  final _ChapterCache cache;
  final double fontScale;
  final bool active;
  final void Function(Json) onPosition, onReference;
  final void Function(String) onReferenceText;
  final void Function(Json, Json, int) onWord;
  final void Function(Json, Json, Json) onVerse;
  @override
  State<_ChapterPane> createState() => _ChapterPaneState();
}

class _ReaderEntry {
  const _ReaderEntry(this.id, this.builder, [this.reference]);
  final String id;
  final Widget Function() builder;
  final Json? reference;
}

class _ChapterPaneState extends State<_ChapterPane> {
  late final ScrollController _scroll;
  final _viewport = GlobalKey();
  final _center = GlobalKey();
  final _visible = <String, BuildContext>{};
  final _references = <String, Json>{};
  List<_ReaderEntry> _entries = [];
  List<Json> get _chapters => widget.cache.chapters;
  bool _loading = false,
      _aligning = false,
      _userScroll = false,
      _needsCapture = false;
  String? _error, _anchorKey;
  Timer? _timer;
  Json? _nextAlignment;
  int _generation = 0;

  String _key(Json reference) =>
      '${reference['book']}:${reference['chapter']}:${reference['verse'] ?? 0}';

  @override
  void initState() {
    super.initState();
    if (_chapters.isEmpty && widget.initial.isNotEmpty) {
      _chapters.add(widget.initial);
    }
    _refreshEntries();
    final restore =
        jsonEncode(widget.cache.reference) == jsonEncode(widget.reference) &&
        widget.cache.fontScale == widget.fontScale;
    _anchorKey = restore
        ? widget.cache.anchorKey
        : _targetKey(widget.reference);
    _scroll = ScrollController(
      initialScrollOffset: restore ? widget.cache.offset : 0,
    )..addListener(_onScroll);
    if (widget.active && (!restore || _chapters.isEmpty)) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => align(widget.reference),
      );
    }
  }

  @override
  void didUpdateWidget(_ChapterPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    final resourceChanged = oldWidget.resource['id'] != widget.resource['id'];
    if (resourceChanged) {
      _generation++;
      _aligning = false;
      _loading = false;
      _nextAlignment = null;
      _chapters.clear();
      if (widget.initial.isNotEmpty) _chapters.add(widget.initial);
      _anchorKey = null;
      _refreshEntries();
      if (widget.active) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => align(widget.reference),
        );
      }
    }

    if (widget.initial.isNotEmpty &&
        !identical(oldWidget.initial, widget.initial)) {
      final index = _chapters.indexWhere(
        (chapter) =>
            _key(asMap(chapter['reference'])) ==
            _key(asMap(widget.initial['reference'])),
      );
      if (index >= 0) _chapters[index] = widget.initial;
      _refreshEntries();
    }
    if (widget.active &&
        (!oldWidget.active ||
            jsonEncode(oldWidget.reference) != jsonEncode(widget.reference) ||
            oldWidget.fontScale != widget.fontScale)) {
      if (jsonEncode(widget.cache.reference) != jsonEncode(widget.reference) ||
          widget.cache.fontScale != widget.fontScale) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => align(widget.reference),
        );
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    if (_scroll.hasClients) widget.cache.offset = _scroll.offset;
    widget.cache.anchorKey = _anchorKey;
    _scroll.dispose();
    super.dispose();
  }

  Future<Json> _fetch(Json reference) {
    final key = _key({...reference, 'verse': null});
    final cache = widget.cache;
    return cache.requests.putIfAbsent(key, () {
      final task = AppScope.of(context).api
          .get(
            '/api/reader/${reference['book']}/${reference['chapter']}?resource=${Uri.encodeComponent(asString(widget.resource['id']))}',
          )
          .then(asMap);
      task.whenComplete(() => cache.requests.remove(key)).ignore();
      return task;
    });
  }

  String? _targetKey(Json reference) {
    String? target;
    var bestVerse = -1;
    for (final entry in _entries) {
      final candidate = entry.reference;
      if (candidate == null ||
          candidate['book'] != reference['book'] ||
          candidate['chapter'] != reference['chapter']) {
        continue;
      }
      final verse = asInt(candidate['verse']);
      if (verse <= asInt(reference['verse']) && verse >= bestVerse) {
        target = entry.id;
        bestVerse = verse;
      }
    }
    return target;
  }

  Future<void> align(Json reference) async {
    if (!mounted || !widget.active || reference.isEmpty) return;
    if (_aligning) {
      _nextAlignment = Map.of(reference);
      return;
    }
    _aligning = true;
    final generation = _generation;
    try {
      if (!_chapters.any(
        (chapter) =>
            asMap(chapter['reference'])['book'] == reference['book'] &&
            asMap(chapter['reference'])['chapter'] == reference['chapter'],
      )) {
        final chapter = await _fetch(reference);
        if (!mounted || generation != _generation) return;
        setState(() {
          _chapters
            ..clear()
            ..add(chapter);
          _refreshEntries();
        });
      }
      if (!mounted || !widget.active || generation != _generation) return;
      final target = _targetKey(reference);
      if (target != null) {
        final visibleContext = _visible[target];
        if (visibleContext != null && visibleContext.mounted) {
          await Scrollable.ensureVisible(
            visibleContext,
            duration: Duration.zero,
            alignment: 0,
          );
        } else {
          // Rebase the two lazy slivers on the target. No estimated heights and no
          // eager layout of the preceding verses are needed for an exact jump.
          setState(() {
            _anchorKey = target;
            widget.cache.anchorKey = target;
          });
          if (_scroll.hasClients) _scroll.jumpTo(0);
          await WidgetsBinding.instance.endOfFrame;
          if (mounted && _scroll.hasClients) _scroll.jumpTo(0);
        }
      }
      widget.cache.reference = Map.of(reference);
      widget.cache.fontScale = widget.fontScale;
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() {
          _error = '$error';
          _refreshEntries();
        });
      }
    } finally {
      if (generation == _generation) {
        _aligning = false;
        final pending = _nextAlignment;
        _nextAlignment = null;
        if (mounted && pending != null) unawaited(align(pending));
      }
    }
  }

  Future<void> _load(bool previous) async {
    if (_loading || _chapters.isEmpty) return;
    final edge = previous ? _chapters.first : _chapters.last;
    final generation = _generation;
    final reference = asMap(
      asMap(edge['navigation'])[previous ? 'previous' : 'next'],
    );
    if (reference.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final chapter = await _fetch(reference);
      if (!mounted ||
          generation != _generation ||
          !_chapters.any(
            (item) =>
                _key(asMap(item['reference'])) ==
                _key(asMap(edge['reference'])),
          )) {
        return;
      }
      setState(() {
        if (!_chapters.any(
          (item) =>
              _key(asMap(item['reference'])) ==
              _key(asMap(chapter['reference'])),
        )) {
          previous ? _chapters.insert(0, chapter) : _chapters.add(chapter);
        }
        _refreshEntries();
      });
      // The center sliver stays on the same verse when a chapter is prepended.
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = '$error';
          _refreshEntries();
        });
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  void _onScroll() {
    if (_scroll.hasClients) {
      widget.cache.offset = _scroll.offset;
      widget.cache.anchorKey = _anchorKey;
    }
    if (!_userScroll || _aligning || !widget.active) return;
    if (_scroll.position.extentAfter < 500) unawaited(_load(false));
    _needsCapture = true;
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 180), capturePosition);
  }

  void capturePosition() {
    if (!_needsCapture || !mounted || !widget.active || _aligning) return;
    _needsCapture = false;
    final viewport = _viewport.currentContext?.findRenderObject();
    if (viewport is! RenderBox) return;
    final top = viewport.localToGlobal(Offset.zero).dy;
    Json? closest;
    var distance = double.infinity;
    for (final entry in _visible.entries) {
      final render = entry.value.findRenderObject();
      if (render is! RenderBox ||
          !render.attached ||
          !_references.containsKey(entry.key)) {
        continue;
      }
      final y = render.localToGlobal(Offset.zero).dy - top;
      if (y >= -render.size.height && y.abs() < distance) {
        distance = y.abs();
        closest = _references[entry.key];
      }
    }
    if (closest != null) {
      widget.cache.reference = Map.of(closest);
      widget.onPosition(closest);
    }
  }

  Widget _verse(Json chapter, Json row) {
    final cells = row['cells'] as List? ?? [];
    if (cells.isEmpty || cells.first == null) return const SizedBox.shrink();
    final cell = asMap(cells.first);
    final reference = {
      ...asMap(chapter['reference']),
      'verse': cell['verse'],
      if (cell['verseEnd'] != null) 'verseEnd': cell['verseEnd'],
    };
    final verse = asInt(cell['verse']);
    final highlights = <Json>[];
    for (final item in asMaps(chapter['highlights'])) {
      if (verse < asInt(item['verse']) ||
          verse > asInt(item['endVerse'], asInt(item['verse']))) {
        continue;
      }
      if (item['resourceId'] != null &&
          item['resourceId'] != widget.resource['id']) {
        continue;
      }
      highlights.add({
        'start': verse == item['verse'] ? asInt(item['startWord']) : 0,
        'end': verse == item['endVerse']
            ? asInt(item['endWord'], 100000)
            : 100000,
        'color': item['color'],
      });
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (AppScope.of(context).eInk && highlights.isNotEmpty)
            Text(
              'Markiert: ${asMaps(chapter['highlights']).where((item) => verse >= asInt(item['verse']) && verse <= asInt(item['endVerse'], asInt(item['verse'])) && (item['resourceId'] == null || item['resourceId'] == widget.resource['id'])).map((item) => asString(item['name'], 'Markierung')).toSet().join(', ')}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          if (asString(cell['heading']).isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                asString(cell['heading']),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          GestureDetector(
            onLongPress: () => widget.onVerse(chapter, cell, reference),
            child: VerseText(
              selectable: false,
              segments: cell['segments'] as List? ?? [],
              verseNumber:
                  '${cell['verse']}${cell['verseEnd'] == null ? '' : '–${cell['verseEnd']}'}',
              onVerseNumber: () => widget.onVerse(chapter, cell, reference),
              fontSize: 19 * widget.fontScale,
              highlights: highlights,
              direction: widget.resource['direction'] == 'rtl'
                  ? TextDirection.rtl
                  : TextDirection.ltr,
              onWord: (word, position) =>
                  widget.onWord(reference, word, position),
            ),
          ),
        ],
      ),
    );
  }

  void _refreshEntries() {
    _references.clear();
    final entries = <_ReaderEntry>[
      _ReaderEntry(
        'previous',
        () => TextButton.icon(
          onPressed: _loading ? null : () => _load(true),
          icon: const Icon(Icons.expand_less),
          label: const Text('Vorheriges Kapitel'),
        ),
      ),
    ];
    for (final chapter in _chapters) {
      final reference = asMap(chapter['reference']),
          works = asMap(chapter['referenceResources']);
      final chapterKey = _key(reference);
      final usedVerses = <int>{};
      void add(String id, Widget Function() builder, [Json? ref]) {
        if (ref != null) _references[id] = ref;
        entries.add(_ReaderEntry(id, builder, ref));
      }

      Json? anchor(int verse) =>
          usedVerses.add(verse) ? {...reference, 'verse': verse} : null;
      add(
        '$chapterKey:heading',
        () => Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 12),
          child: Text(
            asString(chapter['fullTitle']),
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        reference,
      );
      if (widget.resource['kind'] == 'bible') {
        if (asMap(chapter['chapter'])['empty'] == true) {
          add(
            '$chapterKey:empty',
            () => const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Dieses Werk enthält keinen Text für dieses Kapitel.',
              ),
            ),
          );
        }
        for (final row in asMaps(asMap(chapter['chapter'])['rows'])) {
          final cells = row['cells'] as List? ?? [];
          if (cells.isEmpty || cells.first == null) continue;
          final cell = asMap(cells.first),
              verse = asInt(asMap(cells.first)['verse']);
          add('$chapterKey:verse:$verse', () => _verse(chapter, row), {
            ...reference,
            'verse': verse,
            if (cell['verseEnd'] != null) 'verseEnd': cell['verseEnd'],
          });
        }
      }
      var index = 0;
      for (final entry in asMaps(works['commentaries'])) {
        final ref = {
          ...reference,
          if (entry['verseStart'] != null) 'verse': entry['verseStart'],
        };
        add(
          '$chapterKey:comment:${index++}',
          () => Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextButton(
                  onPressed: () => widget.onReference(ref),
                  child: Text(referenceLabel(ref)),
                ),
                if (entry['title'] != null)
                  Text(
                    asString(entry['title']),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                HtmlContent(
                  html: asString(entry['bodyHtml']),
                  onTapUrl: _openCommentaryLink,
                ),
              ],
            ),
          ),
          anchor(asInt(entry['verseStart'], 1)),
        );
      }
      for (final entry in asMaps(works['crossReferences'])) {
        final target = {
          'book': entry['toBook'],
          'chapter': entry['toChapter'],
          'verse': entry['toVerse'],
          if (entry['toVerseEnd'] != entry['toVerse'])
            'verseEnd': entry['toVerseEnd'],
        };
        add(
          '$chapterKey:cross:${index++}',
          () => ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              'Vers ${entry['fromVerse']} → ${referenceLabel(target)}',
            ),
            onTap: () => widget.onReference(target),
          ),
          anchor(asInt(entry['fromVerse'], 1)),
        );
      }
      if (asMaps(chapter['documentAnchors']).isNotEmpty) {
        add(
          '$chapterKey:notes',
          () => ExpansionTile(
            title: const Text('Eigene Notizen und Dokumente zu diesem Kapitel'),
            children: [
              for (final document in asMaps(chapter['documentAnchors']))
                ListTile(
                  leading: const Icon(Icons.description_outlined),
                  title: Text(asString(document['title'])),
                  onTap: () =>
                      AppScope.of(context)
                          .open('/notes/${document['documentId']}'),
                ),
            ],
          ),
        );
      }
    }
    entries.add(
      _ReaderEntry(
        'next',
        () => Column(
          children: [
            if (_error != null)
              Padding(padding: const EdgeInsets.all(12), child: Text(_error!)),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(),
              ),
            TextButton.icon(
              onPressed: _loading ? null : () => _load(false),
              icon: const Icon(Icons.expand_more),
              label: const Text('Nächstes Kapitel'),
            ),
          ],
        ),
      ),
    );
    _entries = entries;
    _anchorKey ??= _targetKey(widget.reference) ?? entries.first.id;
  }

  Future<bool> _openCommentaryLink(String url) async {
    final scope = AppScope.of(context);
    final uri = scope.api.origin.resolve(url);
    if (['http', 'https'].contains(uri.scheme) &&
        uri.origin == scope.api.origin.origin) {
      if (!RegExp(r'^/[GH]\d+$').hasMatch(uri.path) &&
          RegExp(r'^/[1-3]?[A-Za-zÄÖÜäöüß]+\d+(?:,\d+(?:-\d+)?)?$')
              .hasMatch(uri.path)) {
        widget.onReferenceText(Uri.decodeComponent(uri.path.substring(1)));
      } else {
        await scope.open('${uri.path}${uri.hasQuery ? '?${uri.query}' : ''}');
      }
      return true;
    }
    if (!['http', 'https', 'mailto'].contains(uri.scheme)) return false;
    if (await confirmAction(context, 'Externen Link öffnen?', uri.toString())) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
    return true;
  }

  Future<void> _pageBy(int direction) async {
    if (!_scroll.hasClients || _loading) return;
    if (direction > 0 &&
        _scroll.position.extentAfter <
            _scroll.position.viewportDimension * .9) {
      await _load(false);
    }
    if (direction < 0 &&
        _scroll.position.extentBefore <
            _scroll.position.viewportDimension * .9) {
      await _load(true);
    }
    if (!mounted || !_scroll.hasClients) return;
    _userScroll = true;
    _scroll.jumpTo(
      (_scroll.offset + direction * _scroll.position.viewportDimension * .88)
          .clamp(
            _scroll.position.minScrollExtent,
            _scroll.position.maxScrollExtent,
          ),
    );
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) {
      _needsCapture = true;
      capturePosition();
    }
  }

  Widget _item(int index) {
    final entry = _entries[index];
    return _ReaderViewportItem(
      key: ValueKey(entry.id),
      id: entry.id,
      visible: _visible,
      child: entry.builder(),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_chapters.isEmpty) {
      return Center(
        child: _error == null
            ? const CircularProgressIndicator()
            : TextButton.icon(
                onPressed: () => align(widget.reference),
                icon: const Icon(Icons.refresh),
                label: Text('Erneut laden: $_error'),
              ),
      );
    }
    var anchor = _entries.indexWhere((entry) => entry.id == _anchorKey);
    if (anchor < 0) anchor = 0;
    return Column(
      children: [
        Expanded(
          child: NotificationListener<ScrollStartNotification>(
            onNotification: (notification) {
              if (notification.dragDetails != null) _userScroll = true;
              return false;
            },
            child: Scrollbar(
              controller: _scroll,
              child: CustomScrollView(
                key: _viewport,
                controller: _scroll,
                center: _center,
                scrollCacheExtent: const ScrollCacheExtent.pixels(280),
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (_, index) => _item(anchor - 1 - index),
                        childCount: anchor,
                        addAutomaticKeepAlives: false,
                      ),
                    ),
                  ),
                  SliverPadding(
                    key: _center,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (_, index) => _item(anchor + index),
                        childCount: _entries.length - anchor,
                        addAutomaticKeepAlives: false,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (AppScope.of(context).eInk)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                tooltip: 'Vorherige Bildschirmseite',
                onPressed: _loading ? null : () => _pageBy(-1),
                icon: const Icon(Icons.arrow_back),
              ),
              const Flexible(
                child: Text('Blättern', textAlign: TextAlign.center),
              ),
              IconButton(
                tooltip: 'Nächste Bildschirmseite',
                onPressed: _loading ? null : () => _pageBy(1),
                icon: const Icon(Icons.arrow_forward),
              ),
            ],
          ),
      ],
    );
  }
}

/// Registration follows the viewport child's lifetime, so position capture scans
/// mounted rows only, even after reading hundreds of chapters.
class _ReaderViewportItem extends StatefulWidget {
  const _ReaderViewportItem({
    super.key,
    required this.id,
    required this.visible,
    required this.child,
  });
  final String id;
  final Map<String, BuildContext> visible;
  final Widget child;
  @override
  State<_ReaderViewportItem> createState() => _ReaderViewportItemState();
}

class _ReaderViewportItemState extends State<_ReaderViewportItem> {
  @override
  Widget build(BuildContext context) {
    widget.visible[widget.id] = context;
    return widget.child;
  }

  @override
  void dispose() {
    if (identical(widget.visible[widget.id], context)) {
      widget.visible.remove(widget.id);
    }
    super.dispose();
  }
}
