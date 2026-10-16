import 'package:flutter/material.dart';

import '../../core/json.dart';
import 'verse_text.dart';

class HighlightDialog extends StatefulWidget {
  const HighlightDialog({
    super.key,
    required this.chapter,
    required this.cell,
    required this.styles,
  });
  final Json chapter, cell;
  final List<Json> styles;
  @override
  State<HighlightDialog> createState() => _HighlightDialogState();
}

class _HighlightDialogState extends State<HighlightDialog> {
  late int _endVerse = asInt(widget.cell['verse']);
  int _start = 0;
  late int _end = _count(widget.cell) - 1;
  late String? _style = widget.styles.firstOrNull?['id'] as String?;
  int _count(Json cell) => verseRuns(cell['segments'] as List? ?? []).fold<int>(
    0,
    (count, run) => run.wordIndex != null && run.wordIndex! + 1 > count
        ? run.wordIndex! + 1
        : count,
  );
  List<Json> get _verses => asMaps(asMap(widget.chapter['chapter'])['rows'])
      .expand((row) => asMaps(row['cells']))
      .where(
        (cell) =>
            asInt(cell['verse']) >= asInt(widget.cell['verse']) &&
            _count(cell) > 0,
      )
      .toList();
  @override
  Widget build(BuildContext context) {
    final last = _verses.firstWhere(
      (cell) => cell['verse'] == _endVerse,
      orElse: () => widget.cell,
    );
    final count = _count(last);
    final color = asString(
      widget.styles.firstWhere(
        (style) => style['id'] == _style,
        orElse: () => {},
      )['color'],
      '#facc15',
    );
    return AlertDialog(
      title: const Text('Textabschnitt markieren'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.styles.isEmpty)
                const Text(
                  'Lege zuerst in den Einstellungen eine Markierungsfarbe an.',
                ),
              if (widget.styles.isNotEmpty)
                DropdownButtonFormField<String>(
                  initialValue: _style,
                  decoration: const InputDecoration(
                    labelText: 'Markierungsstil',
                  ),
                  items: widget.styles
                      .map(
                        (style) => DropdownMenuItem(
                          value: asString(style['id']),
                          child: Text(asString(style['name'], 'Markierung')),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setState(() => _style = value),
                ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                initialValue: _endVerse,
                decoration: const InputDecoration(labelText: 'Bis Vers'),
                items: _verses
                    .map(
                      (cell) => DropdownMenuItem(
                        value: asInt(cell['verse']),
                        child: Text('${cell['verse']}'),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      _endVerse = value;
                      _end =
                          _count(
                            _verses.firstWhere(
                              (cell) => cell['verse'] == value,
                            ),
                          ) -
                          1;
                    });
                  }
                },
              ),
              const SizedBox(height: 16),
              VerseText(
                segments: widget.cell['segments'] as List? ?? [],
                highlights: [
                  {
                    'start': _start,
                    'end': _endVerse == widget.cell['verse'] ? _end : 100000,
                    'color': color,
                  },
                ],
              ),
              Text('Ab Wort ${_start + 1}'),
              if (_count(widget.cell) > 1)
                Slider(
                  value: _start.toDouble(),
                  min: 0,
                  max: (_count(widget.cell) - 1).toDouble(),
                  divisions: _count(widget.cell) - 1,
                  label: '${_start + 1}',
                  onChanged: (value) => setState(() {
                    _start = value.round();
                    if (_endVerse == widget.cell['verse'] && _end < _start) {
                      _end = _start;
                    }
                  }),
                ),
              if (_endVerse != widget.cell['verse'])
                VerseText(
                  segments: last['segments'] as List? ?? [],
                  highlights: [
                    {'start': 0, 'end': _end, 'color': color},
                  ],
                ),
              Text('Bis Wort ${_end + 1} in Vers $_endVerse'),
              if (count > 1)
                Slider(
                  value: _end.toDouble(),
                  min: 0,
                  max: (count - 1).toDouble(),
                  divisions: count - 1,
                  label: '${_end + 1}',
                  onChanged: (value) => setState(() {
                    _end = value.round();
                    if (_endVerse == widget.cell['verse'] && _start > _end) {
                      _start = _end;
                    }
                  }),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: _style == null || count == 0
              ? null
              : () => Navigator.pop(context, <String, dynamic>{
                  'styleId': _style,
                  'startWord': _start,
                  'endWord': _end,
                  if (_endVerse > asInt(widget.cell['verse']))
                    'endVerse': _endVerse,
                }),
          child: const Text('Markieren'),
        ),
      ],
    );
  }
}
