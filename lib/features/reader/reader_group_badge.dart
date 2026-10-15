import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/akribos_theme.dart';

/// Shared with ReaderTabToolbar.svelte and ReaderResourceTabs.svelte in the web
/// portal. Fills are the latter's `color-mix(in oklab, --link-color 78%,
/// --surface)`, converted to 8-bit sRGB for #fffefa / #171c18 respectively.
abstract final class ReaderLinkGroupColors {
  static const base = {
    'A': Color(0xffb9683f),
    'B': Color(0xff55759b),
    'C': Color(0xff60836d),
    'D': Color(0xff776b91),
    'E': Color(0xff9a6572),
  };

  static const _light = {
    'A': Color(0xffca8968),
    'B': Color(0xff7892b0),
    'C': Color(0xff829d8a),
    'D': Color(0xff938aa8),
    'E': Color(0xffb1858e),
  };

  static const _dark = {
    'A': Color(0xff925737),
    'B': Color(0xff46607c),
    'C': Color(0xff4f6a59),
    'D': Color(0xff605874),
    'E': Color(0xff7b545d),
  };

  static Color? baseColor(String? linkSet) => base[linkSet];

  static Color? backgroundColor(String? linkSet, Brightness brightness) =>
      (brightness == Brightness.dark ? _dark : _light)[linkSet];
}

/// A compact, noninteractive group label. The enclosing button/menu owns taps
/// and its touch target; a badge can also stand alone as tab metadata.
/// The letter is always visible, and an unlinked tab explicitly says "Keine".
class ReaderGroupBadge extends StatelessWidget {
  const ReaderGroupBadge({
    super.key,
    this.linkSet,
    this.selected = false,
    this.eInk = false,
  });

  final String? linkSet;
  final bool selected, eInk;

  static double heightFor(TextScaler scaler, {int maxLines = 1}) =>
      math.max(24, (scaler.scale(12) * 1.1 * maxLines).ceilToDouble() + 8);

  @override
  Widget build(BuildContext context) {
    final tokens = AkribosThemeTokens.of(context);
    final monochrome = eInk || tokens.eInk;
    final brightness = Theme.of(context).brightness;
    final group = ReaderLinkGroupColors.base.containsKey(linkSet)
        ? linkSet
        : null;
    final label = group ?? 'Keine';
    final dark = brightness == Brightness.dark;
    final fill = monochrome
        ? Colors.white
        : ReaderLinkGroupColors.backgroundColor(group, brightness) ??
              tokens.surfaceRaised;
    // The web mixes lighten the daytime fills. Black text preserves the exact
    // group color while meeting small-text contrast, unlike white on that fill.
    final ink = monochrome || !dark ? Colors.black : Colors.white;
    final border = monochrome || selected
        ? ink
        : ReaderLinkGroupColors.baseColor(group) ?? tokens.line;

    return Semantics(
      label: group == null ? 'Tabgruppe Keine, unabhängig' : 'Tabgruppe $group',
      selected: selected ? true : null,
      child: ExcludeSemantics(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minWidth: 24,
            minHeight: heightFor(MediaQuery.textScalerOf(context)),
          ),
          child: DecoratedBox(
            key: ValueKey('reader-group-badge-$label'),
            decoration: BoxDecoration(
              color: fill,
              border: Border.all(color: border, width: selected ? 2 : 1),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall!.copyWith(
                  color: ink,
                  fontSize: 12,
                  height: 1.1,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
