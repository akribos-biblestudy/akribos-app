import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/akribos_theme.dart';

/// A preview of an already opened resource, using text supplied by its owner.
///
/// Ideal widths are 160–260 logical pixels. A wrap may use the default width of
/// 220; a grid should use [heightFor] for its mainAxisExtent so accessibility
/// text can grow without clipping. This widget neither fetches nor invents text.
class ReaderTabCard extends StatefulWidget {
  const ReaderTabCard({
    super.key,
    required this.title,
    required this.reference,
    required this.previewText,
    required this.resourceKind,
    this.linkSet,
    this.selected = false,
    this.onTap,
    this.trailing,
    this.eInk = false,
  });

  final String title, reference, previewText, resourceKind;
  final String? linkSet;
  final bool selected, eInk;
  final VoidCallback? onTap;
  final Widget? trailing;

  /// The same geometry used inside the card, including nonlinear text scaling.
  static double heightFor(TextScaler textScaler) => math.max(
    188,
    (_headerHeight(textScaler) +
            (textScaler.scale(16) * 1.35 * 3).ceilToDouble() +
            _footerHeight(textScaler) +
            44)
        .ceilToDouble(),
  );

  static double _headerHeight(TextScaler scaler) => math.max(
    48,
    (scaler.scale(13) * 1.15 * 2 + 3 + scaler.scale(10.5) * 1.2)
            .ceilToDouble() +
        2,
  );

  static double _footerHeight(TextScaler scaler) =>
      math.max(24, (scaler.scale(12) * 1.2).ceilToDouble());

  @override
  State<ReaderTabCard> createState() => _ReaderTabCardState();
}

class _ReaderTabCardState extends State<ReaderTabCard> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final tokens = AkribosThemeTokens.of(context);
    final monochrome = widget.eInk || tokens.eInk;
    final scaler = MediaQuery.textScalerOf(context);
    final ink = monochrome
        ? Colors.black
        : Theme.of(context).colorScheme.onSurface;
    final muted = monochrome ? Colors.black : tokens.muted;
    final accent = monochrome ? Colors.black : tokens.accent;
    final (kind, icon) = switch (widget.resourceKind) {
      'bible' => ('Bibel', Icons.menu_book_outlined),
      'commentary' => ('Kommentar', Icons.subject_outlined),
      'lexicon' => ('Lexikon', Icons.book_outlined),
      'xrefs' => ('Parallelstellen', Icons.compare_arrows),
      'morphology' => ('Wortformen', Icons.translate_outlined),
      _ => ('Werk', Icons.library_books_outlined),
    };
    final preview = widget.previewText.trim();
    final group = widget.linkSet?.trim();
    final linked = group != null && group.isNotEmpty;
    final reference = widget.reference.trim();
    final semanticLabel = [
      widget.title,
      kind,
      if (reference.isNotEmpty) reference,
      linked ? 'Tabgruppe $group' : 'Unabhängig',
      if (preview.isNotEmpty) preview,
    ].join(', ');

    return SizedBox(
      width: 220,
      height: ReaderTabCard.heightFor(scaler),
      child: Semantics(
        container: true,
        explicitChildNodes: true,
        child: Stack(
          children: [
            Positioned.fill(
              child: Semantics(
                button: true,
                selected: widget.selected,
                enabled: widget.onTap != null,
                label: semanticLabel,
                onTap: widget.onTap,
                child: ExcludeSemantics(
                  child: FocusableActionDetector(
                    enabled: widget.onTap != null,
                    onShowFocusHighlight: (value) =>
                        setState(() => _focused = value),
                    actions: {
                      ActivateIntent: CallbackAction<ActivateIntent>(
                        onInvoke: (_) {
                          widget.onTap?.call();
                          return null;
                        },
                      ),
                    },
                    mouseCursor: widget.onTap == null
                        ? SystemMouseCursors.basic
                        : SystemMouseCursors.click,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: widget.onTap,
                      child: DecoratedBox(
                        key: const ValueKey('reader-tab-card-paper'),
                        decoration: BoxDecoration(
                          color: monochrome
                              ? Colors.white
                              : tokens.surfaceRaised,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: widget.selected || _focused
                                ? accent
                                : monochrome
                                ? Colors.black
                                : tokens.line,
                            width: widget.selected || _focused ? 2 : 1,
                          ),
                          boxShadow: monochrome
                              ? const []
                              : [
                                  BoxShadow(
                                    color: tokens.shadow,
                                    blurRadius: 7,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              SizedBox(
                                height: ReaderTabCard._headerHeight(scaler),
                                child: Padding(
                                  padding: EdgeInsetsDirectional.only(
                                    end: widget.trailing == null ? 0 : 42,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        widget.title,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: ink,
                                          fontSize: 13,
                                          height: 1.15,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Row(
                                        children: [
                                          Icon(icon, size: 12, color: muted),
                                          const SizedBox(width: 4),
                                          Expanded(
                                            child: Text(
                                              kind,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                color: muted,
                                                fontSize: 10.5,
                                                height: 1.2,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Expanded(
                                child: Text(
                                  preview.isEmpty
                                      ? 'Noch kein Textauszug geladen.'
                                      : preview,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: preview.isEmpty ? muted : ink,
                                    fontFamily: 'AkribosText',
                                    fontFamilyFallback: const [
                                      'NotoSansHebrew',
                                    ],
                                    fontSize: 16,
                                    height: 1.35,
                                    fontStyle: preview.isEmpty
                                        ? FontStyle.italic
                                        : FontStyle.normal,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 11),
                              SizedBox(
                                height: 1,
                                child: ColoredBox(
                                  color: monochrome
                                      ? Colors.black
                                      : tokens.line,
                                ),
                              ),
                              SizedBox(
                                height: ReaderTabCard._footerHeight(scaler),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        reference.isEmpty ? kind : reference,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: widget.selected ? accent : ink,
                                          fontSize: 12,
                                          height: 1.2,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Icon(
                                      linked ? Icons.link : Icons.link_off,
                                      size: 13,
                                      color: muted,
                                    ),
                                    if (linked) ...[
                                      const SizedBox(width: 3),
                                      Text(
                                        group,
                                        style: TextStyle(
                                          color: muted,
                                          fontSize: 12,
                                          height: 1.2,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (widget.trailing != null)
              PositionedDirectional(
                top: 4,
                end: 4,
                width: 48,
                height: 48,
                child: widget.trailing!,
              ),
          ],
        ),
      ),
    );
  }
}
