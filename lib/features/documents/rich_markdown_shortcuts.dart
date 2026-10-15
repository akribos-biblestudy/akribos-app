// Quill's shortcut configuration is experimental in the pinned 11.6.0 API.
// ignore_for_file: experimental_member_use

import 'package:flutter/widgets.dart';
import 'package:flutter_quill/flutter_quill.dart' as q;
import 'package:flutter_quill/quill_delta.dart';

/// Markdown block prefixes for hardware and native software keyboards.
///
/// Quill 11.6's SpaceShortcutEvent runs only for a hardware KeyDownEvent. Its
/// standard handlers also omit readOnly/composition checks. Reuse that event
/// interface with guarded handlers and use the public editor input value to
/// recognize a single space arriving through the native TextInputClient.
/// A document listener cannot distinguish typing from loads, undo or paste.
class RichMarkdownShortcuts {
  RichMarkdownShortcuts({
    required this.controller,
    required this.editorKey,
    required this.focusNode,
  }) {
    _previous = controller.onReplaceText;
    _replacement = _replace;
    controller.onReplaceText = _replacement;
    spaceEvents = List.unmodifiable([
      for (final entry in _prefixes.entries)
        q.SpaceShortcutEvent(
          character: entry.key,
          handler: (_, _) => _hardwareSpace(entry.key, entry.value),
        ),
    ]);
  }

  final q.QuillController controller;
  final GlobalKey<q.EditorState> editorKey;
  final FocusNode focusNode;
  late final List<q.SpaceShortcutEvent> spaceEvents;
  late final q.ReplaceTextCallback? _previous;
  late final q.ReplaceTextCallback _replacement;
  bool _applying = false;
  bool _disposed = false;

  static const _prefixes = <String, Map<String, Object>>{
    '#': {'header': 1},
    '##': {'header': 2},
    '###': {'header': 3},
    '####': {'header': 4},
    '#####': {'header': 5},
    '######': {'header': 6},
    '-': {'list': 'bullet'},
    '*': {'list': 'bullet'},
    '+': {'list': 'bullet'},
    '1.': {'list': 'ordered'},
    '>': {'blockquote': true},
  };

  q.QuillRawEditorState? get _editor {
    final state = editorKey.currentState;
    return state is q.QuillRawEditorState ? state : null;
  }

  bool get _canType {
    if (_disposed || _applying || controller.readOnly || !focusNode.hasFocus) {
      return false;
    }
    final value = _editor?.currentTextEditingValue;
    return value != null &&
        (!value.composing.isValid || value.composing.isCollapsed) &&
        controller.selection.isValid &&
        controller.selection.isCollapsed;
  }

  q.Line? _prefixLine(String prefix) {
    if (!_canType) return null;
    final index = controller.selection.baseOffset;
    final node = controller.document.queryChild(index).node;
    if (node is! q.Line ||
        node.toPlainText() != '$prefix\n' ||
        index != node.documentOffset + prefix.length) {
      return null;
    }
    final style = controller.getSelectionStyle().attributes;
    // Existing block/inline code remains literal. In a list, only Enter/Tab and
    // the explicit block menu change structure; a typed marker stays text.
    if ([
      'header',
      'list',
      'blockquote',
      'code-block',
      'code',
    ].any((key) => style[key]?.value != null)) {
      return null;
    }
    return node;
  }

  bool _replace(int index, int length, Object? data) {
    if (_applying) return true;
    if (_previous?.call(index, length, data) == false) return false;
    if (length != 0 || data != ' ' || !_canType) return true;
    if (index != controller.selection.baseOffset) return true;
    final value = _editor!.currentTextEditingValue!;
    // Native input updates this value before calling replaceText. Programmatic
    // insertion and the clipboard toolbar do not. Multi-character IME/paste
    // updates are deliberately left as literal text.
    final current = controller.document.toPlainText();
    if (!value.selection.isCollapsed ||
        value.selection.baseOffset != index + 1 ||
        value.text != current.replaceRange(index, index, ' ')) {
      return true;
    }
    for (final entry in _prefixes.entries) {
      final line = _prefixLine(entry.key);
      if (line != null) {
        _apply(line, entry.key, entry.value);
        return false;
      }
    }
    return true;
  }

  bool _hardwareSpace(String prefix, Map<String, Object> attributes) {
    final line = _prefixLine(prefix);
    if (line == null ||
        _previous?.call(controller.selection.baseOffset, 0, ' ') == false) {
      return false;
    }
    _apply(line, prefix, attributes);
    return true;
  }

  void _apply(q.Line line, String prefix, Map<String, Object> attributes) {
    final start = line.documentOffset;
    _applying = true;
    try {
      // Record the literal keystroke first. One Undo of the separate atomic
      // conversion restores the exact marker plus space, without retriggering.
      controller.replaceText(
        start + prefix.length,
        0,
        ' ',
        TextSelection.collapsed(offset: start + prefix.length + 1),
      );
      controller.document.history.lastRecorded = 0;
      controller.compose(
        Delta()
          ..retain(start)
          ..delete(prefix.length + 1)
          ..retain(1, attributes),
        TextSelection.collapsed(offset: start),
        q.ChangeSource.local,
      );
      controller.document.history.lastRecorded = 0;
    } finally {
      _applying = false;
    }
  }

  void dispose() {
    _disposed = true;
    if (controller.onReplaceText == _replacement) {
      controller.onReplaceText = _previous;
    }
  }
}
