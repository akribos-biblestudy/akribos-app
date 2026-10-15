import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/akribos_theme.dart';

@immutable
class FloatingNavigationDestination {
  const FloatingNavigationDestination({
    required this.label,
    required this.icon,
    this.selectedIcon,
    this.semanticLabel,
  });

  final String label;
  final Widget icon;
  final Widget? selectedIcon;
  final String? semanticLabel;
}

/// A compact, inset destination bar for phone and tablet windows.
///
/// Use as Scaffold.bottomNavigationBar; the surrounding paper remains visible
/// through the outer margins. SafeArea protects the home indicator, while the
/// body remains above the bar. The surface is opaque to avoid filtering live
/// scrolling text beneath it.
/// No navigation occurs internally: the owner can flush edits before switching.
class FloatingNavigationBar extends StatelessWidget {
  const FloatingNavigationBar({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
    this.eInk = false,
    this.hideWhenKeyboardOpen = true,
    this.maxWidth = 560,
  }) : assert(destinations.length >= 4 && destinations.length <= 5),
       assert(selectedIndex >= 0 && selectedIndex < destinations.length),
       assert(maxWidth >= 280);

  final List<FloatingNavigationDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int>? onSelected;
  final bool eInk;
  final bool hideWhenKeyboardOpen;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    if (hideWhenKeyboardOpen && media.viewInsets.bottom > 0) {
      return const SizedBox.shrink();
    }
    final tokens = AkribosThemeTokens.of(context);
    final monochrome = eInk || tokens.eInk;
    final still = monochrome || media.disableAnimations;
    final highContrast = monochrome || media.highContrast;
    final duration = still ? Duration.zero : const Duration(milliseconds: 160);
    final foreground = monochrome ? Colors.black : tokens.accent;
    final background = monochrome ? Colors.white : tokens.surfaceRaised;
    const labelStyle = TextStyle(
      fontSize: 11,
      height: 1.15,
      fontWeight: FontWeight.w600,
      letterSpacing: 0,
    );

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
        child: Align(
          alignment: Alignment.bottomCenter,
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final cellWidth =
                    (constraints.maxWidth - 12) / destinations.length;
                double labelHeight = 0;
                for (final destination in destinations) {
                  final painter = TextPainter(
                    text: TextSpan(text: destination.label, style: labelStyle),
                    textDirection: Directionality.of(context),
                    textScaler: media.textScaler,
                    maxLines: 2,
                    ellipsis: '…',
                  )..layout(maxWidth: math.max(1, cellWidth - 8));
                  labelHeight = math.max(labelHeight, painter.height);
                  painter.dispose();
                }
                final height = math.max(60.0, labelHeight + 46);
                final radius = BorderRadius.circular(26);
                final surface = DecoratedBox(
                  decoration: BoxDecoration(
                    color: background,
                    border: Border.all(
                      color: highContrast
                          ? Theme.of(context).colorScheme.onSurface
                          : tokens.line,
                      width: highContrast ? 1.5 : 1,
                    ),
                    borderRadius: radius,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(5),
                    child: Row(
                      children: [
                        for (
                          var index = 0;
                          index < destinations.length;
                          index++
                        )
                          Expanded(
                            child: _DestinationButton(
                              destination: destinations[index],
                              selected: selectedIndex == index,
                              onPressed: onSelected == null
                                  ? null
                                  : () => onSelected!(index),
                              height: height,
                              foreground: foreground,
                              muted: monochrome ? Colors.black : tokens.muted,
                              selectedBackground: monochrome
                                  ? const Color(0xffeeeeee)
                                  : tokens.accentSoft,
                              highContrast: highContrast,
                              duration: duration,
                              labelStyle: labelStyle,
                            ),
                          ),
                      ],
                    ),
                  ),
                );
                return DecoratedBox(
                  key: const ValueKey('floating-navigation-surface'),
                  decoration: BoxDecoration(
                    borderRadius: radius,
                    boxShadow: monochrome
                        ? const []
                        : [
                            BoxShadow(
                              color: tokens.shadow,
                              blurRadius: 24,
                              offset: const Offset(0, 6),
                            ),
                            BoxShadow(
                              color: tokens.shadow,
                              blurRadius: 2,
                              offset: const Offset(0, 1),
                            ),
                          ],
                  ),
                  child: FocusTraversalGroup(child: surface),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _DestinationButton extends StatefulWidget {
  const _DestinationButton({
    required this.destination,
    required this.selected,
    required this.onPressed,
    required this.height,
    required this.foreground,
    required this.muted,
    required this.selectedBackground,
    required this.highContrast,
    required this.duration,
    required this.labelStyle,
  });
  final FloatingNavigationDestination destination;
  final bool selected, highContrast;
  final VoidCallback? onPressed;
  final double height;
  final Color foreground, muted, selectedBackground;
  final Duration duration;
  final TextStyle labelStyle;
  @override
  State<_DestinationButton> createState() => _DestinationButtonState();
}

class _DestinationButtonState extends State<_DestinationButton> {
  bool _focused = false, _pressed = false;
  @override
  Widget build(BuildContext context) {
    final color = widget.selected ? widget.foreground : widget.muted;
    final borderVisible = _focused || (widget.highContrast && widget.selected);
    return Semantics(
      key: ValueKey('navigation-${widget.destination.label}'),
      container: true,
      button: true,
      selected: widget.selected,
      enabled: widget.onPressed != null,
      label: widget.destination.semanticLabel ?? widget.destination.label,
      onTap: widget.onPressed,
      child: ExcludeSemantics(
        child: Tooltip(
          message: widget.destination.semanticLabel ?? widget.destination.label,
          child: FocusableActionDetector(
            enabled: widget.onPressed != null,
            onShowFocusHighlight: (value) => setState(() => _focused = value),
            actions: {
              ActivateIntent: CallbackAction<ActivateIntent>(
                onInvoke: (_) {
                  widget.onPressed?.call();
                  return null;
                },
              ),
            },
            mouseCursor: widget.onPressed == null
                ? SystemMouseCursors.basic
                : SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onPressed,
              onTapDown: widget.onPressed == null
                  ? null
                  : (_) => setState(() => _pressed = true),
              onTapUp: (_) => setState(() => _pressed = false),
              onTapCancel: () => setState(() => _pressed = false),
              child: AnimatedContainer(
                duration: widget.duration,
                height: widget.height,
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 7),
                decoration: BoxDecoration(
                  color: widget.selected || _pressed
                      ? widget.selectedBackground
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: borderVisible
                        ? widget.foreground
                        : Colors.transparent,
                    width: 1.5,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconTheme(
                      data: IconThemeData(size: 23, color: color),
                      child: widget.selected
                          ? widget.destination.selectedIcon ??
                                widget.destination.icon
                          : widget.destination.icon,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.destination.label,
                      maxLines: 2,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: widget.labelStyle.copyWith(color: color),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
