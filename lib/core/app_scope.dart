import 'package:flutter/material.dart';

import 'api_client.dart';

class AppScope extends InheritedWidget {
  const AppScope({
    super.key,
    required this.api,
    required this.open,
    required this.refreshSession,
    this.onAuthenticationChanged,
    required this.setNavigationGuard,
    required this.setTheme,
    required this.themeMode,
    this.eInk = false,
    this.setEInk,
    this.notesChapter = '',
    this.notesChapterEnabled = true,
    this.setNotesChapterEnabled,
    required super.child,
  });
  final String notesChapter;
  final bool notesChapterEnabled;
  final Future<void> Function(bool)? setNotesChapterEnabled;
  final AppApi api;
  final Future<void> Function(String path) open;
  final Future<void> Function() refreshSession;
  final Future<void> Function()? onAuthenticationChanged;

  /// Authentication changes must clear retained private UI before any network wait.
  Future<void> authenticationChanged() =>
      (onAuthenticationChanged ?? refreshSession)();
  final void Function(Object owner, Future<bool> Function()? guard)
  setNavigationGuard;
  final void Function(ThemeMode mode) setTheme;
  final ThemeMode themeMode;
  final bool eInk;
  final void Function(bool enabled)? setEInk;
  static AppScope of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!;
  @override
  bool updateShouldNotify(AppScope oldWidget) =>
      api != oldWidget.api ||
      open != oldWidget.open ||
      refreshSession != oldWidget.refreshSession ||
      onAuthenticationChanged != oldWidget.onAuthenticationChanged ||
      setNavigationGuard != oldWidget.setNavigationGuard ||
      setTheme != oldWidget.setTheme ||
      themeMode != oldWidget.themeMode ||
      eInk != oldWidget.eInk ||
      setEInk != oldWidget.setEInk ||
      notesChapter != oldWidget.notesChapter ||
      notesChapterEnabled != oldWidget.notesChapterEnabled ||
      setNotesChapterEnabled != oldWidget.setNotesChapterEnabled;
}
