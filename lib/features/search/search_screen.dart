import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/json.dart';
import '../../widgets/common.dart';
import '../../widgets/remote_page.dart';
import '../reader/books.dart';
import '../reader/verse_text.dart';
import 'morphology_labels.dart';

class SearchScreen extends StatelessWidget {
  const SearchScreen({super.key, required this.path});
  final String path;
  @override
  Widget build(BuildContext context) => RemotePage(
    path: path,
    builder: (context, data, reload) {
      final strong = asString(data['strong']);
      final query = asString(data['query']);
      final results = asMap(data['results']);
      final occurrences = asMap(data['occurrences']);
      final payload = strong.isNotEmpty ? occurrences : results;
      void navigate({int? page, int? book, String? gloss}) {
        final parameters = {...Uri.parse(path).queryParameters};
        if (book != null) {
          book == 0 ? parameters.remove('book') : parameters['book'] = '$book';
        }
        if (gloss != null) {
          gloss.isEmpty
              ? parameters.remove('gloss')
              : parameters['gloss'] = gloss;
        }
        final number = page ?? 1;
        String destination;
        if (strong.isEmpty) {
          parameters['page'] = '$number';
          destination = '/search';
        } else {
          destination = '/$strong${number > 1 ? '/$number' : ''}';
        }
        AppScope.of(
          context,
        ).open(Uri(path: destination, queryParameters: parameters).toString());
      }

      return ListView(
        padding: const EdgeInsets.all(20),
        children: [
          SearchBox(
            initialValue: query.isNotEmpty ? query : strong,
            onSearch: (value) => AppScope.of(context).open(
              Uri(path: '/search', queryParameters: {'q': value}).toString(),
            ),
          ),
          if (query.isEmpty && strong.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Text(
                'Suche nach Wörtern, einer Bibelstelle oder einer Strong-Nummer. Mit Anführungszeichen suchst du nach einer Wortfolge.',
              ),
            ),
          if (strong.isNotEmpty)
            StrongDetails(
              data: data,
              onGloss: (gloss) => navigate(gloss: gloss),
            ),
          if (payload.isNotEmpty) ...[
            ResultFilters(
              data: {
                ...payload,
                'book': data['book'],
                'bookCounts': data['bookCounts'] ?? payload['bookCounts'],
              },
              onBook: (book) => navigate(book: book),
            ),
            if (asString(payload['suggestion']).isNotEmpty)
              TextButton(
                onPressed: () => AppScope.of(context).open(
                  '/search?q=${Uri.encodeComponent(asString(payload['suggestion']))}',
                ),
                child: Text('Meintest du „${payload['suggestion']}“?'),
              ),
            ...asMaps(
              strong.isNotEmpty ? payload['occurrences'] : payload['hits'],
            ).map(
              (hit) => SearchHit(
                hit: hit,
                strong: strong.isEmpty ? null : strong,
                needles: (asMap(payload['query'])['highlight'] as List? ?? [])
                    .whereType<String>()
                    .toList(),
                onOpen: (reference) =>
                    AppScope.of(context).open('/${referenceLabel(reference)}'),
              ),
            ),
            if (asInt(payload['total']) == 0)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('Keine Treffer für diese Auswahl.'),
              ),
            ResultPagination(
              data: payload,
              onPage: (page) => navigate(page: page),
            ),
          ],
        ],
      );
    },
  );
}

class SearchBox extends StatefulWidget {
  const SearchBox({
    super.key,
    this.initialValue = '',
    required this.onSearch,
    this.label = 'Wort, Bibelstelle oder Strong-Nummer',
  });
  final String initialValue;
  final String label;
  final void Function(String) onSearch;
  @override
  State<SearchBox> createState() => _SearchBoxState();
}

class _SearchBoxState extends State<SearchBox> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialValue,
  );
  @override
  void didUpdateWidget(SearchBox oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialValue != widget.initialValue) {
      _controller.text = widget.initialValue;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_controller.text.trim().isNotEmpty) {
      widget.onSearch(_controller.text.trim());
    }
  }

  @override
  Widget build(BuildContext context) => TextField(
    controller: _controller,
    textInputAction: TextInputAction.search,
    onSubmitted: (_) => _submit(),
    decoration: InputDecoration(
      labelText: widget.label,
      prefixIcon: const Icon(Icons.search),
      suffixIcon: IconButton(
        tooltip: 'Suchen',
        onPressed: _submit,
        icon: const Icon(Icons.arrow_forward),
      ),
    ),
  );
}

class ResultFilters extends StatelessWidget {
  const ResultFilters({super.key, required this.data, required this.onBook});
  final Json data;
  final void Function(int) onBook;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: Wrap(
      spacing: 16,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          '${asInt(data['total'])} Treffer',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        DropdownButton<int>(
          value: asInt(data['book']),
          items: [
            const DropdownMenuItem(value: 0, child: Text('Alle Bücher')),
            ...asMaps(data['bookCounts'])
                .where(
                  (item) =>
                      asInt(item['count']) > 0 || item['book'] == data['book'],
                )
                .map(
                  (item) => DropdownMenuItem(
                    value: asInt(item['book']),
                    child: Text(
                      '${bookName(asInt(item['book']))} (${item['count']})',
                    ),
                  ),
                ),
          ],
          onChanged: (value) {
            if (value != null) onBook(value);
          },
        ),
      ],
    ),
  );
}

class ResultPagination extends StatelessWidget {
  const ResultPagination({super.key, required this.data, required this.onPage});
  final Json data;
  final void Function(int) onPage;
  @override
  Widget build(BuildContext context) {
    final page = asInt(data['page'], 1), count = asInt(data['pageCount'], 1);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          tooltip: 'Vorherige Seite',
          onPressed: page > 1 ? () => onPage(page - 1) : null,
          icon: const Icon(Icons.chevron_left),
        ),
        Text('Seite $page von $count'),
        IconButton(
          tooltip: 'Nächste Seite',
          onPressed: page < count ? () => onPage(page + 1) : null,
          icon: const Icon(Icons.chevron_right),
        ),
      ],
    );
  }
}

class SearchHit extends StatelessWidget {
  const SearchHit({
    super.key,
    required this.hit,
    required this.onOpen,
    this.strong,
    this.needles = const [],
  });
  final Json hit;
  final String? strong;
  final List<String> needles;
  final void Function(Json) onOpen;
  @override
  Widget build(BuildContext context) {
    final reference = {
      'book': hit['book'],
      'chapter': hit['chapter'],
      'verse': hit['verse'] ?? hit['verseStart'],
    };
    final cells = asMaps(hit['cells']);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextButton.icon(
              onPressed: () => onOpen(reference),
              icon: const Icon(Icons.menu_book, size: 18),
              label: Text(referenceLabel(reference)),
            ),
            if (asString(hit['title']).isNotEmpty)
              Text(
                asString(hit['title']),
                style: Theme.of(context).textTheme.titleSmall,
              ),
            if (hit['bodyHtml'] != null)
              HtmlContent(html: asString(hit['bodyHtml'])),
            if (hit['segments'] is List)
              VerseText(
                segments: hit['segments'] as List,
                studiedStrong: strong,
                needles: needles,
                onWord: (word, _) {
                  final ids = strongNumbers(word);
                  if (ids.isNotEmpty) {
                    AppScope.of(context).open('/${ids.first}');
                  }
                },
              ),
            for (final cell in cells) ...[
              if (cells.length > 1)
                Text(
                  asString(cell['resourceId']),
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              VerseText(
                segments: cell['segments'] as List? ?? [],
                studiedStrong: strong,
                needles: needles,
              ),
            ],
            if (asString(hit['morph']).isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Grammatik: ${hit['morph']}'),
              ),
          ],
        ),
      ),
    );
  }
}

class StrongDetails extends StatefulWidget {
  const StrongDetails({super.key, required this.data, this.onGloss});
  final Json data;
  final void Function(String)? onGloss;
  @override
  State<StrongDetails> createState() => _StrongDetailsState();
}

class _StrongDetailsState extends State<StrongDetails> {
  bool _german = true;
  @override
  Widget build(BuildContext context) {
    final entry = asMap(widget.data['entry']);
    final translated = asMap(entry['germanTranslation']);
    final text = _german && translated.isNotEmpty ? translated : entry;
    final statistics = asMap(widget.data['statistics']);
    final glosses = asMaps(widget.data['glosses']);
    final maxCount = glosses.fold<int>(
      1,
      (max, item) =>
          asInt(item['occurrences']) > max ? asInt(item['occurrences']) : max,
    );
    final original = asMap(widget.data['original']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Text(
          '${widget.data['strong'] ?? entry['strong'] ?? ''}  ${entry['lemma'] ?? ''}',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        if (asString(entry['transliteration']).isNotEmpty)
          Text(asString(entry['transliteration'])),
        if (asString(entry['pronunciation']).isNotEmpty)
          Text('Aussprache: ${entry['pronunciation']}'),
        if (original.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'Originalform: ${original['word'] ?? ''}  ${original['morph'] ?? ''}',
            ),
          ),
        if (widget.data['assignmentStatus'] != null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                widget.data['assignmentStatus'] == 'ambiguous'
                    ? 'Für diese Wortform gibt es mehrere Zuordnungen; mindestens eine davon ist fachlich noch nicht bestätigt.'
                    : 'Die Zuordnung dieses Wortes zur Strong-Nummer ist fachlich noch nicht bestätigt.',
              ),
            ),
          ),
        if (asMap(widget.data['morphology']).isNotEmpty)
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            initiallyExpanded: true,
            title: const Text('Grammatik'),
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  morphologyLabel(
                    asMap(widget.data['morphology'])['partOfSpeech'],
                  ),
                ),
                subtitle: Text(
                  asString(asMap(widget.data['morphology'])['code']),
                ),
              ),
              for (final feature in asMaps(
                asMap(widget.data['morphology'])['features'],
              ))
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(morphologyLabel(feature['feature'])),
                  trailing: Text(morphologyLabel(feature['value'])),
                ),
              if ((asMap(widget.data['morphology'])['unknown'] as List? ?? [])
                  .isNotEmpty)
                Text(
                  'Weitere Quellangaben: ${(asMap(widget.data['morphology'])['unknown'] as List).join(', ')}',
                ),
            ],
          ),
        if (translated.isNotEmpty)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Deutsche Übersetzung'),
            subtitle: translated['machineTranslated'] == true
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
          if (asString(text[key]).isNotEmpty)
            HtmlContent(html: asString(text[key])),
        if (entry.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('In diesem Lexikon ist kein Eintrag vorhanden.'),
          ),
        Wrap(
          spacing: 8,
          children: (entry['seeAlso'] as List? ?? [])
              .whereType<String>()
              .map(
                (id) => ActionChip(
                  label: Text(id),
                  onPressed: () => AppScope.of(context).open('/$id'),
                ),
              )
              .toList(),
        ),
        if (asString(entry['licenseHtml']).isNotEmpty)
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('Quelle und Lizenz'),
            children: [HtmlContent(html: asString(entry['licenseHtml']))],
          ),
        if (asString(entry['usageNotesHtml']).isNotEmpty)
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('Hinweise zum Lexikon'),
            children: [HtmlContent(html: asString(entry['usageNotesHtml']))],
          ),
        if (statistics.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              '${statistics['occurrences']} Vorkommen in ${statistics['verseCount']} Versen',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
        if (glosses.isNotEmpty)
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            initiallyExpanded: true,
            title: const Text('Übersetzungen und Häufigkeit'),
            children: [
              for (final gloss in glosses)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(asString(gloss['display'])),
                  subtitle: LinearProgressIndicator(
                    value: asInt(gloss['occurrences']) / maxCount,
                  ),
                  trailing: Text('${gloss['occurrences']}'),
                  onTap: widget.onGloss == null
                      ? null
                      : () => widget.onGloss!(asString(gloss['display'])),
                ),
              if (widget.onGloss != null &&
                  asString(widget.data['gloss']).isNotEmpty)
                TextButton(
                  onPressed: () => widget.onGloss!(''),
                  child: const Text('Alle Übersetzungen anzeigen'),
                ),
            ],
          ),
      ],
    );
  }
}

class TabSearchPanel extends StatefulWidget {
  const TabSearchPanel({
    super.key,
    required this.resourceId,
    required this.query,
    required this.onOpen,
  });
  final String resourceId, query;
  final void Function(Json) onOpen;
  @override
  State<TabSearchPanel> createState() => _TabSearchPanelState();
}

class _TabSearchPanelState extends State<TabSearchPanel> {
  int _page = 1, _book = 0;
  Future<dynamic>? _request;
  void _load() {
    _request = AppScope.of(context).api.get(
      Uri(
        path: '/api/reader/search',
        queryParameters: {
          'resource': widget.resourceId,
          'q': widget.query,
          'page': '$_page',
          if (_book > 0) 'book': '$_book',
        },
      ).toString(),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _request ??= _makeRequest();
  }

  Future<dynamic> _makeRequest() {
    _load();
    return _request!;
  }

  @override
  void didUpdateWidget(TabSearchPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.query != widget.query ||
        oldWidget.resourceId != widget.resourceId) {
      _page = 1;
      _book = 0;
      _load();
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<dynamic>(
    future: _request,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Center(
          child: TextButton(
            onPressed: () => setState(_load),
            child: Text('Erneut versuchen: ${snapshot.error}'),
          ),
        );
      }
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      final data = asMap(snapshot.data);
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (data['kind'] == 'unsupported')
            const Text('Dieses Werk unterstützt keine Volltextsuche.'),
          ResultFilters(
            data: data,
            onBook: (book) => setState(() {
              _book = book;
              _page = 1;
              _load();
            }),
          ),
          if (data['kind'] == 'strong') StrongDetails(data: data),
          ...asMaps(data['hits']).map(
            (hit) => SearchHit(
              hit: hit,
              onOpen: widget.onOpen,
              strong: data['kind'] == 'strong'
                  ? asString(data['strong'])
                  : null,
              needles: (data['needles'] as List? ?? [])
                  .whereType<String>()
                  .toList(),
            ),
          ),
          ResultPagination(
            data: data,
            onPage: (page) => setState(() {
              _page = page;
              _load();
            }),
          ),
        ],
      );
    },
  );
}

class LexiconStudy extends StatefulWidget {
  const LexiconStudy({
    super.key,
    required this.tab,
    required this.entry,
    required this.onOpen,
  });
  final Json tab, entry;
  final void Function(Json) onOpen;
  @override
  State<LexiconStudy> createState() => _LexiconStudyState();
}

class _LexiconStudyState extends State<LexiconStudy> {
  Future<dynamic>? _request;
  int _page = 1, _book = 0;
  void _load() {
    final strong = asString(
      widget.entry['strong'],
      asString(widget.tab['lookup']),
    );
    if (!RegExp(r'^[GH]\d+$').hasMatch(strong)) {
      _request = Future.value({'entry': widget.entry});
      return;
    }
    final study = asMap(widget.tab['studyContext']);
    _request = AppScope.of(context).api.get(
      Uri(
        path: '/api/strong/$strong',
        queryParameters: {
          'lexicon': asString(widget.tab['resourceId']),
          'page': '$_page',
          if (_book > 0) 'book': '$_book',
          if (study.isNotEmpty) ...{
            'resource': asString(study['sourceResourceId']),
            'ref': referenceLabel(asMap(study['reference'])),
            if (study['word'] != null) 'word': asString(study['word']),
            if (study['wordPosition'] != null)
              'wordPosition': '${study['wordPosition']}',
          },
        },
      ).toString(),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_request == null) _load();
  }

  @override
  void didUpdateWidget(LexiconStudy oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tab != widget.tab || oldWidget.entry != widget.entry) {
      _page = 1;
      _book = 0;
      _load();
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<dynamic>(
    future: _request,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Center(
          child: TextButton(
            onPressed: () => setState(_load),
            child: Text('Erneut versuchen: ${snapshot.error}'),
          ),
        );
      }
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      final data = asMap(snapshot.data),
          result = asMap(asMap(snapshot.data)['occurrences']);
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          StrongDetails(data: data),
          if (result.isNotEmpty) ...[
            ResultFilters(
              data: {
                ...result,
                'bookCounts': data['bookCounts'],
                'book': _book,
              },
              onBook: (book) => setState(() {
                _book = book;
                _page = 1;
                _load();
              }),
            ),
            ...asMaps(result['occurrences']).map(
              (hit) => SearchHit(
                hit: hit,
                strong: asString(data['strong']),
                onOpen: widget.onOpen,
              ),
            ),
            ResultPagination(
              data: result,
              onPage: (page) => setState(() {
                _page = page;
                _load();
              }),
            ),
          ],
        ],
      );
    },
  );
}
