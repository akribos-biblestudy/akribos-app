import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api_client.dart';
import '../../core/app_scope.dart';
import '../../widgets/common.dart';
import '../search/search_screen.dart';
import 'books.dart';
import 'reader_dialogs.dart';
import 'reader_controller.dart';
import 'reader_lexicon_sheet.dart';
import 'reader_group_badge.dart';
import 'reader_tab_card.dart';
import 'reader_verse_menu.dart';
import 'reader_state.dart';
import 'verse_text.dart';
import 'reader_local_store.dart';
import 'reader_companion.dart';
import 'reader_tab_grid.dart';

class ReaderScreen extends StatefulWidget {
  const ReaderScreen({
    super.key,
    required this.path,
    this.controller,
    this.active = true,
    this.localStore,
  });
  final String path;
  final ReaderController? controller;
  final bool active;
  final ReaderLocalStore? localStore;
  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  AppApi? _api;
  ReaderLocalStore? _store;
  Json? _data;
  Object? _error;
  int _generation = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final api = AppScope.of(context).api;
    final id = asString(asMap(api.bootstrap['user'])['id']);
    final store =
        widget.localStore ??
        ReaderLocalStore(origin: api.origin, userId: id.isEmpty ? null : id);
    if (_api != api || _store?.scopeKey != store.scopeKey) {
      _api = api;
      _store = store;
      _load();
    }
  }

  @override
  void didUpdateWidget(ReaderScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path ||
        oldWidget.localStore != widget.localStore) {
      if (widget.localStore != null) _store = widget.localStore;
      _load();
    }
  }

  Future<void> _load() async {
    final generation = ++_generation;
    final api = _api!, store = _store!;
    setState(() {
      _data = null;
      _error = null;
    });
    try {
      final saved = await store.read();
      var destination = localReaderStartPath(widget.path, saved, api.bootstrap);
      for (var redirects = 0; redirects < 6; redirects++) {
        if (!mounted || generation != _generation) return;
        try {
          final data = await api.page(
            readerActionPath(
              destination,
              {},
              readerState: Uri.parse(destination).query,
            ),
          );
          if (!mounted || generation != _generation) return;
          if (data.containsKey('user') && !store.acceptsUser(data['user'])) {
            await AppScope.of(context).authenticationChanged();
            throw const ApiException(
              'Die Anmeldung hat sich geändert. Bitte öffne die Leseansicht erneut.',
            );
          }
          if (asMap(data['workspace']).isEmpty) {
            throw const ApiException(
              'Die Leseansicht konnte nicht geladen werden.',
            );
          }
          final workspace = asMap(data['workspace']);
          workspace['layoutSizes'] = asMap(saved?['layoutSizes']);
          data['readerWorkspaceDetached'] = true;
          data['versePerLine'] = saved?['versePerLine'] == true;
          data['companion'] = ReaderCompanion.fromJson(saved?['companion'])
              .toJson();
          await store.write(
            readerPath(workspace, asString(data['readerState'])),
            layoutSizes: asMap(workspace['layoutSizes']),
            versePerLine: data['versePerLine'] == true,
            companion: ReaderCompanion.fromJson(data['companion']),
          );
          if (mounted && generation == _generation) {
            setState(() => _data = data);
          }
          return;
        } on AppRedirect catch (redirect) {
          final uri = Uri.parse(redirect.location);
          if (uri.path.startsWith('/search') ||
              uri.path.startsWith('/login') ||
              RegExp(r'^/[GH]\d+$').hasMatch(uri.path)) {
            if (mounted && generation == _generation) {
              await AppScope.of(context).open(redirect.location);
            }
            return;
          }
          destination = localReaderStartPath(redirect.location, {
            'path': destination,
          }, api.bootstrap);
        }
      }
      throw const ApiException(
        'Die Reader-Adresse konnte nicht aufgelöst werden.',
      );
    } catch (error) {
      if (mounted && generation == _generation) setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('$_error', textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton.tonalIcon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: const Text('Erneut versuchen'),
              ),
            ],
          ),
        ),
      );
    }
    if (_data == null) return const Center(child: CircularProgressIndicator());
    return _ReaderView(
      key: ValueKey(_store!.scopeKey),
      data: _data!,
      store: _store!,
      controller: widget.controller,
      active: widget.active,
    );
  }
}

class _ReaderView extends StatefulWidget {
  const _ReaderView({
    super.key,
    required this.data,
    required this.store,
    required this.controller,
    required this.active,
  });
  final Json data;
  final ReaderLocalStore store;
  final ReaderController? controller;
  final bool active;
  @override
  State<_ReaderView> createState() => _ReaderViewState();
}

class _ReaderViewState extends State<_ReaderView> with WidgetsBindingObserver {
  late Json _data, _workspace, _searches;
  late String _filterState;
  AppScope? _scope;
  Timer? _timer;
  Future<bool>? _saving;
  final _panes = <String, GlobalKey<_ChapterPaneState>>{};
  final _chapterCaches = <String, _ChapterCache>{};
  final _columnsByTab = <String, Json>{};
  final _lexiconTabs = <String, Json>{};
  final _displayedTabs = <String, String>{};
  final _deferredPositions = <String, Json>{};
  final _activations = <Json>[];
  final _pageControllers = <String, PageController>{};
  Future<bool>? _switching;
  bool _activationInFlight = false;
  bool _discardPending = false;
  Json? _failedActivation;
  bool _busy = false, _dirty = false;
  int _revision = 0;
  String? _saveError;
  String? _mobileTile;
  bool _versePerLine = false;
  ReaderCompanion _companion = const ReaderCompanion();
  final _companionPane = GlobalKey<_ChapterPaneState>();
  void _adopt([Json? incoming]) {
    _data = asMap(jsonDecode(jsonEncode(incoming ?? widget.data)));
    if (_data.containsKey('versePerLine')) {
      _versePerLine = _data['versePerLine'] == true;
    }
    if (_data.containsKey('companion')) {
      _companion = ReaderCompanion.fromJson(_data['companion']);
    }
    _data['readerWorkspaceDetached'] = true;
    _workspace = asMap(_data['workspace']);
    _searches = asMap(_data['searchQueries']);
    _filterState = asString(_data['readerState']);
    _mobileTile = asString(_workspace['focusedTileId']);
    final tiles = asMaps(_workspace['tiles']);
    if (!tiles.any(
      (tile) => tile['id'] == _mobileTile && asMaps(tile['tabs']).isNotEmpty,
    )) {
      final firstReadable = tiles
          .where((tile) => asMaps(tile['tabs']).isNotEmpty)
          .firstOrNull;
      if (firstReadable != null) _mobileTile = asString(firstReadable['id']);
    }
    for (final column in asMaps(_data['columns'])) {
      final tile = asMaps(
        _workspace['tiles'],
      ).firstWhere((tile) => tile['id'] == column['tileId'], orElse: () => {});
      final tab = activeTab(tile);
      _columnsByTab['${tab['id']}:${tab['resourceId']}'] = column;
    }
    _dirty = false;
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
    _scope = AppScope.of(context);
    _scope!.setNavigationGuard(this, widget.active ? _flush : null);
    _bindController();
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
  }

  @override
  void didChangeMetrics() {
    // Window metrics arrive before relayout, while the old glyph positions and
    // transforms can still be read. Finish a pending scroll capture now.
    for (final pane in _panes.values) {
      pane.currentState?.capturePosition();
    }
  }

  String get _state => encodeReaderState(_workspace, _searches, _filterState);
  void _bindController() {
    widget.controller?.attach(
      this,
      showTabs: _showTabs,
      flush: _flush,
      setVersePerLine: _setVersePerLine,
      setCompanion: _setCompanion,
    );
  }

  Future<bool> _setCompanion(ReaderCompanion value) async {
    if (_companion == value) return _flush();
    if (!await _flush() || !mounted) return false;
    setState(() {
      _companion = value;
      _dirty = true;
      _revision++;
    });
    return _save();
  }

  Future<bool> _setVersePerLine(bool value) async {
    if (_versePerLine == value) return _flush();
    if (!await _flush() || !mounted) return false;
    setState(() {
      _versePerLine = value;
      _dirty = true;
      _revision++;
    });
    return _save();
  }

  Future<bool> _flush() async {
    if (_discardPending) return true;
    if (_switching != null && !await _switching!) return false;
    if (_failedActivation != null) return false;
    final saved = await _flushPositions();
    final tile = asMaps(_workspace['tiles'])
        .firstWhere((item) => item['id'] == _mobileTile, orElse: () => {});
    widget.controller?.updateReference(asMap(_shownTab(tile)['reference']));
    return saved;
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
    if (!_dirty) return true;
    try {
      while (_dirty && mounted) {
        final revision = _revision;
        await widget.store.write(
          readerPath(_workspace, _state),
          layoutSizes: asMap(_workspace['layoutSizes']),
          versePerLine: _versePerLine,
          companion: _companion,
        );
        if (revision == _revision) _dirty = false;
      }
      if (mounted) setState(() => _saveError = null);
      return true;
    } catch (error) {
      if (mounted) {
        setState(
          () => _saveError =
              'Die Tabs konnten auf diesem Gerät nicht gespeichert werden: $error',
        );
      }
      return false;
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
    widget.controller?.updateReference(reference);
    _companionPane.currentState?.align(reference);
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
    if (_shownTab(tile)['id'] == tabId &&
        _mobileTile == tileId &&
        _failedActivation == null) {
      return;
    }
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
        final predicted = asMap(jsonDecode(jsonEncode(_workspace)));
        activateReaderTab(predicted, tileId, tabId);
        _activationInFlight = true;
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
        setState(() {
          _workspace = predicted;
          _data['workspace'] = predicted;
          _dirty = true;
          _revision++;
        });
        if (needsArticle) {
          await _reloadView(
            readerPath(_workspace, _state),
            mobileTile: _mobileTile,
          );
        }
        _activationInFlight = false;
        if (_displayedTabs[tileId] == tabId) _displayedTabs.remove(tileId);
        final reference = _deferredPositions.remove(tabId);
        if (reference != null) {
          updateReadingPosition(_workspace, tileId, tabId, reference);
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
      final tabId = asString(activeTab(tile)['id']);
      final reference = _deferredPositions.remove(tabId);
      if (reference == null) continue;
      updateReadingPosition(_workspace, asString(tile['id']), tabId, reference);
      _dirty = true;
      _revision++;
    }
    _workspace['focusedTileId'] = focus;
    if (!await _flushPositions()) return false;
    // A swipe may arrive while the final disk write is pending. The navigation
    // guard must drain that choice too before reporting the Reader as saved.
    if (_activations.isNotEmpty && mounted) return _commitActivations();
    return true;
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
        final data = await _scope!.api.page(
          readerActionPath(
            destination,
            {},
            readerState: Uri.parse(destination).query,
          ),
        );
        if (data.containsKey('user') &&
            !widget.store.acceptsUser(data['user'])) {
          await _scope!.authenticationChanged();
          throw const ApiException(
            'Die Anmeldung hat sich geändert. Bitte öffne die Leseansicht erneut.',
          );
        }
        if (mounted) {
          setState(() {
            asMap(data['workspace'])['layoutSizes'] = _workspace['layoutSizes'];
            _adopt(data);
            _dirty = true;
            _revision++;
            if (mobileTile != null &&
                asMaps(_workspace['tiles']).any(
                  (tile) =>
                      tile['id'] == mobileTile &&
                      asMaps(tile['tabs']).isNotEmpty,
                )) {
              _mobileTile = mobileTile;
            }
            _showSelectedPage();
          });
          await _save();
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
    final result = await showReaderVerseMenu(
      context,
      reference: ref,
      text: plain,
      signedIn: _data['user'] != null,
      styles: asMaps(_data['highlightStyles']),
      highlights: existingHighlights,
      lists: asMaps(_data['lists']),
      selectedLists: {
        for (final entry in asMaps(chapter['markedVerses']))
          if (entry['verse'] == reference['verse']) asString(entry['listId']),
      },
    );
    if (result == null || !mounted) return;
    if (result == 'share') {
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
        _dirty = true;
        _revision++;
      });
      await _flush();
    }
  }

  Future<void> _tabMenu(Json tile, Json tab, String action) async {
    if (action == 'replace') {
      await _chooseResource(tile, replace: tab);
    } else if (action == 'search') {
      final resource = asMaps(_data['readerResources']).firstWhere(
        (resource) => resource['id'] == tab['resourceId'],
        orElse: () => {},
      );
      await _search(tile, tab, resource);
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

  Future<void> _showTabs() async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheet) => StatefulBuilder(
        builder: (sheet, setSheetState) => readerOverlayScope(
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
                      IconButton(
                        tooltip: 'Fertig',
                        onPressed: () => Navigator.pop(sheet),
                        icon: const Icon(Icons.check),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final tiles = asMaps(_workspace['tiles']);
                      final choices = _flatTabs(tiles);
                      final scaler = MediaQuery.textScalerOf(context);
                      final columns =
                          constraints.maxWidth < 360 || scaler.scale(14) > 20
                          ? 1
                          : constraints.maxWidth < 640
                          ? 2
                          : (constraints.maxWidth / 230).floor().clamp(3, 5);
                      Widget card(int index) {
                        if (index == choices.length) {
                          return Card(
                            key: const ValueKey('reader-add-tab'),
                            clipBehavior: Clip.antiAlias,
                            child: InkWell(
                              onTap: () {
                                Navigator.pop(sheet);
                                final tile = _addTargetTile();
                                if (tile.isNotEmpty) _chooseResource(tile);
                              },
                              child: const Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.add, size: 40),
                                    SizedBox(height: 12),
                                    Text('Neuer Tab'),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }
                        final tile = asMap(choices[index]['tile']),
                            tab = asMap(choices[index]['tab']);
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
                              _mobileTile == tile['id'],
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
                              PopupMenuItem(
                                value: 'search',
                                child: Text(
                                  resource['kind'] == 'lexicon'
                                      ? 'Lexikoneintrag öffnen'
                                      : 'In diesem Werk suchen',
                                ),
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
                            ],
                          ),
                        );
                      }

                      return ReaderTabGrid(
                        ids: [
                          for (final choice in choices)
                            asString(asMap(choice['tab'])['id']),
                        ],
                        cards: [
                          for (var index = 0; index < choices.length; index++)
                            card(index),
                        ],
                        addCard: card(choices.length),
                        columns: columns,
                        cardHeight: ReaderTabCard.heightFor(scaler),
                        enabled: !_busy,
                        onMove: (id, index) async {
                          await _moveTab(id, index);
                          if (sheet.mounted) setSheetState(() {});
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
      ),
    );
  }

  Future<void> _moveTab(String id, int destination) async {
    if (_busy || !await _flush() || !mounted) return;
    setState(() {
      if (!moveReaderTab(_workspace, id, destination)) return;
      _mobileTile = asString(_workspace['focusedTileId']);
      _displayedTabs.clear();
      _dirty = true;
      _revision++;
      _showSelectedPage();
    });
    await _save();
  }

  Json _addTargetTile() {
    final tiles = asMaps(_workspace['tiles']);
    return tiles.firstWhere(
      (tile) => tile['id'] == _mobileTile,
      orElse: () => tiles.firstOrNull ?? <String, dynamic>{},
    );
  }

  // Every ordinary resource is one local tab. The optional tablet companion
  // follows the visible Bible without becoming a tab or a server workspace.
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
        final choices = _flatTabs(tiles);
        final selected = choices.indexWhere(
          (item) =>
              _shownTab(asMap(item['tile']))['id'] ==
                  asMap(item['tab'])['id'] &&
              asMap(item['tile'])['id'] == _mobileTile,
        );
        if (selected >= 0 && (entry.value.page ?? -1).round() != selected) {
          entry.value.jumpToPage(selected);
        }
      }
    });
  }

  Widget _resourcePages(List<Json> tiles) {
    final choices = _flatTabs(tiles);
    if (choices.isEmpty) return _tile(_addTargetTile());
    const deckKey = 'mobile';
    final selected = choices.indexWhere(
      (item) =>
          _shownTab(asMap(item['tile']))['id'] == asMap(item['tab'])['id'] &&
          asMap(item['tile'])['id'] == _mobileTile,
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
          child: _tile(tile, selectedTab: tab),
        );
      },
    );
  }

  Widget _readerPanes(
    List<Json> tiles,
    Json selectedTab,
    Json selectedResource,
  ) => LayoutBuilder(
    builder: (context, constraints) {
      final reader = _resourcePages(tiles);
      if (!_companion.enabled ||
          selectedResource['kind'] != 'bible' ||
          !canShowReaderCompanion(
            constraints.maxWidth,
            MediaQuery.textScalerOf(context),
          )) {
        return reader;
      }
      final commentaries = asMaps(_data['readerResources'])
          .where((resource) => resource['kind'] == 'commentary');
      final resource = _companion.resourceId.isEmpty
          ? commentaries.firstOrNull
          : commentaries
                .where((resource) => resource['id'] == _companion.resourceId)
                .firstOrNull;
      final companion = Expanded(
        key: const ValueKey('reader-companion'),
        child: ColoredBox(
          color: Theme.of(context).scaffoldBackgroundColor,
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        resource == null
                            ? 'Kommentarspalte'
                            : asString(resource['name']),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Kommentarspalte schließen',
                    icon: const Icon(Icons.close),
                    onPressed: () =>
                        _setCompanion(_companion.copyWith(enabled: false)),
                  ),
                ],
              ),
              if (_scope!.eInk)
                const SizedBox(
                  width: double.infinity,
                  height: 2,
                  child: ColoredBox(color: Colors.black),
                ),
              Expanded(
                child: resource == null
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            'Der ausgewählte Kommentar ist nicht verfügbar. '
                            'Bitte wähle in den Einstellungen einen verfügbaren Kommentar.',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    : _ChapterPane(
                        key: _companionPane,
                        initial: const {},
                        cache: _chapterCaches.putIfAbsent(
                          'companion:${resource['id']}',
                          _ChapterCache.new,
                        ),
                        resource: resource,
                        reference: Map.of(asMap(selectedTab['reference'])),
                        active: widget.active,
                        follower: true,
                        fontScale: asInt(_data['readerFontScale'], 100) / 100,
                        versePerLine: _versePerLine,
                        // Scrolling comments must never move the Bible or its
                        // linked tabs; only Bible scrolling drives the follower.
                        onPosition: (_) {},
                        onWord: (_, _, _) {},
                        onVerse: (_, _, _) {},
                        onReference: (reference) => _mutate('setTabReference', {
                          'tileId': _mobileTile,
                          'tabId': selectedTab['id'],
                          'reference': referenceLabel(reference),
                        }),
                        onReferenceText: (reference) =>
                            _mutate('setTabReference', {
                              'tileId': _mobileTile,
                              'tabId': selectedTab['id'],
                              'reference': reference,
                            }),
                      ),
              ),
            ],
          ),
        ),
      );
      final primary = Expanded(
        key: const ValueKey('reader-primary'),
        child: reader,
      );
      return Row(
        key: const ValueKey('reader-two-columns'),
        children: [
          _companion.onLeft ? companion : primary,
          VerticalDivider(
            width: _scope!.eInk ? 2 : 1,
            thickness: _scope!.eInk ? 2 : 1,
            color: _scope!.eInk
                ? Colors.black
                : Theme.of(context).colorScheme.outlineVariant,
          ),
          _companion.onLeft ? primary : companion,
        ],
      );
    },
  );

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

  Widget _tile(Json tile, {Json? selectedTab}) {
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
                  PopupMenuItem(
                    value: 'search',
                    child: Text(
                      resource['kind'] == 'lexicon'
                          ? 'Lexikoneintrag öffnen'
                          : 'In diesem Werk suchen',
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'details',
                    child: Text('Informationen zum Werk'),
                  ),
                  const PopupMenuDivider(),
                  for (final link in ['', 'A', 'B', 'C', 'D', 'E'])
                    PopupMenuItem(
                      value: 'link:$link',
                      child: _groupChoice(tab, link),
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
          if (_scope!.eInk)
            const SizedBox(
              width: double.infinity,
              height: 2,
              child: ColoredBox(color: Colors.black),
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
                        _mobileTile == tile['id'],
                    resource: resource,
                    reference: asMap(tab['reference']),
                    fontScale: asInt(_data['readerFontScale'], 100) / 100,
                    versePerLine: _versePerLine,
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
    final selectedTab = _shownTab(selectedTile);
    final selectedResource = asMaps(_data['readerResources']).firstWhere(
      (resource) => resource['id'] == selectedTab['resourceId'],
      orElse: () => {},
    );
    final resourceName = asString(
      selectedResource['name'],
      _resourceTitle(selectedTab),
    );
    final abbreviation = asString(selectedResource['abbrev']);
    widget.controller?.update(
      tabCount: _flatTabs(tiles).length,
      companion: _companion,
      commentaries: [
        for (final resource in asMaps(_data['readerResources']))
          if (resource['kind'] == 'commentary')
            ReaderSearchResource(
              id: asString(resource['id']),
              title: asString(resource['name'], asString(resource['id'])),
              kind: 'commentary',
            ),
      ],
      versePerLine: _versePerLine,
      activeTitle: _resourceTitle(selectedTab),
      reference: asMap(selectedTab['reference']),
      activeResource: selectedResource.isEmpty
          ? null
          : ReaderSearchResource(
              id: asString(selectedResource['id']),
              title: abbreviation.isEmpty || abbreviation == resourceName
                  ? resourceName
                  : '$resourceName ($abbreviation)',
              kind: asString(selectedResource['kind']),
              direction: asString(selectedResource['direction'], 'ltr'),
            ),
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
                        _failedActivation = null;
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
        Expanded(
          child: tiles.isEmpty
              ? const Center(child: Text('Kein Werk verfügbar.'))
              : _readerPanes(tiles, selectedTab, selectedResource),
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
  bool? versePerLine;
  double? viewportWidth;
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
    this.versePerLine = false,
    this.follower = false,
  });
  final Json initial, resource, reference;
  final _ChapterCache cache;
  final double fontScale;
  final bool active, versePerLine, follower;
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
  final _paragraphKeys = <String, GlobalKey<VerseTextState>>{};
  final _paragraphReferences = <String, List<Json>>{};
  List<Json> get _chapters => widget.cache.chapters;
  bool _loading = false,
      _aligning = false,
      _userScroll = false,
      _needsCapture = false;
  String? _error, _anchorKey;
  Timer? _timer;
  Json? _nextAlignment;
  Json? _requestedReference;
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
        widget.cache.fontScale == widget.fontScale &&
        widget.cache.versePerLine == widget.versePerLine;
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
    if (oldWidget.versePerLine != widget.versePerLine) {
      _refreshEntries();
      _anchorKey = _targetKey(widget.reference);
    }
    if (widget.active &&
        (!oldWidget.active ||
            jsonEncode(oldWidget.reference) != jsonEncode(widget.reference) ||
            oldWidget.fontScale != widget.fontScale ||
            oldWidget.versePerLine != widget.versePerLine)) {
      if (jsonEncode(widget.cache.reference) != jsonEncode(widget.reference) ||
          widget.cache.fontScale != widget.fontScale ||
          widget.cache.versePerLine != widget.versePerLine) {
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
    _requestedReference = Map.of(reference);
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
          // A zero-duration scroll updates pixels before the paragraph's paint
          // transform. Wait for layout before measuring the in-flow verse.
          await WidgetsBinding.instance.endOfFrame;
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
      if (target != null && !widget.versePerLine && mounted) {
        final refs = _paragraphReferences[target] ?? [];
        final index = refs.lastIndexWhere(
          (ref) => asInt(ref['verse']) <= asInt(reference['verse']),
        );
        final paragraph = _paragraphKeys[target]?.currentState;
        final render = paragraph?.paragraph;
        final viewport = _viewport.currentContext?.findRenderObject();
        if (paragraph != null &&
            render != null &&
            viewport is RenderBox &&
            _scroll.hasClients) {
          final delta =
              render.localToGlobal(Offset(0, paragraph.passageTop(index))).dy -
              viewport.localToGlobal(Offset.zero).dy;
          _scroll.jumpTo(
            (_scroll.offset + delta).clamp(
              _scroll.position.minScrollExtent,
              _scroll.position.maxScrollExtent,
            ),
          );
        }
      }
      widget.cache.reference = Map.of(reference);
      widget.cache.versePerLine = widget.versePerLine;
      widget.cache.fontScale = widget.fontScale;
      if (_error != null && mounted) {
        setState(() => _error = null);
      }
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() {
          _error = '$error';
          if (widget.follower) _chapters.clear();
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
      // A flow paragraph may span several screens. Its text at the viewport
      // top wins over a following chapter heading that happens to be closer
      // to the top than the paragraph's offscreen start.
      final candidateDistance = y <= 0 && y + render.size.height > 0
          ? 0.0
          : y.abs();
      if (y >= -render.size.height && candidateDistance < distance) {
        distance = candidateDistance;
        closest = _references[entry.key];
        final paragraph = _paragraphKeys[entry.key]?.currentState;
        final refs = _paragraphReferences[entry.key];
        final text = paragraph?.paragraph;
        if (paragraph != null &&
            text != null &&
            refs != null &&
            refs.isNotEmpty) {
          final index = paragraph.passageAtHeight(
            top - text.localToGlobal(Offset.zero).dy,
          );
          closest = refs[index.clamp(0, refs.length - 1)];
        }
      }
    }
    if (closest != null) {
      widget.cache.reference = Map.of(closest);
      widget.onPosition(closest);
    }
  }

  Json _cell(Json row) => asMap((row['cells'] as List).first);
  Json _verseReference(Json chapter, Json cell) => {
    ...asMap(chapter['reference']),
    'verse': cell['verse'],
    if (cell['verseEnd'] != null) 'verseEnd': cell['verseEnd'],
  };

  List<Json> _highlights(Json chapter, Json cell) {
    final verse = asInt(cell['verse']);
    return [
      for (final item in asMaps(chapter['highlights']))
        if (verse >= asInt(item['verse']) &&
            verse <= asInt(item['endVerse'], asInt(item['verse'])) &&
            (item['resourceId'] == null ||
                item['resourceId'] == widget.resource['id']))
          {
            'start': verse == item['verse'] ? asInt(item['startWord']) : 0,
            'end': verse == asInt(item['endVerse'], asInt(item['verse']))
                ? asInt(item['endWord'], 100000)
                : 100000,
            'color': item['color'],
            'name': item['name'],
          },
    ];
  }

  VersePassage _passage(Json chapter, Json row) {
    final cell = _cell(row), reference = _verseReference(chapter, _cell(row));
    return VersePassage(
      segments: cell['segments'] as List? ?? [],
      number:
          '${cell['verse']}${cell['verseEnd'] == null ? '' : '–${cell['verseEnd']}'}',
      highlights: _highlights(chapter, cell),
      onOpen: () => widget.onVerse(chapter, cell, reference),
      onWord: (word, position) => widget.onWord(reference, word, position),
    );
  }

  Widget _bibleBlock(Json chapter, List<Json> rows, String id) {
    final passages = rows.map((row) => _passage(chapter, row)).toList();
    final heading = asString(_cell(rows.first)['heading']);
    final labels = passages
        .expand((passage) => passage.highlights)
        .map((item) => asString(item['name'], 'Markierung'))
        .toSet();
    final first = passages.first;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (AppScope.of(context).eInk && labels.isNotEmpty)
            Text(
              'Markiert: ${labels.join(', ')}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          if (heading.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                heading,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontSize: 19 * widget.fontScale * 1.2,
                  height: 1.4,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          VerseText(
            key: widget.versePerLine
                ? null
                : _paragraphKeys.putIfAbsent(
                    id,
                    () => GlobalKey<VerseTextState>(),
                  ),
            selectable: false,
            segments: first.segments,
            passages: widget.versePerLine ? null : passages,
            verseNumber: first.number,
            onVerseNumber: first.onOpen,
            onWord: first.onWord,
            fontSize: 19 * widget.fontScale,
            highlights: first.highlights,
            direction: widget.resource['direction'] == 'rtl'
                ? TextDirection.rtl
                : TextDirection.ltr,
          ),
        ],
      ),
    );
  }

  void _refreshEntries() {
    _references.clear();
    _paragraphReferences.clear();
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
      final chapterReference = asMap(chapter['reference']);
      final reference = <String, dynamic>{
        'book': chapterReference['book'],
        'chapter': chapterReference['chapter'],
      };
      final works = asMap(chapter['referenceResources']);
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
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(fontSize: 19 * widget.fontScale * 1.4, height: 1.35),
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
        final groups = <List<Json>>[];
        for (final row in asMaps(asMap(chapter['chapter'])['rows'])) {
          final cells = row['cells'] as List? ?? [];
          if (cells.isEmpty || cells.first == null) continue;
          if (widget.versePerLine ||
              groups.isEmpty ||
              asString(_cell(row)['heading']).isNotEmpty) {
            groups.add([]);
          }
          groups.last.add(row);
        }
        for (final rows in groups) {
          final ref = _verseReference(chapter, _cell(rows.first));
          final id = '$chapterKey:verse:${ref['verse']}';
          if (!widget.versePerLine) {
            _paragraphReferences[id] = [
              for (final row in rows) _verseReference(chapter, _cell(row)),
            ];
          }
          add(id, () => _bibleBlock(chapter, rows, id), ref);
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
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontSize: 19 * widget.fontScale * 1.2,
                      height: 1.4,
                    ),
                  ),
                HtmlContent(
                  html: asString(entry['bodyHtml']),
                  textStyle: readingTextStyle(
                    context,
                    fontScale: widget.fontScale,
                  ),
                  scalableListMarkers: true,
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
    _paragraphKeys.removeWhere(
      (id, _) => !_paragraphReferences.containsKey(id),
    );
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
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final previousWidth = widget.cache.viewportWidth;
      widget.cache.viewportWidth = constraints.maxWidth;
      if (!widget.active &&
          previousWidth != null &&
          previousWidth != constraints.maxWidth) {
        widget.cache.reference = null;
      }
      if (widget.active &&
          previousWidth != null &&
          previousWidth != constraints.maxWidth) {
        // Settings flush before changing the split; didChangeMetrics captures
        // window resizes before layout. Reuse their verse, never an old pixel
        // offset or transforms from a tree that is currently being laid out.
        final reference = Map<String, dynamic>.of(
          widget.cache.reference ?? widget.reference,
        );
        WidgetsBinding.instance.addPostFrameCallback((_) => align(reference));
      }
      return _buildContent(context);
    },
  );

  Widget _buildContent(BuildContext context) {
    if (_chapters.isEmpty) {
      return Center(
        child: _error == null
            ? const CircularProgressIndicator()
            : TextButton.icon(
                onPressed: () => align(_requestedReference ?? widget.reference),
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
