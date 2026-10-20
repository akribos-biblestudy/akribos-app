import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../../core/json.dart';

/// Presentation preferences belong only to this installation and account.
/// The notes companion follows the visible chapter, never another workspace/tab.
@immutable
class ReaderCompanion {
  const ReaderCompanion({this.enabled = false, this.onLeft = false});

  factory ReaderCompanion.fromJson(dynamic value) {
    final data = asMap(value);
    // Legacy commentary resourceId is intentionally ignored. Tabs live in the
    // independent reader URL and are never removed by this presentation change.
    return ReaderCompanion(
      enabled: data['enabled'] == true,
      onLeft: data['onLeft'] == true,
    );
  }

  final bool enabled, onLeft;

  ReaderCompanion copyWith({bool? enabled, bool? onLeft}) => ReaderCompanion(
    enabled: enabled ?? this.enabled,
    onLeft: onLeft ?? this.onLeft,
  );

  Json toJson() => {'enabled': enabled, 'onLeft': onLeft};

  @override
  bool operator ==(Object other) =>
      other is ReaderCompanion &&
      enabled == other.enabled &&
      onLeft == other.onLeft;

  @override
  int get hashCode => Object.hash(enabled, onLeft);
}

/// Respect actual split-screen width and accessible text, not device model.
bool canShowReaderCompanion(double width, TextScaler scaler) =>
    width >= 760 && width >= scaler.scale(300) * 2 + 1;
