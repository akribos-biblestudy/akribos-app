import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/json.dart';
import 'reader_companion.dart';

/// Exact resource currently displayed by the native Reader, independent of the
/// saved workspace's other tiles and translations.
@immutable
class ReaderSearchResource {
  const ReaderSearchResource({
    required this.id,
    required this.title,
    required this.kind,
    this.direction = 'ltr',
  });
  final String id, title, kind, direction;

  @override
  bool operator ==(Object other) =>
      other is ReaderSearchResource &&
      id == other.id &&
      title == other.title &&
      kind == other.kind &&
      direction == other.direction;
  @override
  int get hashCode => Object.hash(id, title, kind, direction);
}

/// Shell commands stay attached to the current Reader instance, including when
/// the shell temporarily keeps that Reader offstage.
class ReaderController extends ChangeNotifier {
  Object? _owner;
  Future<void> Function()? _showTabs;
  Future<bool> Function()? _flush;
  Future<bool> Function(bool)? _setVersePerLine;
  Future<bool> Function(ReaderCompanion)? _setCompanion;
  ReaderCompanion _companion = const ReaderCompanion();
  List<ReaderSearchResource> _commentaries = const [];
  ReaderCompanion get companion => _companion;
  List<ReaderSearchResource> get commentaries => _commentaries;
  bool get canSetCompanion => _setCompanion != null;
  Future<bool> setCompanion(ReaderCompanion value) async =>
      await _setCompanion?.call(value) ?? false;
  bool _versePerLine = false;
  bool get versePerLine => _versePerLine;
  bool get canSetTextPresentation => _setVersePerLine != null;
  Future<bool> setVersePerLine(bool value) async =>
      await _setVersePerLine?.call(value) ?? false;
  int _tabCount = 0;
  String _activeTitle = '';
  ReaderSearchResource? _activeResource;
  bool _disposed = false;
  Json _reference = {};
  Json get reference => Map.unmodifiable(_reference);
  void updateReference(Json value) {
    _reference = Map.of(value);
  }

  int get tabCount => _tabCount;
  String get activeTitle => _activeTitle;
  ReaderSearchResource? get activeResource => _activeResource;
  Future<void> showTabs() async => _showTabs?.call();
  Future<bool> flush() async => await _flush?.call() ?? true;

  void attach(
    Object owner, {
    required Future<void> Function() showTabs,
    required Future<bool> Function() flush,
    Future<bool> Function(bool)? setVersePerLine,
    Future<bool> Function(ReaderCompanion)? setCompanion,
  }) {
    _owner = owner;
    _showTabs = showTabs;
    _flush = flush;
    _setVersePerLine = setVersePerLine;
    _setCompanion = setCompanion;
  }

  void detach(Object owner) {
    if (_owner != owner) return;
    _owner = null;
    _showTabs = null;
    _flush = null;
    _setVersePerLine = null;
    _setCompanion = null;
    update(tabCount: 0, activeTitle: '');
  }

  void update({
    required int tabCount,
    required String activeTitle,
    ReaderSearchResource? activeResource,
    Json reference = const {},
    bool versePerLine = false,
    ReaderCompanion companion = const ReaderCompanion(),
    List<ReaderSearchResource> commentaries = const [],
  }) {
    _reference = Map.of(reference);
    if (_tabCount == tabCount &&
        _activeTitle == activeTitle &&
        _activeResource == activeResource &&
        _versePerLine == versePerLine &&
        _companion == companion &&
        listEquals(_commentaries, commentaries)) {
      return;
    }
    _versePerLine = versePerLine;
    _companion = companion;
    _commentaries = List.unmodifiable(commentaries);
    _activeResource = activeResource;
    _tabCount = tabCount;
    _activeTitle = activeTitle;
    scheduleMicrotask(() {
      if (!_disposed) notifyListeners();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
