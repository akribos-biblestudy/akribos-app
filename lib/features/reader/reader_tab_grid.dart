import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

/// Long-press dragging keeps the visual card overview and scrolls at its edges.
/// The final plus card is a drop target for moving a tab to the end, never a tab.
class ReaderTabGrid extends StatefulWidget {
  const ReaderTabGrid({
    super.key,
    required this.ids,
    required this.cards,
    required this.addCard,
    required this.columns,
    required this.cardHeight,
    required this.onMove,
    this.enabled = true,
  });

  final List<String> ids;
  final List<Widget> cards;
  final Widget addCard;
  final int columns;
  final double cardHeight;
  final bool enabled;
  final Future<void> Function(String, int) onMove;

  @override
  State<ReaderTabGrid> createState() => _ReaderTabGridState();
}

class _ReaderTabGridState extends State<ReaderTabGrid> {
  final _scroll = ScrollController();
  final _viewport = GlobalKey();
  Timer? _autoScroll;
  Offset? _pointer;

  void _stopScroll() {
    _pointer = null;
    _autoScroll?.cancel();
    _autoScroll = null;
  }

  void _dragUpdate(DragUpdateDetails details) {
    _pointer = details.globalPosition;
    _autoScroll ??= Timer.periodic(const Duration(milliseconds: 40), (_) {
      final box = _viewport.currentContext?.findRenderObject();
      if (box is! RenderBox || !_scroll.hasClients || _pointer == null) return;
      final y = box.globalToLocal(_pointer!).dy;
      final delta = y < 56
          ? -18.0
          : y > box.size.height - 56
          ? 18.0
          : 0.0;
      if (delta != 0) {
        _scroll.jumpTo(
          (_scroll.offset + delta).clamp(
            _scroll.position.minScrollExtent,
            _scroll.position.maxScrollExtent,
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _stopScroll();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final cardWidth =
          (constraints.maxWidth - 32 - (widget.columns - 1) * 12) /
          widget.columns;
      return GridView.builder(
        key: _viewport,
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: widget.columns,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          mainAxisExtent: widget.cardHeight,
        ),
        itemCount: widget.cards.length + 1,
        itemBuilder: (context, index) {
          final isAdd = index == widget.cards.length;
          final child = isAdd ? widget.addCard : widget.cards[index];
          final id = isAdd ? '' : widget.ids[index];
          return DragTarget<String>(
            key: ValueKey('reader-tab-drop:${isAdd ? 'end' : id}'),
            onWillAcceptWithDetails: (details) =>
                widget.enabled && details.data != id,
            onAcceptWithDetails: (details) {
              _stopScroll();
              unawaited(widget.onMove(details.data, index));
            },
            builder: (context, candidates, _) {
              final target = DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: candidates.isEmpty
                      ? null
                      : Border.all(
                          color: Theme.of(context).colorScheme.onSurface,
                          width: 3,
                        ),
                ),
                child: child,
              );
              if (isAdd || !widget.enabled) return target;
              return Semantics(
                customSemanticsActions: {
                  if (index > 0)
                    const CustomSemanticsAction(label: 'Tab nach vorne'): () =>
                        unawaited(widget.onMove(id, index - 1)),
                  if (index < widget.cards.length - 1)
                    const CustomSemanticsAction(label: 'Tab nach hinten'): () =>
                        unawaited(widget.onMove(id, index + 1)),
                },
                child: LongPressDraggable<String>(
                  data: id,
                  onDragUpdate: _dragUpdate,
                  onDragEnd: (_) => _stopScroll(),
                  onDraggableCanceled: (_, _) => _stopScroll(),
                  feedback: Material(
                    color: Colors.transparent,
                    child: SizedBox(
                      width: cardWidth,
                      height: widget.cardHeight,
                      child: child,
                    ),
                  ),
                  childWhenDragging: Opacity(opacity: .35, child: target),
                  child: target,
                ),
              );
            },
          );
        },
      );
    },
  );
}
