import 'package:akribos_app/theme/akribos_theme.dart';
import 'package:akribos_app/widgets/floating_navigation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const destinations = [
  FloatingNavigationDestination(
    label: 'Lesen',
    icon: Icon(Icons.menu_book_outlined),
  ),
  FloatingNavigationDestination(label: 'Suchen', icon: Icon(Icons.search)),
  FloatingNavigationDestination(label: 'Notizen', icon: Icon(Icons.edit_note)),
  FloatingNavigationDestination(
    label: 'Sammlungen',
    icon: Icon(Icons.bookmarks_outlined),
  ),
  FloatingNavigationDestination(label: 'Mehr', icon: Icon(Icons.more_horiz)),
];

Widget frame({
  double scale = 1,
  double keyboard = 0,
  bool eInk = false,
  ValueChanged<int>? onSelected,
}) => MaterialApp(
  theme: buildAkribosTheme(Brightness.light, eInk: eInk),
  home: MediaQuery(
    data: MediaQueryData(
      textScaler: TextScaler.linear(scale),
      viewInsets: EdgeInsets.only(bottom: keyboard),
      padding: const EdgeInsets.only(bottom: 24),
    ),
    child: Scaffold(
      extendBody: true,
      body: const Text('Inhalt'),
      bottomNavigationBar: FloatingNavigationBar(
        destinations: destinations,
        selectedIndex: 0,
        onSelected: onSelected ?? (_) {},
        eInk: eInk,
      ),
    ),
  ),
);

void main() {
  test(
    'theme uses explicit PWA paper colors and separate heading typography',
    () {
      final light = buildAkribosTheme(Brightness.light);
      final dark = buildAkribosTheme(Brightness.dark);
      expect(light.scaffoldBackgroundColor, const Color(0xfff8f7f2));
      expect(light.colorScheme.surface, const Color(0xfffffefa));
      expect(light.colorScheme.primary, const Color(0xff2a6b28));
      expect(dark.scaffoldBackgroundColor, const Color(0xff111512));
      expect(dark.colorScheme.surface, const Color(0xff171c18));
      expect(light.textTheme.headlineMedium!.fontFamily, 'AkribosText');
      expect(light.colorScheme.surfaceTint, Colors.transparent);
    },
  );

  testWidgets(
    'five destinations fit 320px and 200 percent text with accessible targets',
    (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final semantics = tester.ensureSemantics();
      int? selection;
      await tester.pumpWidget(
        frame(scale: 2, onSelected: (index) => selection = index),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final bar = tester.getRect(
        find.byKey(const ValueKey('floating-navigation-surface')),
      );
      expect(bar.left, 16);
      expect(bar.right, 304);
      expect(bar.bottom, lessThanOrEqualTo(766));
      for (final destination in destinations) {
        final target = find.byKey(ValueKey('navigation-${destination.label}'));
        expect(tester.getSize(target).width, greaterThanOrEqualTo(48));
        expect(tester.getSize(target).height, greaterThanOrEqualTo(48));
        expect(find.bySemanticsLabel(destination.label), findsOneWidget);
      }
      expect(
        tester.getSemantics(find.byKey(const ValueKey('navigation-Lesen'))),
        matchesSemantics(
          label: 'Lesen',
          isButton: true,
          isSelected: true,
          hasSelectedState: true,
          hasEnabledState: true,
          isEnabled: true,
          hasTapAction: true,
        ),
      );
      await tester.tap(find.byKey(const ValueKey('navigation-Notizen')));
      expect(selection, 2);
      semantics.dispose();
    },
  );

  testWidgets('tablet keeps the floating bar centered and compact', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(frame());
    final bar = tester.getRect(
      find.byKey(const ValueKey('floating-navigation-surface')),
    );
    expect(bar.width, 560);
    expect(bar.center.dx, 640);
  });

  testWidgets(
    'keyboard frees the writing area and e-ink disables glass and motion',
    (tester) async {
      await tester.pumpWidget(frame(keyboard: 300));
      expect(find.byType(FloatingNavigationBar), findsOneWidget);
      expect(
        find.byKey(const ValueKey('floating-navigation-surface')),
        findsNothing,
      );
      await tester.pumpWidget(frame(eInk: true));
      await tester.pumpAndSettle();
      expect(find.byType(BackdropFilter), findsNothing);
      for (final container in tester.widgetList<AnimatedContainer>(
        find.byType(AnimatedContainer),
      )) {
        expect(container.duration, Duration.zero);
      }
      final theme = Theme.of(
        tester.element(find.byType(FloatingNavigationBar)),
      );
      expect(theme.colorScheme.onSurface, Colors.black);
      expect(theme.colorScheme.surface, Colors.white);
      expect(tester.takeException(), isNull);
    },
  );
}
