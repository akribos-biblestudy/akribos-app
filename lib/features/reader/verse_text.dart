import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../core/json.dart';

const assignmentNote =
    'Automatische Wortzuordnung; fachlich noch nicht bestätigt.';

class VerseRun {
  VerseRun(
    this.text, {
    this.word,
    this.position,
    this.wordIndex,
    this.note,
    this.italic = false,
    this.divineName = false,
    this.redLetter = false,
  });
  final String text;
  final Json? word;
  final int? position;
  final int? wordIndex;
  final String? note;
  final bool italic;
  final bool divineName;
  final bool redLetter;
}

/// Positions count tagged words only, exactly like verse_words.position. The
/// separate highlight cursor counts whitespace-delimited display words.
List<VerseRun> verseRuns(List<dynamic> segments, {String? studiedStrong}) {
  var position = 0;
  var wordIndex = -1;
  var openWord = false;
  final result = <VerseRun>[];
  void visit(List<dynamic> items, {bool red = false, bool divine = false}) {
    Json? precedingWord;
    for (final item in items) {
      if (item is String) {
        for (final match in RegExp(r'\s+|\S+').allMatches(item)) {
          final text = match.group(0)!;
          if (text.trim().isEmpty) {
            openWord = false;
            result.add(VerseRun(text, divineName: divine, redLetter: red));
          } else {
            if (!openWord) wordIndex++;
            openWord = true;
            precedingWord = null;
            result.add(
              VerseRun(
                text,
                wordIndex: wordIndex,
                divineName: divine,
                redLetter: red,
              ),
            );
          }
        }
        continue;
      }
      final segment = asMap(item);
      final kind = segment['kind'];
      if (kind == 'w') {
        if (!openWord) wordIndex++;
        openWord = true;
        result.add(
          VerseRun(
            asString(segment['text']),
            word: segment,
            position: position++,
            wordIndex: wordIndex,
            divineName: divine,
            redLetter: red,
          ),
        );
        precedingWord = segment;
        continue;
      }
      if (kind == 'nd' || kind == 'wj') {
        visit(
          segment['children'] as List? ?? [],
          red: red || kind == 'wj',
          divine: divine || kind == 'nd',
        );
      } else if (kind == 'br') {
        openWord = false;
        result.add(VerseRun('\n'));
      } else if (kind == 'em') {
        for (final match in RegExp(
          r'\s+|\S+',
        ).allMatches(asString(segment['text']))) {
          final text = match.group(0)!;
          if (text.trim().isEmpty) {
            openWord = false;
          } else {
            if (!openWord) wordIndex++;
            openWord = true;
          }
          result.add(
            VerseRun(
              text,
              wordIndex: text.trim().isEmpty ? null : wordIndex,
              italic: true,
              divineName: divine,
              redLetter: red,
            ),
          );
        }
      } else if (kind == 'note') {
        final text = asString(segment['text']);
        final marker = asString(segment['marker']);
        final automatic =
            marker.trim().isEmpty &&
            text.trim().replaceAll(RegExp(r'\s+'), ' ') == assignmentNote;
        if (!automatic) {
          result.add(
            VerseRun(marker.isEmpty ? ' ⁎ ' : ' $marker ', note: text),
          );
        } else if (studiedStrong != null &&
            precedingWord != null &&
            strongNumbers(precedingWord).contains(studiedStrong)) {
          result.add(
            VerseRun(
              ' ⓘ ',
              note:
                  'Die Strong-Zuordnung von „${precedingWord['text']}“ zu $studiedStrong ist fachlich noch nicht bestätigt.',
            ),
          );
        }
      }
      precedingWord = null;
    }
  }

  visit(segments);
  return result;
}

List<String> strongNumbers(Json word) => word['strongs'] is List
    ? (word['strongs'] as List).whereType<String>().toList()
    : [if (asString(word['strong']).isNotEmpty) asString(word['strong'])];

String versePlainText(List<dynamic> segments) =>
    verseRuns(segments)
        .where((run) => run.note == null)
        .map((run) => run.text)
        .join()
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

TextDirection verseDirection(List<dynamic> segments) {
  final firstLetter = RegExp(r'[A-Za-z\u0370-\u03ff\u1f00-\u1fff\u0590-\u05ff]')
      .firstMatch(versePlainText(segments))
      ?.group(0);
  return firstLetter != null && RegExp(r'[\u0590-\u05ff]').hasMatch(firstLetter)
      ? TextDirection.rtl
      : TextDirection.ltr;
}

Color? verseColor(String value) {
  final hex = value.replaceFirst('#', '');
  final parsed = int.tryParse(hex, radix: 16);
  if (parsed == null || (hex.length != 6 && hex.length != 8)) return null;
  return Color(hex.length == 6 ? 0xff000000 | parsed : parsed);
}

class VerseText extends StatefulWidget {
  const VerseText({
    super.key,
    required this.segments,
    this.onWord,
    this.direction,
    this.studiedStrong,
    this.highlights = const [],
    this.fontSize = 19,
    this.needles = const [],
    this.verseNumber,
    this.onVerseNumber,
    this.selectable = true,
  });
  final List<dynamic> segments;
  final void Function(Json word, int position)? onWord;
  final TextDirection? direction;
  final String? studiedStrong;
  final List<Json> highlights;
  final double fontSize;
  final List<String> needles;
  final String? verseNumber;
  final VoidCallback? onVerseNumber;
  final bool selectable;
  @override
  State<VerseText> createState() => _VerseTextState();
}

class _VerseTextState extends State<VerseText> {
  final _recognizers = <TapGestureRecognizer>[];
  late List<VerseRun> _runs = verseRuns(
    widget.segments,
    studiedStrong: widget.studiedStrong,
  );

  @override
  void didUpdateWidget(VerseText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.segments, widget.segments) ||
        oldWidget.studiedStrong != widget.studiedStrong) {
      _runs = verseRuns(widget.segments, studiedStrong: widget.studiedStrong);
    }
  }

  void _clearRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  @override
  void dispose() {
    _clearRecognizers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _clearRecognizers();
    final colors = Theme.of(context).colorScheme;
    final highContrast = MediaQuery.highContrastOf(context);
    final spans = <InlineSpan>[];
    if (widget.verseNumber != null) {
      final recognizer = TapGestureRecognizer()
        ..onTap = () => widget.onVerseNumber?.call();
      _recognizers.add(recognizer);
      spans.add(
        TextSpan(
          text: '${widget.verseNumber} ',
          recognizer: recognizer,
          style: TextStyle(
            fontSize: widget.fontSize * .65,
            fontWeight: FontWeight.w700,
            color: colors.primary,
            fontFamily: Theme.of(context).textTheme.labelSmall?.fontFamily,
          ),
        ),
      );
    }
    for (final run in _runs) {
      Color? highlight;
      for (final range in widget.highlights) {
        if (run.wordIndex != null &&
            run.wordIndex! >= asInt(range['start']) &&
            run.wordIndex! <= asInt(range['end'], 100000)) {
          highlight = verseColor(asString(range['color']));
        }
      }
      if (widget.needles.any(
        (needle) =>
            needle.isNotEmpty &&
            run.text.toLowerCase().contains(needle.toLowerCase()),
      )) {
        highlight = colors.tertiaryContainer;
      }
      TapGestureRecognizer? recognizer;
      if (run.note != null || (run.word != null && widget.onWord != null)) {
        recognizer = TapGestureRecognizer()
          ..onTap = () {
            if (run.note != null) {
              showDialog<void>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Anmerkung'),
                  content: SelectableText(run.note!),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Schließen'),
                    ),
                  ],
                ),
              );
            } else {
              widget.onWord!(run.word!, run.position!);
            }
          };
        _recognizers.add(recognizer);
      }
      spans.add(
        TextSpan(
          text: run.divineName ? run.text.toUpperCase() : run.text,
          recognizer: recognizer,
          style: TextStyle(
            fontFamily: run.note == null ? 'AkribosText' : null,
            fontFamilyFallback: const ['NotoSansHebrew'],
            fontStyle: run.italic ? FontStyle.italic : null,
            fontSize: run.note != null
                ? widget.fontSize * .75
                : run.divineName
                ? widget.fontSize * .9
                : null,
            color: run.note != null
                ? colors.primary
                : run.redLetter && !highContrast
                ? const Color(0xffa53731)
                : null,
            backgroundColor: highlight?.withValues(alpha: .38),
            decoration:
                (highContrast && highlight != null) ||
                    (run.word != null &&
                        widget.studiedStrong != null &&
                        strongNumbers(run.word!).contains(widget.studiedStrong))
                ? TextDecoration.underline
                : null,
          ),
        ),
      );
    }
    final style = TextStyle(
      fontWeight: FontWeight.w400,
      fontFamily: 'AkribosText',
      fontFamilyFallback: const ['NotoSansHebrew'],
      fontSize: widget.fontSize,
      height: 1.65,
    );
    final span = TextSpan(children: spans);
    final direction = widget.direction ?? verseDirection(widget.segments);
    if (!widget.selectable) {
      return Text.rich(span, textDirection: direction, style: style);
    }
    return SelectableText.rich(span, textDirection: direction, style: style);
  }
}
