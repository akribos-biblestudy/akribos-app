import 'dart:math' as math;

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderAbstractViewport;
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';

import '../../core/json.dart';
import 'books.dart';
import 'offline_lexicon_search.dart';
import 'passage_picker.dart';
import 'verse_text.dart';

/// Read-only view of packages already validated and loaded by the caller.
/// No API, persistent storage or account state is accessed here.
class OfflineReaderScreen extends StatefulWidget {
  const OfflineReaderScreen({
    super.key,
    required this.packages,
    required this.eInk,
    this.initialResourceId,
    this.initialReference,
    this.fontScale = 1,
    this.versePerLine = false,
    this.onPositionChanged,
  });

  final List<Json> packages;
  final bool eInk;
  final String? initialResourceId;
  final Json? initialReference;
  final double fontScale;
  final bool versePerLine;
  final void Function(String resourceId, Json reference)? onPositionChanged;

  @override
  State<OfflineReaderScreen> createState() => _OfflineReaderScreenState();
}

class _OfflineReaderScreenState extends State<OfflineReaderScreen> {
  final _scroll = ScrollController();
  final _viewport = GlobalKey();
  final _center = const ValueKey('offline-center');
  final _chapterKeys = <String, GlobalKey>{};
  final _groupKeys = <String, GlobalKey<VerseTextState>>{};
  final _verseKeys = <String, (GlobalKey<VerseTextState>, int)>{};
  int? _pendingVerse;
  int? _visibleVerse;
  bool _restoringVerse = false;
  String? _lastBibleId;
  String? _lastPosition;
  late List<Json> _packages;
  late Json _package;
  late List<Json> _chapters;
  int _anchor = 0;
  int _current = 0;
  bool _reportScheduled = false;
  int _navigationGeneration = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_scheduleReport);
    _setPackages(widget.initialResourceId, widget.initialReference);
  }

  @override
  void didUpdateWidget(OfflineReaderScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.packages, widget.packages)) {
      final currentRef = _chapters.isEmpty
          ? null
          : asMap(_chapters[_current]['reference']);
      _setPackages(asString(asMap(_package['resource'])['id']), currentRef);
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _setPackages(String? resourceId, Json? ref) {
    _packages = widget.packages.where((p) {
      final resource = asMap(p['resource']);
      return asString(resource['id']).isNotEmpty &&
          ((p['version'] == 1 &&
                  const [
                    'bible',
                    'commentary',
                    'xrefs',
                  ].contains(resource['kind']) &&
                  p['chapters'] is List) ||
              (p['version'] == 2 &&
                  resource['kind'] == 'lexicon' &&
                  p['entries'] is List));
    }).toList();
    _package = _packages.firstWhere(
      (p) => asMap(p['resource'])['id'] == resourceId,
      orElse: () => _packages.isEmpty ? {} : _packages.first,
    );
    if (asMap(_package['resource'])['kind'] == 'bible') {
      _lastBibleId = asString(asMap(_package['resource'])['id']);
    }
    _loadChapters(ref);
  }

  void _loadChapters(Json? ref) {
    _navigationGeneration++;
    _chapters =
        asMaps(_package['chapters']).where((chapter) {
          final r = asMap(chapter['reference']);
          return asInt(r['book']) >= 1 &&
              asInt(r['book']) <= bibleBooks.length &&
              asInt(r['chapter']) >= 1;
        }).toList()..sort((a, b) {
          final x = asMap(a['reference']), y = asMap(b['reference']);
          final result = asInt(x['book']).compareTo(asInt(y['book']));
          return result != 0
              ? result
              : asInt(x['chapter']).compareTo(asInt(y['chapter']));
        });
    final index = _chapters.indexWhere((c) {
      final r = asMap(c['reference']);
      return r['book'] == ref?['book'] && r['chapter'] == ref?['chapter'];
    });
    _anchor = _current = math.max(0, index);
    _chapterKeys.clear();
    _verseKeys.clear();
    _groupKeys.clear();
    final verse = index >= 0 ? asInt(ref?['verse']) : 0;
    _visibleVerse = verse > 0 ? verse : null;
    _pendingVerse = _visibleVerse;
    _restoringVerse = _pendingVerse != null;
  }

  void _navigate(int index) {
    if (index < 0 || index >= _chapters.length) return;
    setState(() {
      _navigationGeneration++;
      _anchor = _current = index;
      _chapterKeys.clear();
      _verseKeys.clear();
      _groupKeys.clear();
      _pendingVerse = null;
      _visibleVerse = null;
      _restoringVerse = false;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
    _emitPosition();
    _scheduleReport();
  }

  Future<void> _pickPassage() async {
    if (_chapters.isEmpty) return;
    final bounds = _restoringVerse ? null : _viewportBounds();
    final visible = bounds == null ? null : _visibleChapterIndex(bounds);
    final reference = asMap(_chapters[visible ?? _current]['reference']);
    final resourceId = asMap(_package['resource'])['id'];
    final chapters = <int, List<int>>{};
    for (final chapter in _chapters) {
      final position = asMap(chapter['reference']);
      final book = asInt(position['book']);
      final number = asInt(position['chapter']);
      final numbers = chapters.putIfAbsent(book, () => []);
      if (numbers.lastOrNull != number) numbers.add(number);
    }
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      sheetAnimationStyle: widget.eInk ? AnimationStyle.noAnimation : null,
      builder: (_) =>
          PassagePicker.local(initial: reference, chapters: chapters),
    );
    if (!mounted ||
        selected == null ||
        asMap(_package['resource'])['id'] != resourceId) {
      return;
    }
    _navigate(
      _chapters.indexWhere((chapter) {
        final position = asMap(chapter['reference']);
        final label = referenceLabel({
          'book': asInt(position['book']),
          'chapter': asInt(position['chapter']),
        });
        return label == selected;
      }),
    );
  }

  void _selectPackage(Json package) {
    final ref = _chapters.isEmpty
        ? null
        : asMap(_chapters[_current]['reference']);
    setState(() {
      _package = package;
      if (asMap(package['resource'])['kind'] == 'bible') {
        _lastBibleId = asString(asMap(package['resource'])['id']);
      }
      _loadChapters(ref);
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
    _emitPosition();
  }

  void _emitPosition() {
    if (_chapters.isEmpty) return;
    final reference = Map<String, dynamic>.from(
      asMap(_chapters[_current]['reference']),
    );
    if (_visibleVerse != null) reference['verse'] = _visibleVerse;
    final resource = asString(asMap(_package['resource'])['id']);
    final signature =
        '$resource:${reference['book']}:${reference['chapter']}:${reference['verse'] ?? 0}';
    if (_lastPosition == signature) return;
    _lastPosition = signature;
    widget.onPositionChanged?.call(resource, reference);
  }

  ({double top, double bottom})? _viewportBounds() {
    final viewport = _viewport.currentContext?.findRenderObject();
    if (viewport is! RenderBox || !viewport.attached || !viewport.hasSize) {
      return null;
    }
    final top = viewport.localToGlobal(Offset.zero).dy;
    return (top: top, bottom: top + viewport.size.height);
  }

  int? _visibleChapterIndex(({double top, double bottom}) bounds) {
    final (:top, :bottom) = bounds;
    int? best;
    var bestY = double.negativeInfinity;
    var firstBelow = double.infinity;
    for (var i = 0; i < _chapters.length; i++) {
      final ref = asMap(_chapters[i]['reference']);
      final box = _chapterKeys[_key(ref)]?.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.attached || !box.hasSize) continue;
      final y = box.localToGlobal(Offset.zero).dy;
      final end = y + box.size.height;
      if (y <= top + 1 && end > top && y > bestY) {
        best = i;
        bestY = y;
      } else if (bestY == double.negativeInfinity &&
          y >= top &&
          y < bottom &&
          y < firstBelow) {
        best = i;
        firstBelow = y;
      }
    }
    return best;
  }

  void _scheduleReport() {
    if (_reportScheduled) return;
    _reportScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _reportScheduled = false;
      if (!mounted || _restoringVerse) return;
      final bounds = _viewportBounds();
      if (bounds == null) return;
      final best = _visibleChapterIndex(bounds);
      if (best == null) return;
      if (best != _current) {
        setState(() => _current = best);
        _visibleVerse = null;
      }
      final (:top, :bottom) = bounds;
      final ref = asMap(_chapters[_current]['reference']);
      final prefix = '${_key(ref)}:';
      int? precedingVerse, nextVerse;
      var precedingY = double.negativeInfinity, nextY = double.infinity;
      for (final entry in _verseKeys.entries) {
        if (!entry.key.startsWith(prefix)) continue;
        final verse = int.tryParse(entry.key.substring(prefix.length));
        final state = entry.value.$1.currentState;
        final box = entry.value.$1.currentContext?.findRenderObject();
        if (verse == null ||
            state == null ||
            box is! RenderBox ||
            !box.attached ||
            !box.hasSize) {
          continue;
        }
        final y = box
            .localToGlobal(Offset(0, state.passageTop(entry.value.$2)))
            .dy;
        if (y <= top + 1) {
          if (y > precedingY ||
              (y == precedingY && verse < (precedingVerse ?? verse + 1))) {
            precedingY = y;
            precedingVerse = verse;
          }
        } else if (y < bottom &&
            (y < nextY || (y == nextY && verse < (nextVerse ?? verse + 1)))) {
          nextY = y;
          nextVerse = verse;
        }
      }
      _visibleVerse = precedingVerse ?? nextVerse;
      _emitPosition();
    });
  }

  String _key(Json ref) => '${ref['book']}:${ref['chapter']}';

  bool _containsVerse(Json package, Json ref) {
    final verse = asInt(ref['verse']);
    for (final chapter in asMaps(package['chapters'])) {
      final position = asMap(chapter['reference']);
      if (position['book'] != ref['book'] ||
          position['chapter'] != ref['chapter']) {
        continue;
      }
      for (final row in asMaps(asMap(chapter['chapter'])['rows'])) {
        for (final cell in asMaps(row['cells'])) {
          final start = asInt(cell['verse']);
          final end = asInt(cell['verseEnd'], start);
          if (start > 0 && verse >= start && verse <= end) return true;
        }
      }
    }
    return false;
  }

  Future<void> _openCrossReference(Json ref) async {
    final bibles = _packages
        .where((p) => asMap(p['resource'])['kind'] == 'bible')
        .toList();
    var selected = bibles
        .where((p) => asMap(p['resource'])['id'] == _lastBibleId)
        .firstOrNull;
    if (selected == null && bibles.length == 1) selected = bibles.single;
    if (selected == null && bibles.length > 1) {
      selected = await showDialog<Json>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('Bibel für die Parallelstelle auswählen'),
          children: [
            for (final bible in bibles)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, bible),
                child: Text(asString(asMap(bible['resource'])['name'])),
              ),
          ],
        ),
      );
      if (!mounted || selected == null) return;
    }
    if (selected == null || !_containsVerse(selected, ref)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Dieser Vers ist in der gewählten Bibel offline nicht verfügbar.',
          ),
        ),
      );
      return;
    }
    setState(() {
      _package = selected!;
      _lastBibleId = asString(asMap(selected['resource'])['id']);
      _loadChapters(ref);
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
    _emitPosition();
  }

  String? _assignmentWarning(
    List<dynamic> segments,
    int position,
    String strong,
  ) {
    int? precedingPosition;
    for (final run in verseRuns(segments, studiedStrong: strong)) {
      if (run.word != null) precedingPosition = run.position;
      if (run.assignment && precedingPosition == position) return run.note;
    }
    return null;
  }

  void _openStrong(Json word, int position, List<dynamic> segments) {
    final choices = <(Json, String)>[];
    for (final strong in strongNumbers(word)) {
      for (final package in _packages) {
        if (asMap(package['resource'])['kind'] == 'lexicon' &&
            asMaps(package['entries'])
                .any((entry) => entry['strong'] == strong)) {
          choices.add((package, strong));
        }
      }
    }
    if (choices.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Für dieses Wort ist kein Offline-Lexikoneintrag gespeichert.',
          ),
        ),
      );
      return;
    }
    var selected = 0;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => FractionallySizedBox(
        heightFactor: .85,
        child: StatefulBuilder(
          builder: (context, setSheetState) {
            final choice = choices[selected];
            final resource = asMap(choice.$1['resource']);
            return SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                    child: DropdownButtonFormField<int>(
                      initialValue: selected,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Lexikon und Strong-Nummer',
                      ),
                      items: [
                        for (var i = 0; i < choices.length; i++)
                          DropdownMenuItem(
                            value: i,
                            child: Text(
                              '${asString(asMap(choices[i].$1['resource'])['name'])} · ${choices[i].$2}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setSheetState(() => selected = value);
                        }
                      },
                    ),
                  ),
                  Expanded(
                    child: _OfflineLexicon(
                      key: ValueKey('${resource['id']}:${choice.$2}'),
                      entries: choice.$1['entries'] as List,
                      scale: widget.fontScale.clamp(.7, 2),
                      initialStrong: choice.$2,
                      assignmentWarning: _assignmentWarning(
                        segments,
                        position,
                        choice.$2,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  void _seekVerseAfterLayout(Json reference) {
    if (_pendingVerse == null || _pendingVerse! < 1) return;
    final verse = _pendingVerse!;
    final generation = _navigationGeneration;
    _pendingVerse = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !_scroll.hasClients ||
          generation != _navigationGeneration) {
        return;
      }
      final target = _verseKeys['${_key(reference)}:$verse'];
      final state = target?.$1.currentState;
      final render = target?.$1.currentContext?.findRenderObject();
      if (target == null || state == null || render == null) {
        _restoringVerse = false;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Dieser Vers ist offline nicht verfügbar.'),
          ),
        );
        return;
      }
      final viewport = RenderAbstractViewport.of(render);
      final offset =
          viewport.getOffsetToReveal(render, 0).offset +
          state.passageTop(target.$2);
      _scroll.jumpTo(
        offset.clamp(
          _scroll.position.minScrollExtent,
          _scroll.position.maxScrollExtent,
        ),
      );
      _restoringVerse = false;
      _scheduleReport();
    });
  }

  @override
  Widget build(BuildContext context) {
    final resource = asMap(_package['resource']);
    final current = _chapters.isEmpty
        ? null
        : asMap(_chapters[_current]['reference']);
    final reference = current == null
        ? null
        : {
            'book': asInt(current['book']),
            'chapter': asInt(current['chapter']),
          };
    final scaler = widget.fontScale.clamp(.7, 2.0);
    final colors = widget.eInk
        ? const ColorScheme.light(
            primary: Colors.black,
            onSurface: Colors.black,
            surface: Colors.white,
          )
        : Theme.of(context).colorScheme;
    return Theme(
      data: Theme.of(context).copyWith(
        colorScheme: colors,
        scaffoldBackgroundColor: widget.eInk ? Colors.white : null,
      ),
      child: Scaffold(
        appBar: AppBar(title: const Text('Offline lesen')),
        body: _packages.isEmpty
            ? const Center(child: Text('Keine Offline-Werke verfügbar.'))
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Column(
                      children: [
                        DropdownButtonFormField<String>(
                          key: ValueKey(asString(resource['id'])),
                          initialValue: asString(resource['id']),
                          isExpanded: true,
                          decoration: const InputDecoration(labelText: 'Werk'),
                          items: [
                            for (final p in _packages)
                              DropdownMenuItem(
                                value: asString(asMap(p['resource'])['id']),
                                child: Text(
                                  asString(asMap(p['resource'])['name']),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                          onChanged: (id) => _selectPackage(
                            _packages.firstWhere(
                              (p) => asMap(p['resource'])['id'] == id,
                            ),
                          ),
                        ),
                        if (reference != null)
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: _pickPassage,
                              icon: const Icon(Icons.menu_book_outlined),
                              label: Text(
                                'Buch und Kapitel · ${referenceLabel(reference)}',
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (widget.eInk)
                    const SizedBox(
                      height: 2,
                      width: double.infinity,
                      child: ColoredBox(color: Colors.black),
                    ),
                  Expanded(
                    child: resource['kind'] == 'lexicon'
                        ? _OfflineLexicon(
                            key: ValueKey(resource['id']),
                            entries: _package['entries'] as List,
                            scale: scaler,
                          )
                        : _chapters.isEmpty
                        ? const Center(
                            child: Text(
                              'Dieses Werk enthält keine Offline-Kapitel.',
                            ),
                          )
                        : CustomScrollView(
                            key: _viewport,
                            controller: _scroll,
                            center: _center,
                            slivers: [
                              SliverList.builder(
                                itemCount: _anchor,
                                itemBuilder: (context, i) => _buildChapter(
                                  _anchor - i - 1,
                                  resource,
                                  scaler,
                                ),
                              ),
                              SliverList.builder(
                                key: _center,
                                itemCount: _chapters.length - _anchor,
                                itemBuilder: (context, i) => _buildChapter(
                                  _anchor + i,
                                  resource,
                                  scaler,
                                ),
                              ),
                            ],
                          ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildChapter(int index, Json resource, double scale) {
    final chapter = _chapters[index];
    final ref = asMap(chapter['reference']);
    final rows = asMaps(asMap(chapter['chapter'])['rows']);
    final works = asMap(chapter['referenceResources']);
    final bodyStyle = TextStyle(
      fontFamily: 'AkribosText',
      fontFamilyFallback: const ['NotoSansHebrew'],
      fontSize: 19 * scale,
      height: 1.65,
    );
    final groups = <List<Json>>[];
    if (resource['kind'] == 'bible') {
      for (final row in rows) {
        final cells = row['cells'];
        if (cells is! List || cells.isEmpty || cells.first == null) continue;
        final cell = asMap(cells.first);
        if (widget.versePerLine ||
            groups.isEmpty ||
            verseHasSourceLineBreak(cell['segments']) ||
            verseHasSourceLineBreak(groups.last.last['segments']) ||
            asString(cell['heading']).isNotEmpty) {
          groups.add([]);
        }
        groups.last.add(cell);
      }
    }
    final groupKeys = <GlobalKey<VerseTextState>>[];
    for (final group in groups) {
      final key = _groupKeys.putIfAbsent(
        '${_key(ref)}:${group.first['verse']}',
        GlobalKey<VerseTextState>.new,
      );
      groupKeys.add(key);
      for (var i = 0; i < group.length; i++) {
        final start = asInt(group[i]['verse']);
        final end = asInt(group[i]['verseEnd'], start);
        for (var verse = start; verse <= end && verse <= start + 200; verse++) {
          _verseKeys['${_key(ref)}:$verse'] = (key, i);
        }
      }
    }
    if (index == _anchor) _seekVerseAfterLayout(ref);
    return Padding(
      key: _chapterKeys.putIfAbsent(_key(ref), GlobalKey.new),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            asString(chapter['fullTitle'], referenceLabel(ref)),
            style: bodyStyle.copyWith(
              fontSize: 19 * scale * 1.4,
              fontWeight: FontWeight.bold,
            ),
          ),
          for (final (groupIndex, group) in groups.indexed) ...[
            if (asString(group.first['heading']).isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  asString(group.first['heading']),
                  style: bodyStyle.copyWith(
                    fontSize: 19 * scale * 1.2,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            VerseText(
              key: groupKeys[groupIndex],
              segments: group.first['segments'] is List
                  ? group.first['segments'] as List
                  : [],
              passages:
                  widget.versePerLine ||
                      verseHasSourceLineBreak(group.first['segments'])
                  ? null
                  : [
                      for (final cell in group)
                        VersePassage(
                          segments: cell['segments'] is List
                              ? cell['segments'] as List
                              : [],
                          number:
                              '${cell['verse']}${cell['verseEnd'] == null ? '' : '–${cell['verseEnd']}'}',
                          onWord: (word, position) => _openStrong(
                            word,
                            position,
                            cell['segments'] is List
                                ? cell['segments'] as List
                                : [],
                          ),
                        ),
                    ],
              verseNumber:
                  '${group.first['verse']}${group.first['verseEnd'] == null ? '' : '–${group.first['verseEnd']}'}',
              onWord: (word, position) => _openStrong(
                word,
                position,
                group.first['segments'] is List
                    ? group.first['segments'] as List
                    : [],
              ),
              fontSize: 19 * scale,
              direction: resource['direction'] == 'rtl'
                  ? TextDirection.rtl
                  : TextDirection.ltr,
            ),
          ],
          for (final entry in asMaps(works['commentaries']))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (entry['verseStart'] != null)
                    Text(
                      referenceLabel({
                        ...ref,
                        'verse': entry['verseStart'],
                        if (entry['verseEnd'] != null)
                          'verseEnd': entry['verseEnd'],
                      }),
                    ),
                  if (asString(entry['title']).isNotEmpty)
                    Text(
                      asString(entry['title']),
                      style: bodyStyle.copyWith(
                        fontSize: 19 * scale * 1.2,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  HtmlWidget(
                    asString(entry['bodyHtml']),
                    textStyle: bodyStyle,
                    factoryBuilder: _OfflineHtmlFactory.new,
                    onTapUrl: (_) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Dieser Link ist offline nicht verfügbar.',
                          ),
                        ),
                      );
                      return true;
                    },
                  ),
                ],
              ),
            ),
          for (final entry in asMaps(works['crossReferences']))
            Builder(
              builder: (context) {
                final target = {
                  'book': entry['toBook'],
                  'chapter': entry['toChapter'],
                  'verse': entry['toVerse'],
                  if (entry['toVerseEnd'] != null &&
                      entry['toVerseEnd'] != entry['toVerse'])
                    'verseEnd': entry['toVerseEnd'],
                };
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    'Vers ${entry['fromVerse']} → ${referenceLabel(target)}',
                  ),
                  onTap: () => _openCrossReference(target),
                );
              },
            ),
        ],
      ),
    );
  }
}

class _OfflineLexicon extends StatefulWidget {
  const _OfflineLexicon({
    super.key,
    required this.entries,
    required this.scale,
    this.initialStrong,
    this.assignmentWarning,
  });
  final List<dynamic> entries;
  final double scale;
  final String? initialStrong;
  final String? assignmentWarning;
  @override
  State<_OfflineLexicon> createState() => _OfflineLexiconState();
}

class _OfflineLexiconState extends State<_OfflineLexicon> {
  final _query = TextEditingController();
  Future<List<String>>? _index;
  late List<Json> _entries;
  Json? _selected;
  bool _german = true;

  @override
  void initState() {
    super.initState();
    _entries = asMaps(widget.entries);
    if (widget.initialStrong != null) {
      _query.text = widget.initialStrong!;
      _selected = _entries
          .where((entry) => entry['strong'] == widget.initialStrong)
          .firstOrNull;
    }
  }

  @override
  void didUpdateWidget(_OfflineLexicon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.entries, widget.entries)) {
      final strong = _selected?['strong'];
      _entries = asMaps(widget.entries);
      _index = null;
      _selected = _entries
          .where((entry) => entry['strong'] == strong)
          .firstOrNull;
    }
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final search = _query.text.trim();
    final strong = normalizeOfflineStrongId(search);
    final selected = _selected;
    final bodyStyle = TextStyle(
      fontFamily: 'AkribosText',
      fontFamilyFallback: const ['NotoSansHebrew'],
      fontSize: 19 * widget.scale,
      height: 1.65,
    );
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: TextField(
            controller: _query,
            decoration: const InputDecoration(
              labelText: 'Lexikon durchsuchen',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (_) => setState(() => _selected = null),
          ),
        ),
        if (selected != null)
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => setState(() => _selected = null),
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('Zur Trefferliste'),
                  ),
                ),
                Text(
                  '${asString(selected['strong'])} · ${asString(selected['lemma'])}',
                  style: bodyStyle.copyWith(fontWeight: FontWeight.bold),
                ),
                if (widget.assignmentWarning != null &&
                    selected['strong'] == widget.initialStrong)
                  Text(widget.assignmentWarning!, style: bodyStyle),
                if (asString(selected['transliteration']).isNotEmpty)
                  Text(asString(selected['transliteration']), style: bodyStyle),
                if (asString(selected['pronunciation']).isNotEmpty)
                  Text(asString(selected['pronunciation']), style: bodyStyle),
                if (asMap(selected['germanTranslation']).isNotEmpty)
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Deutsche Übersetzung'),
                    subtitle:
                        asMap(
                              selected['germanTranslation'],
                            )['machineTranslated'] ==
                            true
                        ? const Text('Maschinell übersetzter Lexikonartikel')
                        : null,
                    value: _german,
                    onChanged: (value) => setState(() => _german = value),
                  ),
                for (final key in [
                  'definitionHtml',
                  'derivationHtml',
                  'kjvDefinitionHtml',
                ])
                  if (asString(
                    (_german && asMap(selected['germanTranslation']).isNotEmpty
                        ? asMap(selected['germanTranslation'])
                        : selected)[key],
                  ).isNotEmpty)
                    HtmlWidget(
                      asString(
                        (_german &&
                                asMap(selected['germanTranslation']).isNotEmpty
                            ? asMap(selected['germanTranslation'])
                            : selected)[key],
                      ),
                      textStyle: bodyStyle,
                      factoryBuilder: _OfflineHtmlFactory.new,
                      onTapUrl: (_) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Dieser Link ist offline nicht verfügbar.',
                            ),
                          ),
                        );
                        return true;
                      },
                    ),
                if (selected['seeAlso'] is List &&
                    (selected['seeAlso'] as List).isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text('Siehe auch'),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final reference
                          in (selected['seeAlso'] as List).whereType<String>())
                        ActionChip(
                          label: Text(reference),
                          onPressed: () => setState(() {
                            _query.text = reference;
                            _selected = null;
                          }),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          )
        else if (search.isEmpty)
          _results(_entries)
        else if (strong != null)
          _results(
            _entries.where((entry) => entry['strong'] == strong).toList(),
          )
        else
          FutureBuilder<List<String>>(
            future: _index ??= compute(
              buildOfflineLexiconSearchIndex,
              _entries,
            ),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Expanded(
                  child: Center(
                    child: TextButton(
                      onPressed: () => setState(() => _index = null),
                      child: const Text('Lexikonsuche erneut versuchen'),
                    ),
                  ),
                );
              }
              if (!snapshot.hasData) {
                return const Expanded(
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final normalized = normalizeOfflineLexiconText(search);
              final index = snapshot.data!;
              return _results([
                for (var i = 0; i < _entries.length; i++)
                  if (index[i].contains(normalized)) _entries[i],
              ]);
            },
          ),
      ],
    );
  }

  Widget _results(List<Json> matches) => Expanded(
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              matches.length > 100
                  ? '${matches.length} Treffer · erste 100 angezeigt'
                  : '${matches.length} Treffer',
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: matches.length > 100 ? 100 : matches.length,
            itemBuilder: (context, index) {
              final entry = matches[index];
              return ListTile(
                title: Text(
                  '${asString(entry['strong'])} · ${asString(entry['lemma'])}',
                ),
                subtitle: asString(entry['transliteration']).isEmpty
                    ? null
                    : Text(asString(entry['transliteration'])),
                onTap: () => setState(() {
                  _selected = entry;
                  _german = true;
                }),
              );
            },
          ),
        ),
      ],
    ),
  );
}

/// Never fetch or open remote media while displaying a saved package.
class _OfflineHtmlFactory extends WidgetFactory {
  @override
  Widget? buildImage(BuildTree tree, ImageMetadata data) => null;
  @override
  ImageProvider? imageProviderFromNetwork(String url) => null;
  @override
  ImageProvider? imageProviderFromFileUri(String url) => null;
  @override
  ImageProvider? imageProviderFromDataUri(String url) => null;
  @override
  ImageProvider? imageProviderFromAsset(String url) => null;
}
