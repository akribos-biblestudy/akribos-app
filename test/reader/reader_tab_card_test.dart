import 'package:akribos_app/features/reader/reader_tab_card.dart';
import 'package:akribos_app/theme/akribos_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const preview =
    'Im Anfang war das Wort, und das Wort war bei Gott, und das Wort war Gott. '
    'Dieses war im Anfang bei Gott. Alles wurde durch dasselbe.';

Widget frame({
  double width = 160,
  double scale = 1,
  bool eInk = false,
  String previewText = preview,
  VoidCallback? onTap,
  VoidCallback? onMenu,
}) => MaterialApp(
  theme: buildAkribosTheme(Brightness.light, eInk: eInk),
  home: MediaQuery(
    data: MediaQueryData(textScaler: TextScaler.linear(scale)),
    child: Scaffold(
      body: Center(
        child: SizedBox(
          width: width,
          height: ReaderTabCard.heightFor(TextScaler.linear(scale)),
          child: ReaderTabCard(
            title: 'Elberfelder Bibel mit ausführlichen Erläuterungen',
            reference: 'Johannes 1,1–18',
            previewText: previewText,
            resourceKind: 'bible',
            linkSet: 'A',
            selected: true,
            onTap: onTap ?? () {},
            trailing: IconButton(
              tooltip: 'Werk verwalten',
              onPressed: onMenu ?? () {},
              icon: const Icon(Icons.more_horiz),
            ),
          ),
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('160px card grows for large text and keeps the real excerpt', (
    tester,
  ) async {
    for (final scale in [1.0, 2.0, 3.0]) {
      await tester.pumpWidget(frame(scale: scale));
      expect(tester.takeException(), isNull);
      expect(find.text(preview), findsOneWidget);
      expect(find.text('Johannes 1,1–18'), findsOneWidget);
      final text = tester.widget<Text>(find.text(preview));
      expect(text.maxLines, 3);
      expect(text.style!.fontFamily, 'AkribosText');
      expect(tester.getSize(find.byType(ReaderTabCard)).width, 160);
      expect(
        tester.getSize(find.byType(ReaderTabCard)).height,
        ReaderTabCard.heightFor(TextScaler.linear(scale)),
      );
    }
    await tester.pumpWidget(frame(width: 260));
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(ReaderTabCard)), const Size(260, 188));
  });

  testWidgets('card selection and menu remain separate accessible actions', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var selections = 0;
    var menus = 0;
    await tester.pumpWidget(
      frame(onTap: () => selections++, onMenu: () => menus++),
    );
    expect(
      tester.getSemantics(
        find.bySemanticsLabel(
          'Elberfelder Bibel mit ausführlichen Erläuterungen, Bibel, '
          'Johannes 1,1–18, Tabgruppe A, $preview',
        ),
      ),
      matchesSemantics(
        label:
            'Elberfelder Bibel mit ausführlichen Erläuterungen, Bibel, '
            'Johannes 1,1–18, Tabgruppe A, $preview',
        isButton: true,
        isSelected: true,
        hasSelectedState: true,
        hasEnabledState: true,
        isEnabled: true,
        hasTapAction: true,
      ),
    );
    await tester.tap(find.byTooltip('Werk verwalten'));
    expect(menus, 1);
    expect(selections, 0);
    expect(tester.getSize(find.byType(IconButton)), const Size(48, 48));
    await tester.tap(find.text(preview));
    expect(selections, 1);
    semantics.dispose();
  });

  testWidgets('e-ink keeps selection visible without color, shadow or motion', (
    tester,
  ) async {
    await tester.pumpWidget(frame(eInk: true, previewText: ''));
    final decoration =
        tester
                .widget<DecoratedBox>(
                  find.byKey(const ValueKey('reader-tab-card-paper')),
                )
                .decoration
            as BoxDecoration;
    expect(decoration.color, Colors.white);
    expect(decoration.border!.top.color, Colors.black);
    expect(decoration.border!.top.width, 2);
    expect(decoration.boxShadow, isEmpty);
    expect(find.byType(AnimatedContainer), findsNothing);
    expect(find.byType(BackdropFilter), findsNothing);
    expect(find.text('Noch kein Textauszug geladen.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
