import 'dart:ui' show BoxHeightStyle;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../core/json.dart';
import 'reader_rich_text.dart';

const assignmentNote =
    'Automatische Wortzuordnung; fachlich noch nicht bestätigt.';

class VerseRun {
  VerseRun(
    this.text, {
    this.word,
    this.position,
    this.wordIndex,
    this.note,
    this.assignment = false,
    this.italic = false,
    this.divineName = false,
    this.redLetter = false,
  });
  final String text;
  final Json? word;
  final int? position;
  final int? wordIndex;
  final String? note;
  final bool assignment;
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
            VerseRun(marker.trim().isEmpty ? '*' : marker.trim(), note: text),
          );
        } else if (studiedStrong != null &&
            precedingWord != null &&
            strongNumbers(precedingWord).contains(studiedStrong)) {
          result.add(
            VerseRun(
              'ⓘ',
              assignment: true,
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
  return _placeVerseNotes(result);
}

// A leading note has no preceding word anchor and describes the whole verse.
// Keep source word/highlight indices: this is a display-only ordering of runs.
List<VerseRun> _placeVerseNotes(List<VerseRun> source) {
  final letters = RegExp(r'[\p{L}\p{N}]', unicode: true);
  final first = source.indexWhere(
    (run) => run.note == null && letters.hasMatch(run.text),
  );
  final last = source.lastIndexWhere(
    (run) => run.note == null && letters.hasMatch(run.text),
  );
  final ending = <VerseRun>[];
  final result = <VerseRun>[];
  for (var i = 0; i < source.length; i++) {
    final run = source[i];
    if (run.note != null && !run.assignment && (i < first || i > last)) {
      ending.add(run);
    } else {
      result.add(run);
    }
  }
  if (ending.isNotEmpty) {
    final markers = ending.map((run) => run.text).toSet();
    final note = VerseRun(
      markers.join(', '),
      note: ending.length == 1
          ? ending.single.note
          : ending.map((run) => '${run.text}: ${run.note}').join('\n\n'),
    );
    var insert = result.length;
    while (insert > 0 && result[insert - 1].text.trim().isEmpty) {
      insert--;
    }
    result.insert(insert, note);
  }
  // Source XML sometimes separates a word from its marker with whitespace.
  // Move that whitespace behind the marker, keeping the scripture bytes and
  // previously computed word indices unchanged.
  for (var i = 1; i < result.length; i++) {
    if (result[i].note == null ||
        result[i - 1].note != null ||
        result[i - 1].text.trim().isNotEmpty) {
      continue;
    }
    final gap = result.removeAt(i - 1);
    result.insert(i, gap);
  }
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

/// One verse in a paragraph. Offsets for Strong words restart for every verse.
class VersePassage {
  const VersePassage({
    required this.segments,
    this.number,
    this.highlights = const [],
    this.onWord,
    this.onOpen,
  });
  final List<dynamic> segments;
  final String? number;
  final List<Json> highlights;
  final void Function(Json word, int position)? onWord;
  final VoidCallback? onOpen;
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
    this.passages,
    this.showHighlightLabels = false,
  });
  final List<dynamic> segments;
  final List<VersePassage>? passages;
  final void Function(Json word, int position)? onWord;
  final TextDirection? direction;
  final String? studiedStrong;
  final List<Json> highlights;
  final double fontSize;
  final List<String> needles;
  final String? verseNumber;
  final VoidCallback? onVerseNumber;
  final bool selectable;
  final bool showHighlightLabels;
  @override
  State<VerseText> createState() => VerseTextState();
}

class VerseTextState extends State<VerseText> {
  final _recognizers = <TapGestureRecognizer>[];
  final _noteTextPainter = TextPainter();
  final _textKey = GlobalKey();
  final _starts = <int>[];
  List<VersePassage> _passages = [];
  List<Object?>? _presentationInputs;
  Widget? _presentation;
  RenderParagraph? get paragraph {
    final render = _textKey.currentContext?.findRenderObject();
    return render is RenderParagraph ? render : null;
  }

  /// Actual glyph positions, also used to preserve the verse while reflowing.
  double passageTop(int index) {
    if (index < 0 || index >= _starts.length) return 0;
    final boxes = paragraph?.getBoxesForSelection(
      TextSelection(
        baseOffset: _starts[index],
        extentOffset: _starts[index] + 1,
      ),
      // The verse number is smaller than its first word. Use the tallest run
      // on its line so restoring the verse cannot clip scripture or a note.
      boxHeightStyle: BoxHeightStyle.max,
    );
    return boxes == null || boxes.isEmpty ? 0 : boxes.first.top;
  }

  int passageAt(Offset local) {
    final offset = paragraph?.getPositionForOffset(local).offset ?? 0;
    final index = _starts.lastIndexWhere((start) => start <= offset);
    return index < 0 ? 0 : index;
  }

  int passageAtHeight(double y) {
    // At the leading edge of a line, including RTL paragraphs.
    final render = paragraph;
    return passageAt(
      Offset(
        widget.direction == TextDirection.rtl ? render?.size.width ?? 0 : 0,
        y,
      ),
    );
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
    _noteTextPainter.dispose();
    super.dispose();
  }

  TapGestureRecognizer _tap(VoidCallback action) {
    final recognizer = TapGestureRecognizer()..onTap = action;
    _recognizers.add(recognizer);
    return recognizer;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final highContrast = MediaQuery.highContrastOf(context);
    final textScaler = MediaQuery.textScalerOf(context);
    final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
    final inheritedStyle = DefaultTextStyle.of(context).style;
    _passages =
        widget.passages ??
        [
          VersePassage(
            segments: widget.segments,
            number: widget.verseNumber,
            highlights: widget.highlights,
            onWord: widget.onWord,
            onOpen: widget.onVerseNumber,
          ),
        ];
    // Chapter reloads replace their segment lists. Selecting another tab or
    // persisting a position only recreates passage/highlight wrappers: keep the
    // shaped paragraph, recognizers and note overlay intact for those updates.
    // Actions resolve the current passage below instead of retaining callbacks
    // from a previous parent build.
    final inputs = <Object?>[
      colors,
      theme.textTheme.labelSmall?.fontFamily,
      inheritedStyle,
      highContrast,
      textScaler,
      devicePixelRatio,
      widget.fontSize,
      widget.direction,
      if (widget.direction == null) widget.segments,
      widget.studiedStrong,
      widget.selectable,
      widget.passages != null,
      widget.showHighlightLabels,
      widget.needles.length,
      ...widget.needles,
      _passages.length,
      for (final passage in _passages) ...[
        passage.segments,
        passage.number,
        passage.onOpen != null,
        passage.onWord != null,
        passage.highlights.length,
        for (final range in passage.highlights) ...[
          range['start'],
          range['end'],
          range['color'],
          if (widget.showHighlightLabels) range['name'],
        ],
      ],
    ];
    if (_presentation != null && listEquals(inputs, _presentationInputs)) {
      return _presentation!;
    }
    _presentationInputs = inputs;
    _clearRecognizers();
    _starts.clear();
    final spans = <InlineSpan>[];
    final marks = <VerseMarkerRange>[];
    final notes = <VerseNoteRange>[];
    final noteStyle = inheritedStyle.copyWith(
      fontFamily: 'AkribosText',
      fontFamilyFallback: const ['NotoSansHebrew'],
      fontSize: widget.fontSize * .65,
      fontWeight: FontWeight.w400,
      height: 1,
      letterSpacing: 0,
      color: colors.primary,
    );
    var offset = 0;
    for (
      var passageIndex = 0;
      passageIndex < _passages.length;
      passageIndex++
    ) {
      final passage = _passages[passageIndex];
      if (spans.isNotEmpty) {
        spans.add(const TextSpan(text: ' '));
        offset++;
      }
      _starts.add(offset);
      if (passage.number != null) {
        // Keep the number with the first word without creating a separate
        // widget: glyph offsets and Strong-word positions stay in one paragraph.
        final number = '${passage.number}\u00a0';
        spans.add(
          TextSpan(
            text: number,
            recognizer: passage.onOpen == null
                ? null
                : _tap(() => _passages[passageIndex].onOpen?.call()),
            style: TextStyle(
              fontSize: widget.fontSize * .65,
              fontWeight: FontWeight.w700,
              color: colors.primary,
              fontFamily: theme.textTheme.labelSmall?.fontFamily,
            ),
          ),
        );
        offset += number.length;
      }
      final runs = verseRuns(
        passage.segments,
        studiedStrong: widget.studiedStrong,
      );
      // Imported verse-leading whitespace must not reopen the break after
      // the number. Remove it only from this presentation, not stored segments.
      if (passage.number != null) {
        while (runs.isNotEmpty &&
            runs.first.note == null &&
            runs.first.text.trim().isEmpty) {
          runs.removeAt(0);
        }
      }
      final runOffsets = <int>[];
      for (final run in runs) {
        runOffsets.add(offset);
        final text = run.divineName ? run.text.toUpperCase() : run.text;
        if (run.note != null) {
          // The native paragraph must measure the actual marker with its word.
          // WidgetSpan can break after punctuation even behind a word joiner in
          // justified paragraphs. Only its visual baseline is raised below.
          final marker = run.text.replaceAll(RegExp(r'\s'), '\u00a0');
          void openNote() => showDialog<void>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Anmerkung'),
              content: SingleChildScrollView(child: SelectableText(run.note!)),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Schließen'),
                ),
              ],
            ),
          );
          spans.add(
            TextSpan(
              text: '\u2060$marker',
              semanticsLabel: 'Hinweis ${run.text} öffnen',
              style: noteStyle.copyWith(color: Colors.transparent),
              recognizer: _tap(openNote),
            ),
          );
          notes.add(VerseNoteRange(offset + 1, marker, openNote));
          offset += marker.length + 1;
          continue;
        }
        offset += text.length;
        TapGestureRecognizer? recognizer;
        if (run.word != null && passage.onWord != null) {
          recognizer = _tap(
            () =>
                _passages[passageIndex].onWord?.call(run.word!, run.position!),
          );
        }
        final searchHit = widget.needles.any(
          (needle) =>
              needle.isNotEmpty &&
              run.text.toLowerCase().contains(needle.toLowerCase()),
        );
        spans.add(
          TextSpan(
            text: text,
            recognizer: recognizer,
            style: TextStyle(
              fontFamily: 'AkribosText',
              fontFamilyFallback: const ['NotoSansHebrew'],
              fontStyle: run.italic ? FontStyle.italic : null,
              fontSize: run.divineName ? widget.fontSize * .9 : null,
              color: run.redLetter && !highContrast
                  ? const Color(0xffa53731)
                  : null,
              backgroundColor: searchHit ? colors.tertiaryContainer : null,
              decoration:
                  run.word != null &&
                      widget.studiedStrong != null &&
                      strongNumbers(run.word!).contains(widget.studiedStrong)
                  ? TextDecoration.underline
                  : null,
            ),
          ),
        );
      }
      // A selection spans all intervening spaces, punctuation and note markers.
      // Partial highlights retain the exact stored display-word boundaries.
      for (final range in passage.highlights) {
        final indices = [
          for (var i = 0; i < runs.length; i++)
            if (runs[i].wordIndex != null &&
                runs[i].wordIndex! >= asInt(range['start']) &&
                runs[i].wordIndex! <= asInt(range['end'], 100000))
              i,
        ];
        final color = verseColor(asString(range['color']));
        if (indices.isEmpty || color == null) continue;
        final last = indices.last;
        final end = last + 1 < runOffsets.length
            ? runOffsets[last + 1]
            : offset;
        marks.add(VerseMarkerRange(runOffsets[indices.first], end, color));
      }
      if (widget.showHighlightLabels && passage.highlights.isNotEmpty) {
        final labels = passage.highlights
            .map((item) => asString(item['name'], 'Markierung'))
            .toSet();
        final label = ' (Markiert: ${labels.join(', ')})';
        spans.add(
          TextSpan(
            text: label,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        );
        offset += label.length;
      }
    }
    final style = inheritedStyle.merge(
      TextStyle(
        fontWeight: FontWeight.w400,
        fontFamily: 'AkribosText',
        fontFamilyFallback: const ['NotoSansHebrew'],
        fontSize: widget.fontSize,
        height: 1.65,
      ),
    );
    final direction = widget.direction ?? verseDirection(widget.segments);
    final paragraphText = TextSpan(style: style, children: spans);
    // Keep the entire shaping context: bidi runs can separate a marker's parts,
    // and a long source marker can occupy more than one line.
    final noteStarts = notes.map((note) => note.start - 1).toSet();
    var paintOffset = 0;
    TextSpan noteOverlay(TextSpan span) {
      final visible = noteStarts.contains(paintOffset);
      paintOffset += span.text?.length ?? 0;
      return TextSpan(
        text: span.text,
        style: (span.style ?? const TextStyle()).copyWith(
          foreground: Paint()
            ..color = visible ? colors.primary : Colors.transparent,
          background: Paint()..color = Colors.transparent,
          decoration: TextDecoration.none,
          shadows: const [],
        ),
        children: span.children?.cast<TextSpan>().map(noteOverlay).toList(),
      );
    }

    _noteTextPainter.text = notes.isEmpty ? null : noteOverlay(paragraphText);
    Widget text = Builder(
      builder: (textContext) => CustomPaint(
        painter: VerseMarkerPainter(
          paragraph: () => paragraph,
          ranges: marks,
          highContrast: highContrast,
          inkColor: colors.onSurface,
          devicePixelRatio: devicePixelRatio,
        ),
        foregroundPainter: VerseNotePainter(
          paragraph: () => paragraph,
          notes: notes,
          textPainter: _noteTextPainter,
          lift: textScaler.scale(widget.fontSize) * .18,
        ),
        child: ReaderRichText(
          key: _textKey,
          text: paragraphText,
          textDirection: direction,
          textAlign: widget.passages == null
              ? TextAlign.start
              : TextAlign.justify,
          textScaler: textScaler,
          selectionRegistrar: widget.selectable
              ? SelectionContainer.maybeOf(textContext)
              : null,
          selectionColor: colors.primary.withValues(alpha: .25),
        ),
      ),
    );
    text = GestureDetector(
      behavior: HitTestBehavior.translucent,
      // The raised top edge can lie above RenderParagraph's native glyph hit
      // box. Native span taps win inside it; this catches only remaining taps.
      onTapUp: (details) {
        final render = paragraph;
        if (render == null) return;
        final local = render.globalToLocal(details.globalPosition);
        final painter = VerseNotePainter(
          paragraph: () => render,
          notes: notes,
          textPainter: _noteTextPainter,
          lift: textScaler.scale(widget.fontSize) * .18,
        );
        for (final note in notes) {
          if (painter.rectangles(note).any((rect) => rect.contains(local))) {
            note.onOpen();
            return;
          }
        }
      },
      onLongPressStart: widget.selectable
          ? null
          : (details) {
              final render = paragraph;
              if (render == null) return;
              _passages[passageAt(render.globalToLocal(details.globalPosition))]
                  .onOpen
                  ?.call();
            },
      child: text,
    );
    return _presentation = widget.selectable
        ? SelectionArea(child: text)
        : text;
  }
}

class VerseNoteRange {
  const VerseNoteRange(this.start, this.text, this.onOpen);
  final int start;
  final String text;
  final VoidCallback onOpen;
}

/// Superscript is a paint offset only. The native paragraph owns line breaking,
/// advances, selection, semantics and taps, including arbitrarily named markers.
class VerseNotePainter extends CustomPainter {
  VerseNotePainter({
    required this.paragraph,
    required this.notes,
    required this.textPainter,
    required this.lift,
  });
  final RenderParagraph? Function() paragraph;
  final List<VerseNoteRange> notes;
  final TextPainter textPainter;
  final double lift;

  List<Rect> rectangles(VerseNoteRange note) =>
      paragraph()
          ?.getBoxesForSelection(
            TextSelection(
              baseOffset: note.start,
              extentOffset: note.start + note.text.length,
            ),
          )
          .map((box) => box.toRect().shift(Offset(0, -lift)))
          .toList() ??
      [];

  @override
  void paint(Canvas canvas, Size size) {
    final render = paragraph();
    if (render == null) return;
    final clip = canvas.getLocalClipBounds();
    if (!notes.any(
      (note) => rectangles(note).any((rect) => rect.overlaps(clip)),
    )) {
      return;
    }
    // Match RenderParagraph's layout, not an isolated marker. The state owns
    // and disposes this painter; repeated paints reuse its shaped paragraph.
    textPainter
      ..textDirection = render.textDirection
      ..textAlign = render.textAlign
      ..textScaler = render.textScaler
      ..strutStyle = render.strutStyle
      ..textWidthBasis = render.textWidthBasis
      ..textHeightBehavior = render.textHeightBehavior
      ..locale = render.locale
      ..maxLines = render.maxLines
      ..ellipsis = render.overflow == TextOverflow.ellipsis ? '\u2026' : null
      ..layout(
        minWidth: render.constraints.minWidth,
        maxWidth: render.softWrap || render.overflow == TextOverflow.ellipsis
            ? render.constraints.maxWidth
            : double.infinity,
      );
    textPainter.paint(canvas, Offset(0, -lift));
  }

  @override
  bool shouldRepaint(VerseNotePainter oldDelegate) => true;
}

class VerseMarkerRange {
  const VerseMarkerRange(this.start, this.end, this.color);
  final int start, end;
  final Color color;
}

/// Uses the rendered paragraph itself: shaping, scaling and bidirectional text
/// must match the ink exactly. Paint runs behind glyphs and never intercepts taps.
class VerseMarkerPainter extends CustomPainter {
  VerseMarkerPainter({
    required this.paragraph,
    required this.ranges,
    required this.highContrast,
    required this.inkColor,
    this.devicePixelRatio = 1,
  });
  final Color inkColor;
  final RenderParagraph? Function() paragraph;
  final List<VerseMarkerRange> ranges;
  final bool highContrast;
  final double devicePixelRatio;

  List<Rect> rectangles(VerseMarkerRange range) {
    final render = paragraph();
    if (render == null) return [];
    final boxes = render.getBoxesForSelection(
      TextSelection(baseOffset: range.start, extentOffset: range.end),
    );
    // A line-ending space may extend beyond a justified paragraph, especially
    // with RTL text. Keep the continuous marker inside the actual text column.
    final bounds = Offset.zero & render.size;
    final rects =
        boxes
            .map((box) => box.toRect().intersect(bounds))
            .where((r) => r.width > 0)
            .toList()
          ..sort((a, b) {
            final line = a.center.dy.compareTo(b.center.dy);
            return (a.center.dy - b.center.dy).abs() < 4
                ? a.left.compareTo(b.left)
                : line;
          });
    final merged = <Rect>[];
    for (final rect in rects) {
      if (merged.isNotEmpty) {
        final previous = merged.last;
        if ((previous.center.dy - rect.center.dy).abs() <
                previous.height * .45 &&
            rect.left <= previous.right + 1) {
          merged[merged.length - 1] = previous.expandToInclude(rect);
          continue;
        }
      }
      merged.add(rect);
    }
    return merged;
  }

  @override
  void paint(Canvas canvas, Size size) {
    for (final range in ranges) {
      for (final rect in rectangles(range)) {
        if (highContrast) {
          // Fractional antialiased strokes can contain no fully opaque pixels.
          // E-Ink threshold/dither modes need a solid band on the first frame.
          final bottom = (rect.bottom * devicePixelRatio).floorToDouble();
          final thickness = (2 * devicePixelRatio).ceilToDouble();
          canvas.drawRect(
            Rect.fromLTRB(
              (rect.left * devicePixelRatio).floor() / devicePixelRatio,
              (bottom - thickness) / devicePixelRatio,
              (rect.right * devicePixelRatio).ceil() / devicePixelRatio,
              bottom / devicePixelRatio,
            ),
            Paint()
              ..color = inkColor.withValues(alpha: 1)
              ..isAntiAlias = false,
          );
          continue;
        }
        final top = rect.top + rect.height * .14,
            bottom = rect.bottom - rect.height * .05;
        final left = rect.left, right = rect.right, width = rect.width;
        final path = Path()
          ..moveTo(left, top + 1)
          ..cubicTo(
            left + width * .28,
            top - .8,
            left + width * .65,
            top + 1.3,
            right,
            top,
          )
          ..lineTo(right - .5, bottom - .7)
          ..cubicTo(
            left + width * .7,
            bottom + 1,
            left + width * .3,
            bottom - 1,
            left,
            bottom + .6,
          )
          ..close();
        canvas.drawPath(
          path,
          Paint()..color = range.color.withValues(alpha: .38),
        );
      }
    }
  }

  @override
  bool shouldRepaint(VerseMarkerPainter oldDelegate) => true;
}
