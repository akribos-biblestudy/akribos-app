import 'dart:ui' as ui;

import 'package:akribos_app/features/reader/reader_rich_text.dart';
import 'package:akribos_app/features/reader/reader_screen.dart';
import 'package:akribos_app/features/reader/verse_text.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'native_reader_test.dart' show app;
import 'reader_performance_test.dart' show DelayedReaderApi, longChapter;

List<SemanticsNode> traversalChildren(SemanticsNode node) =>
    node.debugListChildrenInOrder(DebugSemanticsDumpOrder.traversalOrder);

List<SemanticsNode> labelledNodes(SemanticsNode node) => [
  if (node.label.isNotEmpty) node,
  for (final child in traversalChildren(node)) ...labelledNodes(child),
];

int maximumSiblings(SemanticsNode node) {
  final children = traversalChildren(node);
  var maximum = children.length;
  for (final child in children) {
    final count = maximumSiblings(child);
    if (count > maximum) maximum = count;
  }
  return maximum;
}

List<Object> presentation(SemanticsNode root) => [
  for (final node in labelledNodes(root))
    (
      node.label,
      node.rect,
      node.getSemanticsData().hasAction(ui.SemanticsAction.tap),
      node.flagsCollection.isHidden,
    ),
];

Widget textFrame({
  required InlineSpan text,
  required bool grouped,
  required Key paragraphKey,
  ScrollController? scrollController,
  TextDirection direction = TextDirection.ltr,
  double width = 350,
  double scale = 1,
}) => MaterialApp(
  home: Scaffold(
    body: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: width,
        height: 420,
        child: SingleChildScrollView(
          controller: scrollController,
          child: grouped
              ? ReaderRichText(
                  key: paragraphKey,
                  text: text,
                  textDirection: direction,
                  textAlign: TextAlign.justify,
                  textScaler: TextScaler.linear(scale),
                )
              : RichText(
                  key: paragraphKey,
                  text: text,
                  textDirection: direction,
                  textAlign: TextAlign.justify,
                  textScaler: TextScaler.linear(scale),
                ),
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets(
    'recursive groups handle more than 1024 words and disappear after shrinking',
    (tester) async {
      final handle = tester.ensureSemantics();
      final recognizer = TapGestureRecognizer()..onTap = () {};
      try {
        const key = ValueKey('growing-paragraph');
        List<int>? retainedIds;
        for (final count in [1200, 12, 1200]) {
          final text = TextSpan(
            style: const TextStyle(fontSize: 19),
            children: [
              for (var word = 0; word < count; word++)
                TextSpan(text: 'Wort$word ', recognizer: recognizer),
            ],
          );
          await tester.pumpWidget(
            textFrame(text: text, grouped: true, paragraphKey: key),
          );
          final paragraph = tester.renderObject<RenderParagraph>(
            find.byKey(key),
          );
          final root = paragraph.debugSemantics!;
          final leaves = labelledNodes(root);
          expect(leaves, hasLength(count));
          expect(maximumSiblings(root), lessThanOrEqualTo(32));
          final firstIds = leaves.take(12).map((node) => node.id).toList();
          if (retainedIds != null) expect(firstIds, retainedIds);
          retainedIds = firstIds;
          if (count == 12) {
            expect(traversalChildren(root), hasLength(12));
            expect(
              traversalChildren(root).every((node) => node.label.isNotEmpty),
              isTrue,
            );
          }
          expect(tester.takeException(), isNull);
        }
      } finally {
        handle.dispose();
        recognizer.dispose();
      }
    },
  );

  testWidgets(
    'grouped paragraph survives accessibility being disabled and enabled',
    (tester) async {
      final recognizer = TapGestureRecognizer()..onTap = () {};
      addTearDown(recognizer.dispose);
      const key = ValueKey('semantics-lifecycle');
      final text = TextSpan(
        style: const TextStyle(fontSize: 19),
        children: [
          for (var word = 0; word < 120; word++)
            TextSpan(text: 'Wort$word ', recognizer: recognizer),
        ],
      );
      await tester.pumpWidget(
        textFrame(text: text, grouped: true, paragraphKey: key),
      );
      for (var cycle = 0; cycle < 2; cycle++) {
        final handle = tester.ensureSemantics();
        try {
          await tester.pump();
          final paragraph = tester.renderObject<RenderParagraph>(
            find.byKey(key),
          );
          expect(labelledNodes(paragraph.debugSemantics!), hasLength(120));
          expect(
            maximumSiblings(paragraph.debugSemantics!),
            lessThanOrEqualTo(32),
          );
        } finally {
          handle.dispose();
        }
        await tester.pump();
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
    semanticsEnabled: false,
  );

  testWidgets(
    'long native word semantics are bounded without changing labels or actions',
    (tester) async {
      final handle = tester.ensureSemantics();
      try {
        final actions = <String>[];
        final recognizers = <TapGestureRecognizer>[];
        TapGestureRecognizer tap(String label) {
          final recognizer = TapGestureRecognizer()
            ..onTap = () => actions.add(label);
          recognizers.add(recognizer);
          return recognizer;
        }

        addTearDown(() {
          for (final recognizer in recognizers) {
            recognizer.dispose();
          }
        });
        final text = TextSpan(
          style: const TextStyle(fontSize: 19, height: 1.7),
          children: [
            for (var verse = 1; verse <= 120; verse++) ...[
              TextSpan(text: '$verse ', recognizer: tap('verse:$verse')),
              TextSpan(text: 'Wort$verse', recognizer: tap('word:$verse')),
              const TextSpan(text: ' bleibt. '),
              TextSpan(
                text: '* ',
                semanticsLabel: 'Hinweis $verse öffnen',
                recognizer: tap('note:$verse'),
              ),
            ],
          ],
        );
        const key = ValueKey('comparison-paragraph');
        await tester.pumpWidget(
          textFrame(text: text, grouped: false, paragraphKey: key),
        );
        final native = tester.renderObject<RenderParagraph>(find.byKey(key));
        final expected = presentation(native.debugSemantics!);
        expect(
          traversalChildren(native.debugSemantics!).length,
          greaterThan(300),
        );
        final nativeText = native.text.toPlainText();
        final nativeSize = native.size;

        await tester.pumpWidget(
          textFrame(text: text, grouped: true, paragraphKey: key),
        );
        final paragraph = tester.renderObject<RenderParagraph>(find.byKey(key));
        final semantics = paragraph.debugSemantics!;
        expect(maximumSiblings(semantics), lessThanOrEqualTo(32));
        expect(presentation(semantics), expected);
        expect(paragraph.text.toPlainText(), nativeText);
        expect(paragraph.size, nativeSize);
        final nodes = labelledNodes(semantics);
        for (final label in ['1 ', 'Wort1', 'Hinweis 1 öffnen']) {
          final target = nodes.singleWhere((node) => node.label == label);
          target.owner!.performAction(target.id, ui.SemanticsAction.tap);
        }
        expect(actions, ['verse:1', 'word:1', 'note:1']);
        expect(tester.takeException(), isNull);
      } finally {
        handle.dispose();
      }
    },
  );

  for (final direction in [TextDirection.ltr, TextDirection.rtl]) {
    testWidgets(
      'grouped semantics retain IDs, clipping and native geometry for $direction',
      (tester) async {
        final handle = tester.ensureSemantics();
        try {
          final recognizers = List.generate(
            90,
            (_) => TapGestureRecognizer()..onTap = () {},
          );
          addTearDown(() {
            for (final recognizer in recognizers) {
              recognizer.dispose();
            }
          });
          final text = TextSpan(
            style: const TextStyle(fontSize: 19, height: 1.7),
            children: [
              for (var index = 0; index < recognizers.length; index++) ...[
                TextSpan(
                  text: direction == TextDirection.rtl
                      ? 'מילה$index'
                      : 'Wort$index',
                  recognizer: recognizers[index],
                ),
                const TextSpan(text: ' '),
              ],
            ],
          );
          const key = ValueKey('changing-paragraph');
          final scroll = ScrollController();
          addTearDown(scroll.dispose);
          Widget frame(bool grouped, {double width = 350, double scale = 1}) =>
              textFrame(
                text: text,
                grouped: grouped,
                paragraphKey: key,
                scrollController: scroll,
                direction: direction,
                width: width,
                scale: scale,
              );
          await tester.pumpWidget(frame(true));
          var paragraph = tester.renderObject<RenderParagraph>(find.byKey(key));
          final initial = labelledNodes(paragraph.debugSemantics!);
          final ids = {for (final node in initial) node.label: node.id};
          final rects = {for (final node in initial) node.label: node.rect};
          final initialHidden = initial
              .map((node) => node.flagsCollection.isHidden)
              .toList();
          expect(initial.any((node) => node.flagsCollection.isHidden), isTrue);
          expect(initial.any((node) => !node.flagsCollection.isHidden), isTrue);

          await tester.fling(
            find.byType(SingleChildScrollView),
            const Offset(0, -180),
            2500,
          );
          await tester.pumpAndSettle();
          paragraph = tester.renderObject<RenderParagraph>(find.byKey(key));
          final moved = labelledNodes(paragraph.debugSemantics!);
          expect({for (final node in moved) node.label: node.id}, ids);
          expect({for (final node in moved) node.label: node.rect}, rects);
          expect(
            maximumSiblings(paragraph.debugSemantics!),
            lessThanOrEqualTo(32),
          );
          expect(
            moved.map((node) => node.flagsCollection.isHidden).toList(),
            isNot(initialHidden),
          );

          for (final (width, scale) in [(280.0, 1.0), (350.0, 1.6)]) {
            scroll.jumpTo(0);
            await tester.pumpWidget(frame(true, width: width, scale: scale));
            paragraph = tester.renderObject<RenderParagraph>(find.byKey(key));
            final groupedPresentation = presentation(paragraph.debugSemantics!);
            final groupedSize = paragraph.size;
            expect(
              maximumSiblings(paragraph.debugSemantics!),
              lessThanOrEqualTo(32),
            );
            expect({
              for (final node in labelledNodes(paragraph.debugSemantics!))
                node.label: node.id,
            }, ids);
            await tester.pumpWidget(frame(false, width: width, scale: scale));
            final native = tester.renderObject<RenderParagraph>(
              find.byKey(key),
            );
            expect(groupedPresentation, presentation(native.debugSemantics!));
            expect(groupedSize, native.size);
            await tester.pumpWidget(frame(true, width: width, scale: scale));
            // Replacing the render object legitimately allocates new node IDs.
            ids
              ..clear()
              ..addEntries(
                labelledNodes(
                  tester
                      .renderObject<RenderParagraph>(find.byKey(key))
                      .debugSemantics!,
                ).map((node) => MapEntry(node.label, node.id)),
              );
          }
          expect(tester.takeException(), isNull);
        } finally {
          handle.dispose();
        }
      },
    );
  }

  testWidgets(
    '300 verse Reader keeps bounded semantics during fast flings and work swipes',
    (tester) async {
      final handle = tester.ensureSemantics();
      try {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final data = longChapter()..['versePerLine'] = false;
        final api = DelayedReaderApi(data);
        await tester.pumpWidget(app(api, const ReaderScreen(path: '/Joh1')));
        await tester.pumpAndSettle();

        void verifyVisibleParagraphs() {
          final paragraphs = tester.stateList<VerseTextState>(
            find.byType(VerseText),
          );
          expect(paragraphs, isNotEmpty);
          for (final state in paragraphs) {
            final semantics = state.paragraph?.debugSemantics;
            if (semantics != null) {
              expect(maximumSiblings(semantics), lessThanOrEqualTo(32));
            }
          }
          expect(tester.takeException(), isNull);
        }

        verifyVisibleParagraphs();
        for (final distance in [-300.0, 300.0]) {
          await tester.fling(
            find.byType(CustomScrollView),
            Offset(0, distance),
            4500,
          );
          for (var frame = 0; frame < 5; frame++) {
            await tester.pump(const Duration(milliseconds: 16));
            verifyVisibleParagraphs();
          }
          await tester.pumpAndSettle();
        }
        await tester.fling(find.byType(PageView), const Offset(-330, 0), 4500);
        await tester.pumpAndSettle();
        verifyVisibleParagraphs();
        await tester.fling(find.byType(PageView), const Offset(330, 0), 4500);
        await tester.pumpAndSettle();
        verifyVisibleParagraphs();
        expect(api.actions, isEmpty);
      } finally {
        handle.dispose();
      }
    },
  );
}
