import 'package:flutter/material.dart';

import 'api_client.dart';

class AppScope extends InheritedWidget {
  const AppScope({
    super.key,
    required this.api,
    required this.open,
    required this.refreshSession,
    required this.setNavigationGuard,
    required this.setTheme,
    required this.themeMode,
    this.eInk = false,
    this.setEInk,
    required super.child,
  });
  final AppApi api;
  final Future<void> Function(String path) open;
  final Future<void> Function() refreshSession;
  final void Function(Object owner, Future<bool> Function()? guard)
  setNavigationGuard;
  final void Function(ThemeMode mode) setTheme;
  final ThemeMode themeMode;
  final bool eInk;
  final void Function(bool enabled)? setEInk;
  static AppScope of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!;
  @override
  bool updateShouldNotify(AppScope oldWidget) => true;
}
