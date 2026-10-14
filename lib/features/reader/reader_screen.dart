import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
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
import 'highlight_dialog.dart';
import 'reader_notes.dart';
import 'reader_layout.dart';
import 'reader_state.dart';
import 'verse_text.dart';
import 'workspace_screen.dart';

class ReaderScreen extends StatelessWidget {
  const ReaderScreen({super.key, required this.path});
  final String path;
  @override
  Widget build(BuildContext context) => RemotePage(
    path: path,
    builder: (context, data, reload) =>
        _ReaderView(data: data, path: path, reload: reload),
  );
}

class _ReaderView extends StatefulWidget {
  const _ReaderView({
    required this.data,
    required this.path,
    required this.reload,
  });
  final Json data;
  final String path;
  final Future<void> Function() reload;
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
  bool _busy = false, _dirty = false;
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
    _dirty = false;
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
    _scope!.setNavigationGuard(this, _flush);
    if (firstLoad) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _follow());
    }
  }

  @override
  void didUpdateWidget(_ReaderView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data != widget.data) _adopt();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _scope?.setNavigationGuard(this, null);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
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
  Future<bool> _flush() {
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
          result = asMap(
            await _scope!.api.send(
              'PUT',
              '/api/reader/workspaces/${_data['workspaceId']}/view',
              data: {
                'snapshot': _snapshot,
                'workspaceVersion': _data['workspaceVersion'],
                'workspaceContentVersion': _data['workspaceContentVersion'],
              },
            ),
          );
          if (result['saved'] != true) {
            throw const ApiException(
              'Die Ansicht wurde nicht gespeichert. Bitte den aktuellen Stand neu laden.',
            );
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
    if (_busy) return;
    if (jsonEncode(tab['reference']) == jsonEncode(reference)) return;
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

  Future<void> _reloadView(String path, {String? mobileTile}) async {
    var destination = path;
    for (var redirects = 0; redirects < 6; redirects++) {
      try {
        final data = await _scope!.api.page(destination);
        if (mounted) {
          setState(() {
            _adopt(data);
            if (mobileTile != null) _mobileTile = mobileTile;
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
    if (selected != null) {
      await _mutate('openLexiconTab', {
        'tileId': tile['id'],
        'tabId': tab['id'],
        'lookup': selected,
        'currentReference': referenceLabel(asMap(tab['reference'])),
        'sourceReference': referenceLabel(reference),
        'word': word['text'],
        'wordPosition': position,
      });
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

  Widget _tabStrip(List<Json> tiles, {bool mobile = false}) {
    final resources = asMaps(_data['readerResources']);
    return SizedBox(
      height: 49,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final tile in tiles) ...[
            for (final tab in asMaps(tile['tabs']))
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 5),
                child: ChoiceChip(
                  label: Text(
                    asString(
                      resources.firstWhere(
                        (item) => item['id'] == tab['resourceId'],
                        orElse: () => {},
                      )['tabTitle'],
                      asString(tab['resourceId']),
                    ),
                  ),
                  selected:
                      tile['activeTabId'] == tab['id'] &&
                      (!mobile || _mobileTile == tile['id']),
                  onSelected: _busy
                      ? null
                      : (_) {
                          if (mobile &&
                              tile['activeTabId'] == tab['id'] &&
                              _mobileTile == tile['id']) {
                            return;
                          } else {
                            _mutate('activateTab', {
                              'tileId': tile['id'],
                              'tabId': tab['id'],
                              'currentReference': referenceLabel(
                                asMap(activeTab(tile)['reference']),
                              ),
                            });
                          }
                        },
                ),
              ),
            IconButton(
              tooltip: 'Werk hinzufügen',
              onPressed: _busy ? null : () => _chooseResource(tile),
              icon: const Icon(Icons.add),
            ),
          ],
        ],
      ),
    );
  }

  Widget _tile(Json tile, {bool mobile = false}) {
    final tab = activeTab(tile);
    if (tab.isEmpty) {
      return Center(
        child: FilledButton.tonalIcon(
          onPressed: () => _chooseResource(tile),
          icon: const Icon(Icons.add),
          label: const Text('Werk hinzufügen'),
        ),
      );
    }
    final column = asMaps(
      _data['columns'],
    ).firstWhere((column) => column['tileId'] == tile['id'], orElse: () => {});
    final resource = asMap(column['resource']);
    final query = asString(_searches[tab['id']]);
    final tabKey = asString(tab['id']);
    final paneKey = _panes.putIfAbsent(
      tabKey,
      () => GlobalKey<_ChapterPaneState>(),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        children: [
          if (!mobile) _tabStrip([tile]),
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () => _goTo(tile, tab),
                  child: Text(
                    referenceLabel(asMap(tab['reference'])),
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
                      child: Text(
                        '${tab['linkSet'] == (link.isEmpty ? null : link) ? '✓ ' : ''}Tabgruppe ${link.isEmpty ? 'Keine' : link}',
                      ),
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
                  child: Text(asString(tab['linkSet'], '–')),
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
                    tab: tab,
                    entry: asMap(column['lexiconEntry']),
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
    final colors = Theme.of(context).colorScheme;
    return Column(
      children: [
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
                    onPressed: _flush,
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
                        if (mounted) await widget.reload();
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
        Material(
          color: colors.surfaceContainerLow,
          child: SizedBox(
            height: 48,
            child: Row(
              children: [
                const SizedBox(width: 8),
                PopupMenuButton<String>(
                  tooltip: 'Anordnung',
                  icon: const Icon(Icons.dashboard_outlined),
                  onSelected: (layout) =>
                      _mutate('setLayout', {'layout': layout}),
                  itemBuilder: (context) => readerLayouts.entries
                      .map(
                        (layout) => PopupMenuItem(
                          value: layout.key,
                          child: Text(layout.value),
                        ),
                      )
                      .toList(),
                ),
                if (_data['user'] != null)
                  IconButton(
                    tooltip: 'Arbeitsbereiche',
                    onPressed: () async {
                      if (await _flush() && mounted) {
                        await showWorkspaces(this.context, snapshot: _snapshot);
                      }
                    },
                    icon: const Icon(Icons.workspaces_outline),
                  ),
                if (_data['user'] != null)
                  IconButton(
                    tooltip: 'Eigene Notizen und Dokumente',
                    onPressed: _notes,
                    icon: const Icon(Icons.note_alt_outlined),
                  ),
                const Spacer(),
                IconButton(
                  tooltip: 'Schrift verkleinern',
                  onPressed: () => _mutate('adjustFontSize', {'delta': -5}),
                  icon: const Icon(Icons.text_decrease),
                ),
                IconButton(
                  tooltip: 'Schrift vergrößern',
                  onPressed: () => _mutate('adjustFontSize', {'delta': 5}),
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
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (tiles.isEmpty) {
                return const Center(child: Text('Kein Werk verfügbar.'));
              }
              if (constraints.maxWidth < 768) {
                final tile = tiles.firstWhere(
                  (tile) => tile['id'] == _mobileTile,
                  orElse: () => tiles.first,
                );
                return Column(
                  children: [
                    _tabStrip(tiles, mobile: true),
                    Expanded(child: _tile(tile, mobile: true)),
                  ],
                );
              }
              final children = tiles.map((tile) => _tile(tile)).toList();
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

class _ChapterCache {
  final chapters = <Json>[];
  double offset = 0;
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
    this.fontScale = 1,
  });
  final Json initial, resource, reference;
  final _ChapterCache cache;
  final double fontScale;
  final void Function(Json) onPosition, onReference;
  final void Function(String) onReferenceText;
  final void Function(Json, Json, int) onWord;
  final void Function(Json, Json, Json) onVerse;
  @override
  State<_ChapterPane> createState() => _ChapterPaneState();
}

class _ChapterPaneState extends State<_ChapterPane> {
  late final _scroll = ScrollController(
    initialScrollOffset: widget.cache.offset,
  );
  final _viewport = GlobalKey();
  final _keys = <String, GlobalKey>{};
  final _references = <String, Json>{};
  List<Json> get _chapters => widget.cache.chapters;
  bool _loading = false, _aligning = false, _userScroll = false;
  String? _error;
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    if (_chapters.isEmpty) _chapters.add(widget.initial);
    _scroll.addListener(_onScroll);
    if (jsonEncode(widget.cache.reference) != jsonEncode(widget.reference) ||
        widget.cache.fontScale != widget.fontScale) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => align(widget.reference),
      );
    }
  }

  @override
  void didUpdateWidget(_ChapterPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.resource['id'] != widget.resource['id']) {
      _chapters
        ..clear()
        ..add(widget.initial);
      _keys.clear();
      _references.clear();
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => align(widget.reference),
      );
    } else if (oldWidget.initial != widget.initial) {
      final index = _chapters.indexWhere(
        (chapter) =>
            jsonEncode(chapter['reference']) ==
            jsonEncode(widget.initial['reference']),
      );
      if (index >= 0) _chapters[index] = widget.initial;
    }
    if (jsonEncode(oldWidget.reference) != jsonEncode(widget.reference) ||
        oldWidget.fontScale != widget.fontScale) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => align(widget.reference),
      );
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    if (_scroll.hasClients) widget.cache.offset = _scroll.offset;
    _scroll.dispose();
    super.dispose();
  }

  String _key(Json reference) =>
      '${reference['book']}:${reference['chapter']}:${reference['verse'] ?? 1}';
  Json? _nextAlignment;
  Future<void> align(Json reference) async {
    if (!mounted || reference.isEmpty) return;
    if (_aligning) {
      _nextAlignment = Map<String, dynamic>.from(reference);
      return;
    }
    _aligning = true;
    final resourceId = widget.resource['id'];
    try {
      if (!_chapters.any(
        (chapter) =>
            asMap(chapter['reference'])['book'] == reference['book'] &&
            asMap(chapter['reference'])['chapter'] == reference['chapter'],
      )) {
        final chapter = asMap(
          await AppScope.of(context).api.get(
            '/api/reader/${reference['book']}/${reference['chapter']}?resource=${Uri.encodeComponent(asString(widget.resource['id']))}',
          ),
        );
        if (!mounted || widget.resource['id'] != resourceId) return;
        setState(() {
          _chapters
            ..clear()
            ..add(chapter);
          _keys.clear();
          _references.clear();
        });
        await WidgetsBinding.instance.endOfFrame;
      }
      if (!mounted) return;
      var target = reference['verse'] == null
          ? _keys['${_key(reference)}:heading']?.currentContext
          : _keys[_key(reference)]?.currentContext;
      if (target == null) {
        final candidates =
            _references.entries
                .where(
                  (entry) =>
                      entry.value['book'] == reference['book'] &&
                      entry.value['chapter'] == reference['chapter'] &&
                      asInt(entry.value['verse'], 1) <=
                          asInt(reference['verse'], 1) &&
                      _keys[entry.key]?.currentContext != null,
                )
                .toList()
              ..sort(
                (left, right) =>
                    asInt(right.value['verse'])
                        .compareTo(asInt(left.value['verse'])),
              );
        if (candidates.isNotEmpty) {
          target = _keys[candidates.first.key]?.currentContext;
        }
      }
      if (target != null && target.mounted) {
        await Scrollable.ensureVisible(
          target,
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 180),
          alignment: .02,
        );
      }
      widget.cache.reference = Map<String, dynamic>.from(reference);
      widget.cache.fontScale = widget.fontScale;
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      _aligning = false;
      final pending = _nextAlignment;
      _nextAlignment = null;
      if (mounted && pending != null) unawaited(align(pending));
    }
  }

  Future<void> _load(bool previous) async {
    if (_loading || _chapters.isEmpty) return;
    final edge = previous ? _chapters.first : _chapters.last;
    final reference = asMap(
      asMap(edge['navigation'])[previous ? 'previous' : 'next'],
    );
    if (reference.isEmpty) return;
    final resourceId = widget.resource['id'];
    setState(() {
      _loading = true;
      _error = null;
    });
    final oldExtent = _scroll.hasClients
        ? _scroll.position.maxScrollExtent
        : 0.0;
    final oldOffset = _scroll.hasClients ? _scroll.offset : 0.0;
    try {
      final chapter = asMap(
        await AppScope.of(context).api.get(
          '/api/reader/${reference['book']}/${reference['chapter']}?resource=${Uri.encodeComponent(asString(widget.resource['id']))}',
        ),
      );
      if (!mounted || widget.resource['id'] != resourceId) return;
      setState(() {
        previous ? _chapters.insert(0, chapter) : _chapters.add(chapter);
      });
      if (previous) {
        await WidgetsBinding.instance.endOfFrame;
        if (mounted && _scroll.hasClients) {
          _scroll.jumpTo(
            oldOffset + _scroll.position.maxScrollExtent - oldExtent,
          );
        }
      }
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onScroll() {
    if (_scroll.hasClients) widget.cache.offset = _scroll.offset;
    if (!_userScroll || _aligning) return;
    if (_scroll.position.extentAfter < 500) _load(false);
    _needsCapture = true;
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 180), capturePosition);
  }

  bool _needsCapture = false;
  void capturePosition() {
    if (!_needsCapture) return;
    if (!mounted || _aligning) return;
    _needsCapture = false;
    final viewport = _viewport.currentContext?.findRenderObject();
    if (viewport is! RenderBox) return;
    final top = viewport.localToGlobal(Offset.zero).dy;
    Json? closest;
    var distance = double.infinity;
    for (final entry in _keys.entries) {
      final render = entry.value.currentContext?.findRenderObject();
      if (render is! RenderBox || !render.attached) continue;
      final y = render.localToGlobal(Offset.zero).dy - top;
      if (y >= -render.size.height && y.abs() < distance) {
        distance = y.abs();
        closest = _references[entry.key];
      }
    }
    if (closest != null) {
      widget.cache.reference = Map<String, dynamic>.from(closest);
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
    final key = _key(reference);
    _references[key] = reference;
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
      key: _keys.putIfAbsent(key, GlobalKey.new),
      padding: const EdgeInsets.symmetric(vertical: 6),
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 42,
                child: InkWell(
                  onTap: () => widget.onVerse(chapter, cell, reference),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      '${cell['verse']}${cell['verseEnd'] == null ? '' : '–${cell['verseEnd']}'}',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: GestureDetector(
                  onLongPress: () => widget.onVerse(chapter, cell, reference),
                  child: VerseText(
                    segments: cell['segments'] as List? ?? [],
                    fontSize: 19 * widget.fontScale,
                    highlights: highlights,
                    direction: widget.resource['direction'] == 'rtl'
                        ? TextDirection.rtl
                        : TextDirection.ltr,
                    onWord: (word, position) =>
                        widget.onWord(reference, word, position),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chapter(Json chapter) {
    final reference = asMap(chapter['reference']);
    final works = asMap(chapter['referenceResources']);
    final isBible = widget.resource['kind'] == 'bible';
    final anchoredVerses = <int>{};
    GlobalKey? entryKey(int verse) {
      if (isBible || !anchoredVerses.add(verse)) return null;
      final entryReference = {...reference, 'verse': verse};
      final key = _key(entryReference);
      _references[key] = entryReference;
      return _keys.putIfAbsent(key, GlobalKey.new);
    }

    final headingKey = '${_key(reference)}:heading';
    _references[headingKey] = reference;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          key: _keys.putIfAbsent(headingKey, GlobalKey.new),
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Text(
            asString(chapter['fullTitle']),
            style: Theme.of(context).textTheme.headlineSmall,
          ),
        ),
        if (isBible && asMap(chapter['chapter'])['empty'] == true)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Dieses Werk enthält keinen Text für dieses Kapitel.'),
          ),
        if (isBible)
          ...asMaps(asMap(chapter['chapter'])['rows'])
              .map((row) => _verse(chapter, row)),
        for (final entry in asMaps(works['commentaries']))
          Padding(
            key: entryKey(asInt(entry['verseStart'], 1)),
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextButton(
                  onPressed: () => widget.onReference({
                    ...reference,
                    if (entry['verseStart'] != null)
                      'verse': entry['verseStart'],
                  }),
                  child: Text(
                    referenceLabel({
                      ...reference,
                      if (entry['verseStart'] != null)
                        'verse': entry['verseStart'],
                    }),
                  ),
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
        for (final entry in asMaps(works['crossReferences']))
          ListTile(
            key: entryKey(asInt(entry['fromVerse'], 1)),
            contentPadding: EdgeInsets.zero,
            title: Text(
              'Vers ${entry['fromVerse']} → ${referenceLabel({'book': entry['toBook'], 'chapter': entry['toChapter'], 'verse': entry['toVerse'], if (entry['toVerseEnd'] != entry['toVerse']) 'verseEnd': entry['toVerseEnd']})}',
            ),
            onTap: () => widget.onReference({
              'book': entry['toBook'],
              'chapter': entry['toChapter'],
              'verse': entry['toVerse'],
            }),
          ),
        if (asMaps(chapter['documentAnchors']).isNotEmpty)
          ExpansionTile(
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
      ],
    );
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
          .clamp(0, _scroll.position.maxScrollExtent),
    );
    capturePosition();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Expanded(
        child: NotificationListener<ScrollStartNotification>(
          onNotification: (notification) {
            if (notification.dragDetails != null) _userScroll = true;
            return false;
          },
          child: Scrollbar(
            controller: _scroll,
            child: SingleChildScrollView(
              key: _viewport,
              controller: _scroll,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  TextButton.icon(
                    onPressed: _loading ? null : () => _load(true),
                    icon: const Icon(Icons.expand_less),
                    label: const Text('Vorheriges Kapitel'),
                  ),
                  for (final chapter in _chapters) _chapter(chapter),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(_error!),
                    ),
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
            const Text('Blättern'),
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
