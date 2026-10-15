import 'package:flutter/material.dart';

/// The native counterpart of ../akribos/src/routes/layout.css.
/// Accent values are sRGB conversions of the PWA's OKLCH hue 143 palette.
abstract final class AkribosColors {
  static const paper = Color(0xfff8f7f2);
  static const paperDeep = Color(0xfff0eee6);
  static const surface = Color(0xfffffefa);
  static const raised = Color(0xffffffff);
  static const ink = Color(0xff1c1917);
  static const muted = Color(0xff78716c);
  static const green100 = Color(0xffd3f2d1);
  static const green300 = Color(0xff86cc82);
  static const green500 = Color(0xff4aa747);
  static const green600 = Color(0xff368935);
  static const green700 = Color(0xff2a6b28);
  static const green900 = Color(0xff1a3819);
  static const darkPaper = Color(0xff111512);
  static const darkPaperDeep = Color(0xff181d19);
  static const darkSurface = Color(0xff171c18);
  static const darkRaised = Color(0xff1c221d);
}

@immutable
class AkribosThemeTokens extends ThemeExtension<AkribosThemeTokens> {
  const AkribosThemeTokens({
    required this.paper,
    required this.paperDeep,
    required this.surfaceRaised,
    required this.line,
    required this.muted,
    required this.accent,
    required this.accentSoft,
    required this.shadow,
    this.eInk = false,
  });

  final Color paper,
      paperDeep,
      surfaceRaised,
      line,
      muted,
      accent,
      accentSoft,
      shadow;
  final bool eInk;

  static AkribosThemeTokens of(BuildContext context) =>
      Theme.of(context).extension<AkribosThemeTokens>() ??
      _tokens(Theme.of(context).brightness, false);

  @override
  AkribosThemeTokens copyWith({
    Color? paper,
    Color? paperDeep,
    Color? surfaceRaised,
    Color? line,
    Color? muted,
    Color? accent,
    Color? accentSoft,
    Color? shadow,
    bool? eInk,
  }) => AkribosThemeTokens(
    paper: paper ?? this.paper,
    paperDeep: paperDeep ?? this.paperDeep,
    surfaceRaised: surfaceRaised ?? this.surfaceRaised,
    line: line ?? this.line,
    muted: muted ?? this.muted,
    accent: accent ?? this.accent,
    accentSoft: accentSoft ?? this.accentSoft,
    shadow: shadow ?? this.shadow,
    eInk: eInk ?? this.eInk,
  );

  @override
  AkribosThemeTokens lerp(AkribosThemeTokens? other, double t) {
    if (other == null) return this;
    return AkribosThemeTokens(
      paper: Color.lerp(paper, other.paper, t)!,
      paperDeep: Color.lerp(paperDeep, other.paperDeep, t)!,
      surfaceRaised: Color.lerp(surfaceRaised, other.surfaceRaised, t)!,
      line: Color.lerp(line, other.line, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentSoft: Color.lerp(accentSoft, other.accentSoft, t)!,
      shadow: Color.lerp(shadow, other.shadow, t)!,
      eInk: t < .5 ? eInk : other.eInk,
    );
  }
}

AkribosThemeTokens _tokens(Brightness brightness, bool eInk) {
  if (eInk) {
    return const AkribosThemeTokens(
      paper: Colors.white,
      paperDeep: Colors.white,
      surfaceRaised: Colors.white,
      line: Colors.black,
      muted: Colors.black,
      accent: Colors.black,
      accentSoft: Color(0xffeeeeee),
      shadow: Colors.transparent,
      eInk: true,
    );
  }
  final dark = brightness == Brightness.dark;
  return AkribosThemeTokens(
    paper: dark ? AkribosColors.darkPaper : AkribosColors.paper,
    paperDeep: dark ? AkribosColors.darkPaperDeep : AkribosColors.paperDeep,
    surfaceRaised: dark ? AkribosColors.darkRaised : AkribosColors.raised,
    line: dark ? const Color(0x1fd6d3d1) : const Color(0x3378716c),
    muted: dark ? const Color(0xffa8a29e) : AkribosColors.muted,
    accent: dark ? AkribosColors.green300 : AkribosColors.green700,
    accentSoft: dark ? const Color(0xff263b27) : const Color(0xffe8f1e3),
    shadow: dark ? const Color(0x30000000) : const Color(0x101c1917),
  );
}

/// Explicit PWA colors and geometry; no generated Material seed palette.
/// Controls use the platform's sans serif. Reading and area headings use the
/// locally bundled Akribos Text; Hebrew retains its bundled fallback.
ThemeData buildAkribosTheme(Brightness brightness, {bool eInk = false}) {
  if (eInk) brightness = Brightness.light;
  final dark = brightness == Brightness.dark;
  final tokens = _tokens(brightness, eInk);
  final ink = eInk
      ? Colors.black
      : dark
      ? const Color(0xfff5f5f4)
      : AkribosColors.ink;
  final surface = eInk
      ? Colors.white
      : dark
      ? AkribosColors.darkSurface
      : AkribosColors.surface;
  final scheme = ColorScheme(
    brightness: brightness,
    primary: eInk
        ? Colors.black
        : dark
        ? AkribosColors.green300
        : AkribosColors.green700,
    onPrimary: dark ? AkribosColors.darkPaper : Colors.white,
    primaryContainer: tokens.accentSoft,
    onPrimaryContainer: tokens.accent,
    secondary: tokens.accent,
    onSecondary: dark ? AkribosColors.darkPaper : Colors.white,
    secondaryContainer: tokens.paperDeep,
    onSecondaryContainer: ink,
    tertiary: tokens.accent,
    onTertiary: dark ? AkribosColors.darkPaper : Colors.white,
    tertiaryContainer: tokens.accentSoft,
    onTertiaryContainer: tokens.accent,
    error: eInk
        ? Colors.black
        : dark
        ? const Color(0xffffb4ab)
        : const Color(0xffa32828),
    onError: dark ? const Color(0xff601410) : Colors.white,
    surface: surface,
    onSurface: ink,
    onSurfaceVariant: tokens.muted,
    outline: tokens.line,
    outlineVariant: tokens.line,
    surfaceTint: Colors.transparent,
    surfaceContainerLowest: tokens.paper,
    surfaceContainerLow: tokens.surfaceRaised,
    surfaceContainer: surface,
    surfaceContainerHigh: tokens.paperDeep,
    surfaceContainerHighest: tokens.paperDeep,
    inverseSurface: dark ? AkribosColors.paper : AkribosColors.ink,
    onInverseSurface: dark ? AkribosColors.ink : AkribosColors.paper,
  );
  final base = ThemeData(brightness: brightness, colorScheme: scheme);
  final sans = base.textTheme.apply(
    bodyColor: ink,
    displayColor: ink,
    fontFamilyFallback: const ['NotoSansHebrew'],
  );
  TextStyle heading(double size) => TextStyle(
    fontFamily: 'AkribosText',
    fontFamilyFallback: const ['NotoSansHebrew'],
    fontSize: size,
    fontWeight: FontWeight.w600,
    height: 1.12,
    letterSpacing: -.45,
    color: ink,
  );
  final border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(9),
    borderSide: BorderSide(color: tokens.line),
  );
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(9));
  final controlText = sans.labelLarge!.copyWith(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
  );
  final control = ButtonStyle(
    minimumSize: const WidgetStatePropertyAll(Size(44, 44)),
    padding: const WidgetStatePropertyAll(
      EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    ),
    shape: WidgetStatePropertyAll(shape),
    textStyle: WidgetStatePropertyAll(controlText),
    elevation: const WidgetStatePropertyAll(0),
    splashFactory: NoSplash.splashFactory,
    animationDuration: eInk ? Duration.zero : const Duration(milliseconds: 120),
  );
  return base.copyWith(
    scaffoldBackgroundColor: tokens.paper,
    extensions: [tokens],
    splashFactory: NoSplash.splashFactory,
    highlightColor: eInk ? Colors.transparent : tokens.accentSoft,
    hoverColor: tokens.accentSoft,
    focusColor: tokens.accentSoft,
    disabledColor: tokens.muted,
    dividerColor: tokens.line,
    textTheme: sans.copyWith(
      displayLarge: heading(48),
      displayMedium: heading(40),
      displaySmall: heading(36),
      headlineLarge: heading(34),
      headlineMedium: heading(30),
      headlineSmall: heading(26),
      titleLarge: sans.titleLarge?.copyWith(
        fontSize: 19,
        fontWeight: FontWeight.w600,
        letterSpacing: -.2,
      ),
      titleMedium: sans.titleMedium?.copyWith(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
      ),
      titleSmall: sans.titleSmall?.copyWith(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
      ),
      bodyLarge: sans.bodyLarge?.copyWith(
        fontSize: 16,
        height: 1.45,
        letterSpacing: 0,
      ),
      bodyMedium: sans.bodyMedium?.copyWith(
        fontSize: 14,
        height: 1.45,
        letterSpacing: 0,
      ),
      bodySmall: sans.bodySmall?.copyWith(
        fontSize: 12,
        height: 1.4,
        color: tokens.muted,
        letterSpacing: 0,
      ),
      labelLarge: controlText.copyWith(color: ink),
      labelMedium: controlText.copyWith(fontSize: 12, color: ink),
      labelSmall: controlText.copyWith(fontSize: 11, color: tokens.muted),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: surface,
      foregroundColor: ink,
      surfaceTintColor: Colors.transparent,
      shadowColor: tokens.shadow,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      toolbarHeight: 58,
      titleSpacing: 16,
      titleTextStyle: heading(28),
      shape: Border(bottom: BorderSide(color: tokens.line)),
      iconTheme: IconThemeData(color: tokens.muted, size: 22),
      actionsIconTheme: IconThemeData(color: tokens.muted, size: 22),
    ),
    cardTheme: CardThemeData(
      color: tokens.surfaceRaised,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      margin: const EdgeInsets.symmetric(vertical: 5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(13),
        side: BorderSide(color: tokens.line),
      ),
    ),
    inputDecorationTheme: InputDecorationThemeData(
      filled: true,
      fillColor: tokens.surfaceRaised,
      border: border,
      enabledBorder: border,
      focusedBorder: border.copyWith(
        borderSide: BorderSide(color: tokens.accent, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 13),
      labelStyle: TextStyle(color: tokens.muted, fontSize: 14),
      floatingLabelStyle: TextStyle(color: tokens.accent, fontSize: 14),
      hintStyle: TextStyle(color: tokens.muted, fontSize: 14),
    ),
    filledButtonTheme: FilledButtonThemeData(style: control),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: control.copyWith(
        backgroundColor: WidgetStatePropertyAll(tokens.surfaceRaised),
        foregroundColor: WidgetStatePropertyAll(tokens.accent),
        side: WidgetStatePropertyAll(BorderSide(color: tokens.line)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: control.copyWith(
        foregroundColor: WidgetStatePropertyAll(ink),
        side: WidgetStatePropertyAll(BorderSide(color: tokens.line)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: control.copyWith(
        foregroundColor: WidgetStatePropertyAll(tokens.accent),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? tokens.muted.withValues(alpha: .5)
              : tokens.muted,
        ),
        shape: WidgetStatePropertyAll(shape),
        minimumSize: const WidgetStatePropertyAll(Size(44, 44)),
        splashFactory: NoSplash.splashFactory,
      ),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: tokens.muted,
      textColor: ink,
      selectedColor: tokens.accent,
      selectedTileColor: tokens.accentSoft,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      shape: shape,
    ),
    chipTheme: ChipThemeData(
      backgroundColor: tokens.paperDeep,
      selectedColor: tokens.accentSoft,
      surfaceTintColor: Colors.transparent,
      labelStyle: TextStyle(
        fontSize: 12,
        color: ink,
        fontWeight: FontWeight.w500,
      ),
      side: BorderSide(color: tokens.line),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: tokens.surfaceRaised,
      surfaceTintColor: Colors.transparent,
      elevation: eInk ? 0 : 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: tokens.line),
      ),
      titleTextStyle: heading(25),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: tokens.surfaceRaised,
      surfaceTintColor: Colors.transparent,
      dragHandleColor: tokens.line,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        side: BorderSide(color: tokens.line),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: tokens.surfaceRaised,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: tokens.line),
      ),
      textStyle: sans.bodyMedium,
      elevation: eInk ? 0 : 4,
    ),
    dividerTheme: DividerThemeData(color: tokens.line, thickness: 1, space: 1),
    tabBarTheme: TabBarThemeData(
      labelColor: tokens.accent,
      unselectedLabelColor: tokens.muted,
      labelStyle: controlText,
      unselectedLabelStyle: controlText,
      indicatorSize: TabBarIndicatorSize.label,
      dividerColor: tokens.line,
      indicatorColor: tokens.accent,
    ),
    pageTransitionsTheme: eInk
        ? const PageTransitionsTheme(
            builders: {
              TargetPlatform.android: _NoPageTransition(),
              TargetPlatform.iOS: _NoPageTransition(),
            },
          )
        : base.pageTransitionsTheme,
  );
}

class _NoPageTransition extends PageTransitionsBuilder {
  const _NoPageTransition();
  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => child;
}
