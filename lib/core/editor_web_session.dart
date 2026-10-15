import 'dart:io';

import 'package:flutter/services.dart';

/// Copies the existing app session through a native channel only. No JavaScript,
/// URL parameter, logger or second persistent token store receives credentials.
class EditorWebSession {
  EditorWebSession({MethodChannel? channel, bool? supported})
    : _channel =
          channel ?? const MethodChannel('de.akribos.app/editor-session'),
      _supported = supported ?? (Platform.isAndroid || Platform.isIOS);

  final MethodChannel _channel;
  final bool _supported;
  // WebView's cookie store is process-wide, including different AppApi instances.
  static Future<void> _pending = Future<void>.value();
  // Process-local only: avoid throwing away cached editor assets for each note.
  // Never persist, expose or log this binding. It is valid only after native ACK.
  static String? _preparedOrigin;
  static String? _preparedSession;

  Future<void> setSession(Uri origin, String? session) {
    final operation = _pending.then((_) async {
      if (session != null &&
          _preparedOrigin == origin.origin &&
          _preparedSession == session) {
        return;
      }
      _preparedOrigin = null;
      _preparedSession = null;
      if (!_supported) return;
      try {
        await _channel.invokeMethod<void>('setSession', {
          'origin': origin.origin,
          'session': ?session,
        });
        if (session != null) {
          _preparedOrigin = origin.origin;
          _preparedSession = session;
        }
      } on PlatformException {
        // Native exception details must never leak cookies or platform data.
        throw const EditorWebSessionException();
      } on MissingPluginException {
        throw const EditorWebSessionException();
      }
    });
    // A failed preparation remains visible to its caller but must not poison
    // the queue: logout and subsequent attempts still need to clear the store.
    _pending = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }

  Future<void> clear(Uri origin) => setSession(origin, null);
}

class EditorWebSessionException implements Exception {
  const EditorWebSessionException();

  @override
  String toString() =>
      'Die sichere Editorsitzung konnte nicht vorbereitet werden. Bitte erneut versuchen.';
}
