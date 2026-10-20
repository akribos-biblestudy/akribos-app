import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Keeps long linked reading paragraphs accessible without a flat semantics
/// sibling list. Flutter's spatial traversal sort runs before its ordinal sort;
/// thousands of word links in one list make that work expensive on every scroll.
class ReaderRichText extends RichText {
  ReaderRichText({
    super.key,
    required super.text,
    super.textAlign,
    super.textDirection,
    super.softWrap,
    super.overflow,
    super.textScaler,
    super.maxLines,
    super.locale,
    super.strutStyle,
    super.textWidthBasis,
    super.textHeightBehavior,
    super.selectionRegistrar,
    super.selectionColor,
  });

  @override
  RenderReaderParagraph createRenderObject(BuildContext context) =>
      RenderReaderParagraph(
        text,
        textAlign: textAlign,
        textDirection: textDirection ?? Directionality.of(context),
        softWrap: softWrap,
        overflow: overflow,
        textScaler: textScaler,
        maxLines: maxLines,
        locale: locale ?? Localizations.maybeLocaleOf(context),
        strutStyle: strutStyle,
        textWidthBasis: textWidthBasis,
        textHeightBehavior: textHeightBehavior,
        registrar: selectionRegistrar,
        selectionColor: selectionColor,
        devicePixelRatio:
            MediaQuery.maybeDevicePixelRatioOf(context) ??
            View.maybeOf(context)?.devicePixelRatio ??
            1,
      );
}

/// Only the hierarchy changes. RenderParagraph still creates every original
/// label, link action, glyph rectangle, visibility flag and show-on-screen action.
class RenderReaderParagraph extends RenderParagraph {
  RenderReaderParagraph(
    super.text, {
    super.textAlign,
    required super.textDirection,
    super.softWrap,
    super.overflow,
    super.textScaler,
    super.maxLines,
    super.locale,
    super.strutStyle,
    super.textWidthBasis,
    super.textHeightBehavior,
    super.registrar,
    super.selectionColor,
    super.devicePixelRatio,
  });

  static const maxSemanticsChildren = 32;

  // Stable structural nodes, indexed by level and position. Higher levels are
  // needed when even the first layer of groups exceeds the sibling limit.
  final _groups = <List<SemanticsNode>>[];

  void _emptyGroups() {
    for (final level in _groups) {
      for (final group in level) {
        // Release the previous parents before RenderParagraph reuses its native
        // leaf nodes. No semantics update is submitted during this assembly.
        group.updateWith(config: null);
      }
    }
  }

  @override
  void assembleSemanticsNode(
    SemanticsNode node,
    SemanticsConfiguration config,
    Iterable<SemanticsNode> children,
  ) {
    _emptyGroups();
    super.assembleSemanticsNode(node, config, children);
    var current = <SemanticsNode>[];
    node.visitChildren((child) {
      current.add(child);
      return true;
    });
    if (current.length <= maxSemanticsChildren) {
      _groups.clear();
      return;
    }

    var levelIndex = 0;
    while (current.length > maxSemanticsChildren) {
      if (_groups.length == levelIndex) _groups.add([]);
      final level = _groups[levelIndex];
      final next = <SemanticsNode>[];
      for (
        var start = 0;
        start < current.length;
        start += maxSemanticsChildren
      ) {
        final end = (start + maxSemanticsChildren).clamp(0, current.length);
        final members = current.sublist(start, end);
        final groupIndex = next.length;
        if (level.length == groupIndex) {
          level.add(
            SemanticsNode(
              key: ValueKey('reader-semantics:$levelIndex:$groupIndex'),
            ),
          );
        }
        final group = level[groupIndex];
        Rect? bounds;
        for (final member in members) {
          final transform = member.transform;
          final rect = transform == null
              ? member.rect
              : MatrixUtils.transformRect(transform, member.rect);
          bounds = bounds == null ? rect : bounds.expandToInclude(rect);
        }
        group
          // Rectangles remain in paragraph coordinates. A group's bounding box
          // is not a translation; native leaf rectangles must stay unchanged for
          // RenderParagraph's existing show-on-screen closures.
          ..transform = null
          ..rect = bounds!
          ..parentPaintClipRect = node.parentPaintClipRect
          ..parentSemanticsClipRect = node.parentSemanticsClipRect
          ..updateWith(
            config: SemanticsConfiguration()
              ..isSemanticBoundary = true
              ..explicitChildNodes = true
              ..textDirection = textDirection
              ..sortKey = OrdinalSortKey(groupIndex.toDouble()),
            childrenInInversePaintOrder: members,
          );
        next.add(group);
      }
      if (level.length > next.length) {
        level.removeRange(next.length, level.length);
      }
      current = next;
      levelIndex++;
    }
    if (_groups.length > levelIndex) {
      _groups.removeRange(levelIndex, _groups.length);
    }
    node.updateWith(config: config, childrenInInversePaintOrder: current);
  }

  @override
  void clearSemantics() {
    // The owner may already have disposed its node registry. Like
    // RenderParagraph's native node cache, only release our references here;
    // changing parent/child links would try to detach from that disposed owner.
    _groups.clear();
    super.clearSemantics();
  }

  @override
  void dispose() {
    _groups.clear();
    super.dispose();
  }
}
