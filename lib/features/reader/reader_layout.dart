import 'package:flutter/material.dart';

import '../../core/json.dart';

List<double> readerTrackSizes(Json workspace, String axis, int count) {
  final stored = asMap(
    asMap(workspace['layoutSizes'])[workspace['layout']],
  )[axis];
  if (stored is List &&
      stored.length == count &&
      stored.every((value) => value is num && value > 0)) {
    final sum = stored.fold<double>(
      0,
      (sum, value) => sum + (value as num).toDouble(),
    );
    return stored.map((value) => (value as num).toDouble() / sum).toList();
  }
  return List.filled(count, 1 / count);
}

class ReaderSplit extends StatefulWidget {
  const ReaderSplit({
    super.key,
    required this.axis,
    required this.weights,
    required this.children,
    required this.onResize,
  });
  final Axis axis;
  final List<double> weights;
  final List<Widget> children;
  final void Function(List<double>)? onResize;
  @override
  State<ReaderSplit> createState() => _ReaderSplitState();
}

class _ReaderSplitState extends State<ReaderSplit> {
  late List<double> _weights = List.of(widget.weights);
  bool _dragging = false;
  @override
  void didUpdateWidget(ReaderSplit oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_dragging || oldWidget.children.length != widget.children.length) {
      _weights = List.of(widget.weights);
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final horizontal = widget.axis == Axis.horizontal;
      final extent =
          (horizontal ? constraints.maxWidth : constraints.maxHeight) -
          (widget.children.length - 1) * 12;
      void drag(int index, double delta) {
        if (extent <= 0) return;
        final pair = _weights[index] + _weights[index + 1];
        final minimum = pair < .24 ? pair / 2 : .12;
        final left = (_weights[index] + delta / extent)
            .clamp(minimum, pair - minimum)
            .toDouble();
        setState(() {
          _weights[index] = left;
          _weights[index + 1] = pair - left;
        });
      }

      return Flex(
        direction: widget.axis,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var index = 0; index < widget.children.length; index++) ...[
            Expanded(
              flex: (_weights[index] * 10000).round().clamp(1, 10000),
              child: widget.children[index],
            ),
            if (index < widget.children.length - 1)
              Semantics(
                label: 'Kachelgröße ändern',
                onIncrease: widget.onResize == null
                    ? null
                    : () {
                        drag(index, extent * .05);
                        widget.onResize!(_weights);
                      },
                onDecrease: widget.onResize == null
                    ? null
                    : () {
                        drag(index, -extent * .05);
                        widget.onResize!(_weights);
                      },
                child: MouseRegion(
                  cursor: horizontal
                      ? SystemMouseCursors.resizeColumn
                      : SystemMouseCursors.resizeRow,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onHorizontalDragStart: horizontal && widget.onResize != null
                        ? (_) => _dragging = true
                        : null,
                    onHorizontalDragUpdate:
                        horizontal && widget.onResize != null
                        ? (event) => drag(index, event.delta.dx)
                        : null,
                    onHorizontalDragEnd: horizontal && widget.onResize != null
                        ? (_) {
                            _dragging = false;
                            widget.onResize!(_weights);
                          }
                        : null,
                    onVerticalDragStart: !horizontal && widget.onResize != null
                        ? (_) => _dragging = true
                        : null,
                    onVerticalDragUpdate: !horizontal && widget.onResize != null
                        ? (event) => drag(index, event.delta.dy)
                        : null,
                    onVerticalDragEnd: !horizontal && widget.onResize != null
                        ? (_) {
                            _dragging = false;
                            widget.onResize!(_weights);
                          }
                        : null,
                    child: SizedBox(
                      width: horizontal ? 12 : null,
                      height: horizontal ? null : 12,
                      child: Center(
                        child: Container(
                          width: horizontal ? 3 : 34,
                          height: horizontal ? 34 : 3,
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.outlineVariant,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ],
      );
    },
  );
}
