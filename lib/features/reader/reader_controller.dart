import 'dart:async';

import 'package:flutter/foundation.dart';

/// Shell commands stay attached to the current Reader instance, including when
/// the shell temporarily keeps that Reader offstage.
class ReaderController extends ChangeNotifier {
  Object? _owner;
  Future<void> Function()? _showTabs;
  Future<bool> Function()? _flush;
  int _tabCount = 0;
  String _activeTitle = '';
  bool _disposed = false;

  int get tabCount => _tabCount;
  String get activeTitle => _activeTitle;
  Future<void> showTabs() async => _showTabs?.call();
  Future<bool> flush() async => await _flush?.call() ?? true;

  void attach(
    Object owner, {
    required Future<void> Function() showTabs,
    required Future<bool> Function() flush,
  }) {
    _owner = owner;
    _showTabs = showTabs;
    _flush = flush;
  }

  void detach(Object owner) {
    if (_owner != owner) return;
    _owner = null;
    _showTabs = null;
    _flush = null;
  }

  void update({required int tabCount, required String activeTitle}) {
    if (_tabCount == tabCount && _activeTitle == activeTitle) return;
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
