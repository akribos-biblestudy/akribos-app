import 'package:flutter/gestures.dart';
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

/// Native RenderParagraph creates the accessible text leaves and their actions.
/// Bounded groups and incremental clip updates keep unchanged leaves attached
/// without retransmitting them during scrolling.
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
  _SemanticsChildrenCollector? _collector;
  SemanticsNode? _semanticsRoot;
  List<SemanticsNode> _rootChildren = const [];
  List<_NativeSemanticsLeaf>? _nativeLeaves;

  @override
  void assembleSemanticsNode(
    SemanticsNode node,
    SemanticsConfiguration config,
    Iterable<SemanticsNode> children,
  ) {
    final leaves = _nativeLeaves;
    if (identical(node, _semanticsRoot) &&
        leaves != null &&
        children.isEmpty &&
        leaves.every((leaf) => leaf.callbackUnchanged)) {
      // Scrolling changes the inherited clip, not text geometry or actions.
      // Native assembly also replaces every OrdinalSortKey, which dirties and
      // retransmits even unchanged words. Keep its nodes and configurations,
      // updating only words that have actually entered or left the paint clip.
      final clip = node.parentPaintClipRect;
      for (final leaf in leaves) {
        final hidden =
            clip != null &&
            clip.intersect(leaf.node.rect).isEmpty &&
            !leaf.node.rect.isEmpty;
        if (leaf.config.isHidden != hidden) {
          leaf.config.isHidden = hidden;
          leaf.node.updateWith(config: leaf.config);
        }
      }
      for (final level in _groups) {
        for (final group in level) {
          group
            ..parentPaintClipRect = node.parentPaintClipRect
            ..parentSemanticsClipRect = node.parentSemanticsClipRect;
        }
      }
      node.updateWith(
        config: config,
        childrenInInversePaintOrder: _rootChildren,
      );
      return;
    }

    final collector = _collector ??= _SemanticsChildrenCollector();
    collector
      ..rect = node.rect
      ..transform = node.transform
      ..parentPaintClipRect = node.parentPaintClipRect
      ..parentSemanticsClipRect = node.parentSemanticsClipRect;
    super.assembleSemanticsNode(collector, config, children);
    var current = collector.takeChildren();
    _nativeLeaves = children.isEmpty ? _cacheNativeLeaves(current) : null;
    _semanticsRoot = node;
    if (current.length <= maxSemanticsChildren) {
      _groups.clear();
      _rootChildren = current;
      node.updateWith(config: config, childrenInInversePaintOrder: current);
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
              ..sortKey =
                  group.sortKey ?? OrdinalSortKey(groupIndex.toDouble()),
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
    _rootChildren = current;
    node.updateWith(config: config, childrenInInversePaintOrder: current);
  }

  List<_NativeSemanticsLeaf>? _cacheNativeLeaves(List<SemanticsNode> nodes) {
    final infos = combineSemanticsInfo(text.getSemanticsInformation());
    if (infos.any((info) => info.isPlaceholder)) return null;
    final leaves = <_NativeSemanticsLeaf>[];
    var offset = 0;
    for (final info in infos) {
      final selection = TextSelection(
        baseOffset: offset,
        extentOffset: offset + info.text.length,
      );
      offset = selection.extentOffset;
      // Native RenderParagraph skips ranges without glyph boxes. Match that
      // mapping once after layout/content changes, never on ordinary scrolling.
      if (getBoxesForSelection(selection).isEmpty) continue;
      if (leaves.length == nodes.length) return null;
      final node = nodes[leaves.length];
      if (node.attributedLabel.string != (info.semanticsLabel ?? info.text) ||
          node.identifier != (info.semanticsIdentifier ?? '') ||
          node.hasChildren) {
        return null;
      }
      // These are precisely the fields native RenderParagraph assigns to a
      // text leaf. Keep its actual attributed label, direction and sort key;
      // geometry, identity and its private showOnScreen callback stay native.
      // Compatibility tests compare these fields/actions with native assembly;
      // placeholders or an unexpected node mapping use native assembly instead.
      final config = SemanticsConfiguration()
        ..attributedLabel = node.attributedLabel
        ..identifier = node.identifier
        ..textDirection = node.textDirection
        ..sortKey = node.sortKey
        ..isLink = node.flagsCollection.isLink
        ..isHidden = node.flagsCollection.isHidden;
      VoidCallback? action;
      switch (info.recognizer) {
        case TapGestureRecognizer(onTap: final handler):
        case DoubleTapGestureRecognizer(onDoubleTap: final handler):
          action = handler;
          if (handler != null) config.onTap = handler;
        case LongPressGestureRecognizer(onLongPress: final handler):
          action = handler;
          if (handler != null) config.onLongPress = handler;
        case null:
          break;
        default:
          return null;
      }
      leaves.add(_NativeSemanticsLeaf(node, config, info.recognizer, action));
    }
    return leaves.length == nodes.length ? leaves : null;
  }

  @override
  void markNeedsSemanticsUpdate() {
    _nativeLeaves = null;
    super.markNeedsSemanticsUpdate();
  }

  @override
  void performLayout() {
    _nativeLeaves = null;
    super.performLayout();
  }

  void _clearSemanticsCache() {
    _groups.clear();
    _collector = null;
    _semanticsRoot = null;
    _rootChildren = const [];
    _nativeLeaves = null;
  }

  @override
  void clearSemantics() {
    // The owner may already have disposed its node registry. Like
    // RenderParagraph's native node cache, only release our references here;
    // changing parent/child links would try to detach from that disposed owner.
    _clearSemanticsCache();
    super.clearSemantics();
  }

  @override
  void dispose() {
    _clearSemanticsCache();
    super.dispose();
  }
}

/// Lets native RenderParagraph update its own cached leaves without temporarily
/// reparenting them to a flat root. Detaching them would mark every word dirty.
/// This collector never joins the semantics tree or submits a platform update.
class _SemanticsChildrenCollector extends SemanticsNode {
  List<SemanticsNode> _children = const [];

  @override
  void updateWith({
    required SemanticsConfiguration? config,
    List<SemanticsNode>? childrenInInversePaintOrder,
  }) {
    _children = childrenInInversePaintOrder ?? const [];
  }

  List<SemanticsNode> takeChildren() {
    final children = _children;
    _children = const [];
    return children;
  }
}

class _NativeSemanticsLeaf {
  const _NativeSemanticsLeaf(
    this.node,
    this.config,
    this.recognizer,
    this.action,
  );

  final SemanticsNode node;
  final SemanticsConfiguration config;
  final GestureRecognizer? recognizer;
  final VoidCallback? action;

  // Recognizers are mutable even when their containing TextSpan is unchanged.
  // Rebuild from native semantics when a callback changes or becomes null.
  bool get callbackUnchanged => identical(action, switch (recognizer) {
    TapGestureRecognizer(onTap: final handler) => handler,
    DoubleTapGestureRecognizer(onDoubleTap: final handler) => handler,
    LongPressGestureRecognizer(onLongPress: final handler) => handler,
    _ => null,
  });
}
