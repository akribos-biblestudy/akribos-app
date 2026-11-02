import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../search/search_screen.dart';
import 'books.dart';

/// Selects only positions present in the current reader resource.
class PassagePicker extends StatefulWidget {
  const PassagePicker({
    super.key,
    required this.initial,
    required this.resourceId,
    required this.api,
    this.isLexicon = false,
  });

  final Json initial;
  final String resourceId;
  final AppApi api;
  final bool isLexicon;

  @override
  State<PassagePicker> createState() => _PassagePickerState();
}

class _PassagePickerState extends State<PassagePicker> {
  final Map<int, List<int>> _chapters = {};
  late bool _oldTestament = asInt(widget.initial['book'], 43) <= 39;
  int? _selectedBook;
  bool _loading = true;
  bool _failed = false;
  int _page = 0;
  int _generation = 0;
  static const _pageSize = 42;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _failed = false;
      _chapters.clear();
    });
    try {
      // Lexica have no chapter-navigation endpoint. Preserve their existing
      // reference picker while chapter-based resources use their actual content.
      if (widget.isLexicon) {
        _chapters.addAll({
          for (final book in bibleBooks)
            book.id: List.generate(book.chapters, (index) => index + 1),
        });
        if (mounted) setState(() => _loading = false);
        return;
      }
      final result = asMap(
        await widget.api.get(
          '/api/reader/resources/${Uri.encodeComponent(widget.resourceId)}/navigation',
        ),
      );
      final books = asMaps(result['books']);
      final available = <int, List<int>>{};
      for (final row in books) {
        final id = asInt(row['book']);
        if (id < 1 || id > bibleBooks.length) continue;
        final values = row['chapters'];
        if (values is! List) continue;
        final chapters =
            values
                .whereType<num>()
                .map((v) => v.toInt())
                .where((v) => v > 0 && v <= bibleBooks[id - 1].chapters)
                .toSet()
                .toList()
              ..sort();
        if (chapters.isNotEmpty) available[id] = chapters;
      }
      if (!mounted || generation != _generation) return;
      setState(() {
        _chapters.addAll(available);
        if (!_hasTestament(_oldTestament)) {
          _oldTestament = _hasTestament(true);
        }
        _loading = false;
      });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  bool _hasTestament(bool old) => _chapters.keys.any((id) => (id <= 39) == old);

  void _chooseBook(BibleBook book) {
    final current = asInt(widget.initial['chapter'], 1);
    final index = book.id == asInt(widget.initial['book'])
        ? _chapters[book.id]!.indexOf(current)
        : 0;
    setState(() {
      _selectedBook = book.id;
      _page = math.max(0, index) ~/ _pageSize;
    });
  }

  @override
  Widget build(BuildContext context) {
    final book = _selectedBook == null ? null : bibleBooks[_selectedBook! - 1];
    final books = bibleBooks
        .where(
          (b) => (b.id <= 39) == _oldTestament && _chapters.containsKey(b.id),
        )
        .toList();
    final chapters = book == null ? <int>[] : _chapters[book.id]!;
    final visible = chapters.skip(_page * _pageSize).take(_pageSize).toList();
    final extent = math.max(
      52.0,
      MediaQuery.textScalerOf(context).scale(20) + 24,
    );
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    return PopScope<String>(
      canPop: book == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && book != null) setState(() => _selectedBook = null);
      },
      child: Padding(
        padding: EdgeInsets.only(bottom: keyboard),
        child: SizedBox(
          height: math.max(
            0,
            MediaQuery.sizeOf(context).height * .8 - keyboard,
          ),
          child: SingleChildScrollView(
            key: ValueKey(book?.id ?? (_oldTestament ? 'at' : 'nt')),
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                SearchBox(
                  label: 'Direkte Bibelstelle, z. B. Joh 3,16',
                  onSearch: (value) => Navigator.pop(context, value),
                ),
                const SizedBox(height: 12),
                if (book == null)
                  Row(
                    children: [
                      ChoiceChip(
                        label: const Text('AT'),
                        tooltip: 'Altes Testament',
                        selected: _oldTestament,
                        onSelected: _hasTestament(true)
                            ? (_) => setState(() => _oldTestament = true)
                            : null,
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: const Text('NT'),
                        tooltip: 'Neues Testament',
                        selected: !_oldTestament,
                        onSelected: _hasTestament(false)
                            ? (_) => setState(() => _oldTestament = false)
                            : null,
                      ),
                    ],
                  )
                else
                  Row(
                    children: [
                      TextButton.icon(
                        onPressed: () => setState(() => _selectedBook = null),
                        icon: const Icon(Icons.chevron_left),
                        label: Text(book.abbreviation),
                      ),
                      const Expanded(child: Text('Kapitel wählen')),
                    ],
                  ),
                if (book != null && chapters.length > _pageSize)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        tooltip: 'Vorherige Kapitel',
                        onPressed: _page > 0
                            ? () => setState(() => _page--)
                            : null,
                        icon: const Icon(Icons.chevron_left),
                      ),
                      Text(
                        '${visible.first}–${visible.last} / ${chapters.last}',
                      ),
                      IconButton(
                        tooltip: 'Nächste Kapitel',
                        onPressed: (_page + 1) * _pageSize < chapters.length
                            ? () => setState(() => _page++)
                            : null,
                        icon: const Icon(Icons.chevron_right),
                      ),
                    ],
                  ),
                const SizedBox(height: 8),
                _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _failed
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'Die Buchauswahl konnte nicht geladen werden.',
                            ),
                            TextButton(
                              onPressed: _load,
                              child: const Text('Erneut versuchen'),
                            ),
                          ],
                        ),
                      )
                    : _chapters.isEmpty
                    ? const Center(
                        child: Text(
                          'Dieses Werk enthält keine auswählbaren Kapitel.',
                        ),
                      )
                    : GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: math.max(
                            90,
                            MediaQuery.textScalerOf(context).scale(100),
                          ),
                          mainAxisExtent: extent,
                          mainAxisSpacing: 6,
                          crossAxisSpacing: 6,
                        ),
                        itemCount: book == null ? books.length : visible.length,
                        itemBuilder: (context, index) {
                          if (book == null) {
                            final item = books[index];
                            return Tooltip(
                              message: item.name,
                              child: OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 2,
                                  ),
                                ),
                                onPressed: () => _chooseBook(item),
                                child: Semantics(
                                  label: item.name,
                                  excludeSemantics: true,
                                  child: Text(item.abbreviation),
                                ),
                              ),
                            );
                          }
                          final chapter = visible[index];
                          return OutlinedButton(
                            onPressed: () => Navigator.pop(
                              context,
                              referenceLabel({
                                'book': book.id,
                                'chapter': chapter,
                              }),
                            ),
                            child: Semantics(
                              label: '${book.name} $chapter',
                              excludeSemantics: true,
                              child: Text('$chapter'),
                            ),
                          );
                        },
                      ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
