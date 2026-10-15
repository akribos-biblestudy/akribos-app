import 'package:akribos_app/features/reader/reader_group_badge.dart';
import 'package:akribos_app/theme/akribos_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget frame({
  Brightness brightness = Brightness.light,
  bool eInk = false,
  double scale = 1,
}) => MaterialApp(
  theme: buildAkribosTheme(brightness, eInk: eInk),
  home: MediaQuery(
    data: MediaQueryData(textScaler: TextScaler.linear(scale)),
    child: Scaffold(
      body: Wrap(
        spacing: 12,
        children: [
          for (final group in ['A', 'B', 'C', 'D', 'E', null])
            ReaderGroupBadge(linkSet: group, selected: group == 'A'),
        ],
      ),
    ),
  ),
);

void main() {
  test('group identities match the five published web portal colors', () {
    expect(ReaderLinkGroupColors.base, {
      'A': const Color(0xffb9683f),
      'B': const Color(0xff55759b),
      'C': const Color(0xff60836d),
      'D': const Color(0xff776b91),
      'E': const Color(0xff9a6572),
    });
    expect(ReaderLinkGroupColors.baseColor(null), isNull);
  });

  testWidgets('all light and dark group letters meet small-text contrast', (
    tester,
  ) async {
    for (final brightness in Brightness.values) {
      await tester.pumpWidget(frame(brightness: brightness));
      for (final group in ['A', 'B', 'C', 'D', 'E', 'Keine']) {
        final decoration =
            tester
                    .widget<DecoratedBox>(
                      find.byKey(ValueKey('reader-group-badge-$group')),
                    )
                    .decoration
                as BoxDecoration;
        final text = tester.widget<Text>(find.text(group));
        final background = decoration.color!.computeLuminance();
        final foreground = text.style!.color!.computeLuminance();
        final ratio = (background > foreground)
            ? (background + .05) / (foreground + .05)
            : (foreground + .05) / (background + .05);
        expect(
          ratio,
          greaterThanOrEqualTo(4.5),
          reason: '$group / $brightness',
        );
      }
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('groups retain explicit accessible labels in monochrome', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(frame(eInk: true, scale: 3));
    for (final group in ['A', 'B', 'C', 'D', 'E', 'Keine']) {
      expect(find.text(group), findsOneWidget);
      expect(
        find.bySemanticsLabel(
          group == 'Keine' ? 'Tabgruppe Keine, unabhängig' : 'Tabgruppe $group',
        ),
        findsOneWidget,
      );
      final decoration =
          tester
                  .widget<DecoratedBox>(
                    find.byKey(ValueKey('reader-group-badge-$group')),
                  )
                  .decoration
              as BoxDecoration;
      expect(decoration.color, Colors.white);
      expect(decoration.border!.top.color, Colors.black);
      expect(decoration.border!.top.width, group == 'A' ? 2 : 1);
    }
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });
}
