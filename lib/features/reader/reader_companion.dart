import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../../core/json.dart';

/// Presentation preferences belong only to this installation and account.
/// The companion is a read-only follower, never another saved workspace/tab.
@immutable
class ReaderCompanion {
  const ReaderCompanion({
    this.enabled = false,
    this.onLeft = false,
    this.resourceId = '',
  });

  factory ReaderCompanion.fromJson(dynamic value) {
    final data = asMap(value);
    return ReaderCompanion(
      enabled: data['enabled'] == true,
      onLeft: data['onLeft'] == true,
      resourceId: asString(data['resourceId']),
    );
  }

  final bool enabled, onLeft;
  final String resourceId;

  ReaderCompanion copyWith({bool? enabled, bool? onLeft, String? resourceId}) =>
      ReaderCompanion(
        enabled: enabled ?? this.enabled,
        onLeft: onLeft ?? this.onLeft,
        resourceId: resourceId ?? this.resourceId,
      );

  Json toJson() => {
    'enabled': enabled,
    'onLeft': onLeft,
    'resourceId': resourceId,
  };

  @override
  bool operator ==(Object other) =>
      other is ReaderCompanion &&
      enabled == other.enabled &&
      onLeft == other.onLeft &&
      resourceId == other.resourceId;

  @override
  int get hashCode => Object.hash(enabled, onLeft, resourceId);
}

/// Respect actual split-screen width and accessible text, not device model.
bool canShowReaderCompanion(double width, TextScaler scaler) =>
    width >= 760 && width >= scaler.scale(300) * 2 + 1;
