import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../theme/akribos_theme.dart';
import '../search/search_screen.dart';
import 'books.dart';

/// Selects only positions present in the current reader resource.
class PassagePicker extends StatefulWidget {
  const PassagePicker({
    super.key,
    required this.initial,
    required String this.resourceId,
    required AppApi this.api,
    this.isLexicon = false,
  }) : _localChapters = null;

  /// Uses chapter keys from the downloaded resource without a network request.
  const PassagePicker.local({
    super.key,
    required this.initial,
    required Map<int, List<int>> chapters,
  }) : _localChapters = chapters,
       resourceId = null,
       api = null,
       isLexicon = false;

  final Json initial;
  final String? resourceId;
  final AppApi? api;
  final Map<int, List<int>>? _localChapters;
  final bool isLexicon;

  @override
  State<PassagePicker> createState() => _PassagePickerState();
}

enum _BookCategory {
  law('Bücher Mose', 1, 5, 0xff875419, 0xffe4b869),
  history('Geschichtsbücher', 6, 17, 0xff366949, 0xff90c49c),
  poetry('Poesie und Weisheit', 18, 22, 0xff745487, 0xffcdaddc),
  prophets('Propheten', 23, 39, 0xff355d8f, 0xff9fbee7),
  gospels('Evangelien', 40, 43, 0xff276d73, 0xff8cc9ca),
  acts('Apostelgeschichte', 44, 44, 0xff875236, 0xffdba17e),
  letters('Briefe', 45, 65, 0xff8b4652, 0xffdca0aa),
  revelation('Offenbarung', 66, 66, 0xff626335, 0xffc8c388);

  const _BookCategory(this.label, this.first, this.last, this.light, this.dark);

  final String label;
  final int first;
  final int last;
  final int light;
  final int dark;

  bool contains(BibleBook book) => first <= book.id && book.id <= last;
}

class _PassagePickerState extends State<PassagePicker> {
  final _sheetScroll = ScrollController(keepScrollOffset: false);
  final _bookScroll = ScrollController(keepScrollOffset: false);
  final _chapterScroll = ScrollController(keepScrollOffset: false);
  final _bookViewport = GlobalKey();
  final _selectedBookAnchor = GlobalKey();
  Map<int, List<int>> _chapters = {};
  int get _currentBook => asInt(widget.initial['book'], 43);
  int get _currentChapter => asInt(widget.initial['chapter'], 1);
  late bool _oldTestament = _currentBook <= 39;
  int? _selectedBook;
  bool _loading = true;
  bool _failed = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _sheetScroll.dispose();
    _bookScroll.dispose();
    _chapterScroll.dispose();
    super.dispose();
  }

  Future<Map<int, Iterable<num>>> _fetchChapters() async {
    final resource = Uri.encodeComponent(widget.resourceId!);
    final result = asMap(
      await widget.api!.get('/api/reader/resources/$resource/navigation'),
    );
    return {
      for (final row in asMaps(result['books']))
        if (row['chapters'] case final List<dynamic> values)
          asInt(row['book']): values.whereType<num>(),
    };
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      // Lexica have no chapter-navigation endpoint. Keep their reference picker.
      final supplied =
          widget._localChapters ??
          (widget.isLexicon
              ? {
                  for (final book in bibleBooks)
                    book.id: List.generate(book.chapters, (index) => index + 1),
                }
              : await _fetchChapters());
      if (!mounted || generation != _generation) return;
      final available = <int, List<int>>{};
      for (final book in bibleBooks) {
        final numbers = supplied[book.id];
        if (numbers == null) continue;
        final valid =
            numbers
                .map((number) => number.toInt())
                .where(
                  (number) =>
                      number > 0 &&
                      (widget._localChapters != null ||
                          number <= book.chapters),
                )
                .toSet()
                .toList()
              ..sort();
        if (valid.isNotEmpty) available[book.id] = valid;
      }
      setState(() {
        _chapters = available;
        if (!_hasTestament(_oldTestament)) {
          _oldTestament = _hasTestament(true);
        }
        _selectedBook = _firstBookFor(_oldTestament);
        _loading = false;
      });
      _positionSelection(centerBook: true, revealPanes: true);
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  bool _hasTestament(bool old) => _chapters.keys.any((id) => (id <= 39) == old);

  int? _firstBookFor(bool old) {
    if ((_currentBook <= 39) == old && _chapters.containsKey(_currentBook)) {
      return _currentBook;
    }
    // Navigation entries were inserted in canonical order.
    return _chapters.keys.where((id) => (id <= 39) == old).firstOrNull;
  }

  void _chooseTestament(bool old) {
    if (_oldTestament == old) return;
    setState(() {
      _oldTestament = old;
      _selectedBook = _firstBookFor(old);
    });
    _positionSelection(centerBook: true);
  }

  void _chooseBook(int book) {
    if (_selectedBook == book) return;
    setState(() => _selectedBook = book);
    _positionSelection();
  }

  double _chapterExtent(BuildContext context) =>
      math.max(52, MediaQuery.textScalerOf(context).scale(16) * 1.35 + 20);

  void _positionSelection({bool centerBook = false, bool revealPanes = false}) {
    final book = _selectedBook;
    if (book == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _selectedBook != book) return;
      final target = _selectedBookAnchor.currentContext?.findRenderObject();
      if (centerBook && target != null && _bookScroll.hasClients) {
        unawaited(_bookScroll.position.ensureVisible(target, alignment: .5));
      }
      if (!_chapterScroll.hasClients) return;
      // Padding in the chapter pane gives the first and last entries a full
      // midpoint as well. A different book starts at its first available entry.
      final chapters = _chapters[book]!;
      var index = 0;
      if (book == _currentBook) {
        index = chapters.indexWhere((chapter) => chapter >= _currentChapter);
        if (index < 0) index = chapters.length - 1;
      }
      final position = _chapterScroll.position;
      final extent = _chapterExtent(context);
      final offset =
          index * extent +
          math.max(0.0, (extent - position.viewportDimension) / 2);
      _chapterScroll.jumpTo(offset.clamp(0.0, position.maxScrollExtent));
      // With the keyboard or a very short window, the sheet itself may scroll.
      // Reveal the centered rows on opening. Later gestures control that scroll.
      final viewport = _bookViewport.currentContext?.findRenderObject();
      if (revealPanes &&
          viewport != null &&
          _sheetScroll.hasClients &&
          _sheetScroll.position.maxScrollExtent > 0) {
        unawaited(_sheetScroll.position.ensureVisible(viewport, alignment: .5));
      }
    });
  }

  String _displayName(BibleBook book) => book.name.replaceFirst('.', '. ');

  Widget _bookRow(
    BibleBook book,
    Color marker,
    AkribosThemeTokens tokens,
    ThemeData theme,
  ) {
    final id = book.id;
    final selected = _selectedBook == id;
    final surface = theme.colorScheme.surface;
    final background = selected
        ? tokens.accentSoft
        : tokens.eInk
        ? surface
        : Color.alphaBlend(marker.withValues(alpha: .09), surface);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(8),
      side: selected
          ? BorderSide(color: tokens.accent, width: tokens.eInk ? 2 : 1.5)
          : BorderSide.none,
    );
    final row = Semantics(
      key: ValueKey('passage-book-$id'),
      selected: selected,
      child: Material(
        color: background,
        shape: shape,
        child: InkWell(
          customBorder: shape,
          onTap: () => _chooseBook(book.id),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 52),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
              child: Row(
                children: [
                  if (!tokens.eInk) ...[
                    Container(
                      width: 3,
                      height: 18,
                      decoration: BoxDecoration(
                        color: marker,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 7),
                  ],
                  Expanded(
                    child: Text(
                      _displayName(book),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: selected
          ? KeyedSubtree(key: _selectedBookAnchor, child: row)
          : row,
    );
  }

  Widget _bookPane(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = AkribosThemeTokens.of(context);
    final books = bibleBooks
        .where(
          (book) =>
              (book.id <= 39) == _oldTestament &&
              _chapters.containsKey(book.id),
        )
        .toList();
    final rows = <Widget>[];
    for (final category in _BookCategory.values) {
      final members = books.where(category.contains).toList();
      if (members.isEmpty) continue;
      final marker = Color(
        theme.brightness == Brightness.dark ? category.dark : category.light,
      );
      rows.add(
        Semantics(
          header: true,
          child: Padding(
            padding: EdgeInsets.only(
              top: rows.isEmpty ? 0 : 10,
              bottom: 5,
              left: 4,
            ),
            child: Text(
              category.label,
              style: theme.textTheme.labelMedium?.copyWith(color: tokens.muted),
            ),
          ),
        ),
      );
      rows.addAll(members.map((book) => _bookRow(book, marker, tokens, theme)));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _paneHeading(context, 'Buch'),
        Expanded(
          child: LayoutBuilder(
            key: _bookViewport,
            builder: (context, constraints) => Scrollbar(
              controller: _bookScroll,
              thumbVisibility: true,
              child: SingleChildScrollView(
                key: const ValueKey('passage-books-scroll'),
                controller: _bookScroll,
                padding: EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: math.max(0, (constraints.maxHeight - 56) / 2),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: rows,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _paneHeading(BuildContext context, String text) => Semantics(
    header: true,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 5),
      child: Text(text, style: Theme.of(context).textTheme.labelLarge),
    ),
  );

  Widget _chapterPane(
    BuildContext context,
    BibleBook book, {
    required bool compact,
  }) {
    final theme = Theme.of(context);
    final tokens = AkribosThemeTokens.of(context);
    final chapters = _chapters[book.id]!;
    final extent = _chapterExtent(context);
    final name = _displayName(book);
    final count = chapters.length;
    final dividerThickness = tokens.eInk ? 2.0 : 1.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _paneHeading(context, 'Kapitel'),
        if (!compact)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 10, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: theme.textTheme.titleLarge),
                Text('$count Kapitel', style: theme.textTheme.bodySmall),
                const SizedBox(height: 8),
                Divider(
                  height: dividerThickness,
                  thickness: dividerThickness,
                  color: tokens.eInk
                      ? tokens.line
                      : tokens.muted.withValues(alpha: .35),
                ),
              ],
            ),
          ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) => Scrollbar(
              controller: _chapterScroll,
              thumbVisibility: true,
              child: ListView.builder(
                key: const ValueKey('passage-chapters-scroll'),
                controller: _chapterScroll,
                itemExtent: extent,
                padding: EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: book.id == _currentBook
                      ? math.max(0, (constraints.maxHeight - extent) / 2)
                      : 0,
                ),
                itemCount: count,
                itemBuilder: (context, index) {
                  final chapter = chapters[index];
                  final current =
                      book.id == _currentBook && chapter == _currentChapter;
                  final shape = RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(
                      color: current ? tokens.accent : tokens.line,
                      width: current && tokens.eInk ? 2 : 1,
                    ),
                  );
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Semantics(
                      key: ValueKey('passage-chapter-$chapter'),
                      label: '$name $chapter',
                      selected: current,
                      excludeSemantics: true,
                      button: true,
                      onTap: () => _openChapter(book, chapter),
                      child: Material(
                        color: current
                            ? tokens.accentSoft
                            : theme.colorScheme.surface,
                        shape: shape,
                        child: InkWell(
                          customBorder: shape,
                          onTap: () => _openChapter(book, chapter),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 11),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '$chapter',
                                    style: theme.textTheme.bodyLarge?.copyWith(
                                      fontWeight: current
                                          ? FontWeight.w700
                                          : FontWeight.w500,
                                    ),
                                  ),
                                ),
                                if (!compact)
                                  Icon(
                                    current ? Icons.check : Icons.chevron_right,
                                    size: 19,
                                    color: current
                                        ? tokens.accent
                                        : tokens.muted,
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _openChapter(BibleBook book, int chapter) => Navigator.pop(
    context,
    referenceLabel({'book': book.id, 'chapter': chapter}),
  );

  Widget _controls(
    BuildContext context, {
    required bool shortLabels,
    required bool shortLayout,
  }) {
    final theme = Theme.of(context);
    final search = widget._localChapters == null
        ? SearchBox(
            label: shortLabels || shortLayout
                ? 'Bibelstelle'
                : 'Direkte Bibelstelle, z. B. Joh 3,16',
            onSearch: (value) => Navigator.pop(context, value),
          )
        : null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: shortLayout && search != null
                    ? search
                    : Semantics(
                        header: true,
                        child: Text(
                          'Buch und Kapitel',
                          style: theme.textTheme.headlineSmall,
                        ),
                      ),
              ),
              IconButton(
                tooltip: 'Schließen',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          if (!shortLayout && search != null) search,
          if (search != null) const SizedBox(height: 8),
          Row(
            children: [
              for (final old in [true, false]) ...[
                if (!old) const SizedBox(width: 6),
                Expanded(
                  child: ChoiceChip(
                    materialTapTargetSize: MaterialTapTargetSize.padded,
                    label: Semantics(
                      label: old ? 'Altes Testament' : 'Neues Testament',
                      excludeSemantics: true,
                      child: Text(
                        shortLabels
                            ? (old ? 'AT' : 'NT')
                            : (old ? 'Altes Testament' : 'Neues Testament'),
                      ),
                    ),
                    selected: _oldTestament == old,
                    onSelected: _hasTestament(old)
                        ? (_) => _chooseTestament(old)
                        : null,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _panes(
    BuildContext context,
    BibleBook book, {
    required bool shortLayout,
  }) {
    final tokens = AkribosThemeTokens.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: tokens.line, width: tokens.eInk ? 2 : 1),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final largeText = MediaQuery.textScalerOf(context).scale(16) > 22;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                key: const ValueKey('passage-books-pane'),
                flex: 3,
                child: ColoredBox(
                  color: tokens.paper,
                  child: _bookPane(context),
                ),
              ),
              VerticalDivider(
                width: tokens.eInk ? 2 : 1,
                thickness: tokens.eInk ? 2 : 1,
                color: tokens.line,
              ),
              Expanded(
                key: const ValueKey('passage-chapters-pane'),
                flex: 2,
                child: _chapterPane(
                  context,
                  book,
                  compact:
                      shortLayout || (largeText && constraints.maxWidth < 500),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final scaled = MediaQuery.textScalerOf(context).scale(16);
    final shortLayout = screen.height < math.max(500, 330 + scaled * 5);
    final selected = _selectedBook;
    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: SizedBox(
        height: math.max(0, screen.height * (shortLayout ? 1 : .8) - keyboard),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final controls = _controls(
              context,
              shortLabels: constraints.maxWidth < scaled * 19,
              shortLayout: shortLayout,
            );
            if (_loading || _failed || selected == null) {
              return SingleChildScrollView(
                child: Column(
                  children: [
                    controls,
                    if (_loading)
                      const Padding(
                        padding: EdgeInsets.all(18),
                        child: CircularProgressIndicator(),
                      )
                    else if (_failed)
                      Column(
                        children: [
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 14),
                            child: Text(
                              'Die Buchauswahl konnte nicht geladen werden.',
                            ),
                          ),
                          TextButton(
                            onPressed: _load,
                            child: const Text('Erneut versuchen'),
                          ),
                        ],
                      )
                    else
                      const Padding(
                        padding: EdgeInsets.all(14),
                        child: Text(
                          'Dieses Werk enthält keine auswählbaren Kapitel.',
                        ),
                      ),
                  ],
                ),
              );
            }
            final minHeight = shortLayout ? 132 + scaled * 4 : 202 + scaled * 9;
            return SingleChildScrollView(
              key: const ValueKey('passage-viewport'),
              controller: _sheetScroll,
              physics: constraints.maxHeight >= minHeight
                  ? const NeverScrollableScrollPhysics()
                  : null,
              child: SizedBox(
                height: math.max(constraints.maxHeight, minHeight),
                child: Column(
                  children: [
                    controls,
                    Expanded(
                      child: _panes(
                        context,
                        bibleBooks[selected - 1],
                        shortLayout: shortLayout,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
