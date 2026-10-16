import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../core/api_client.dart';

/// Only the isolated, authenticated editor page may speak this protocol.
/// Text saves belong to the web editor; native commands never PATCH text.
class WebEditorController extends ChangeNotifier {
  WebEditorController({
    required this.documentId,
    required this.userId,
    this.commandTimeout = const Duration(seconds: 30),
  }) : instanceId = AppApi.newBrowserTabId();

  final String instanceId;
  final String documentId;
  final String userId;
  final Duration commandTimeout;
  Future<void> Function(String script)? _send;
  final _ready = Completer<bool>();
  final _pending = <String, Completer<Json>>{};
  final _methods = <String, String>{};
  Future<void> _queue = Future.value();
  int _sequence = 0;
  bool _disposed = false;
  bool initialized = false;
  bool failed = false;
  Json? snapshot;
  Json? savedSnapshot;
  String? error;
  void Function(String path)? onNavigate;

  void attach(Future<void> Function(String script) send) => _send = send;

  void receive(String raw) {
    if (_disposed || raw.length > 14 * 1024 * 1024) return;
    Json message;
    try {
      message = asMap(jsonDecode(raw));
    } catch (_) {
      return;
    }
    if (message['protocol'] != 1 ||
        message['instanceId'] != instanceId ||
        message['documentId'] != documentId ||
        message['userId'] != userId) {
      return;
    }
    final type = message['type'];
    if (!const ['ready', 'state', 'response', 'navigate'].contains(type)) {
      return;
    }
    if (type == 'response' &&
        (!_pending.containsKey(message['id']) ||
            message['method'] != _methods[message['id']])) {
      return;
    }
    if (type == 'ready' && _ready.isCompleted) {
      fail(
        'Der Editor wurde unerwartet neu geladen. Bitte den gesicherten Entwurf prüfen.',
      );
      return;
    }
    final current = _snapshot(message['snapshot']);
    final saved = _snapshot(message['savedSnapshot']);
    if (current == null ||
        saved == null ||
        !const [
          'saved',
          'dirty',
          'saving',
          'error',
          'conflict',
        ].contains(current['status'])) {
      fail('Der Editor hat einen ungültigen Dokumentstand geliefert.');
      return;
    }
    snapshot = current;
    savedSnapshot = saved;
    if (current['status'] == 'saved') error = null;
    if (type == 'ready' && !_ready.isCompleted) _ready.complete(true);
    if (type == 'response') {
      _pending.remove(message['id'])?.complete(message);
    }
    if (type == 'navigate' && message['path'] is String) {
      onNavigate?.call(message['path'] as String);
    }
    notifyListeners();
  }

  static Json? _snapshot(Object? value) {
    final map = asMap(value);
    if (map['title'] is! String ||
        map['markdown'] is! String ||
        map['revision'] is! int ||
        (map['revision'] as int) < 1 ||
        (map['revision'] as int) > 9007199254740991 ||
        (map['title'] as String).runes.length > 200 ||
        (map['markdown'] as String).contains('\u0000') ||
        utf8.encode(map['markdown'] as String).length > 1024 * 1024) {
      return null;
    }
    return Map<String, dynamic>.from(map);
  }

  Future<void> start({Json? restore, required bool readOnly}) async {
    if (!await _ready.future.timeout(commandTimeout)) {
      throw StateError('Der Editor wurde geschlossen.');
    }
    if (restore != null) await command('restore', {'snapshot': restore});
    await command('initialize', {'mode': readOnly ? 'read' : 'edit'});
    if (_disposed) return;
    initialized = true;
    notifyListeners();
  }

  Future<Json> command(String method, [Json payload = const {}]) {
    final result = Completer<Json>();
    _queue = _queue.then((_) async {
      try {
        if (_disposed || failed || _send == null) {
          throw StateError('Der Editor ist nicht verbunden.');
        }
        final id = '${++_sequence}';
        final response = Completer<Json>();
        _pending[id] = response;
        _methods[id] = method;
        try {
          // JSON encode the entire object; never interpolate source as JavaScript.
          final message = jsonEncode({
            ...payload,
            'protocol': 1,
            'instanceId': instanceId,
            'id': id,
            'method': method,
            'documentId': documentId,
            'userId': userId,
          });
          await _send!('window.akribosEditorBridge.receive($message);')
              .timeout(commandTimeout);
          final value = await response.future.timeout(commandTimeout);
          if (value['ok'] != true) {
            throw StateError(
              asString(
                value['error'],
                'Der Editor konnte die Änderung nicht bestätigen.',
              ),
            );
          }
          result.complete(value);
        } on TimeoutException {
          // The outcome is unknown; do not send subsequent writes on this bridge.
          failed = true;
          throw StateError(
            'Der Editor antwortet nicht. Dein gesicherter Entwurf bleibt erhalten.',
          );
        } finally {
          _pending.remove(id);
          _methods.remove(id);
        }
      } catch (failure, stack) {
        if (!_disposed) {
          error = '$failure';
          notifyListeners();
        }
        result.completeError(failure, stack);
      }
    });
    return result.future;
  }

  Future<void> flush() async {
    if (!initialized) throw StateError('Der Editor ist noch nicht bereit.');
    await command('flush');
    if (snapshot?['status'] != 'saved') {
      throw StateError('Die Änderungen wurden noch nicht gespeichert.');
    }
  }

  Future<void> setMode(bool readOnly) async {
    await command('setMode', {'mode': readOnly ? 'read' : 'edit'});
  }

  void fail(String message) {
    if (_disposed) return;
    failed = true;
    error = message;
    for (final response in _pending.values) {
      if (!response.isCompleted) {
        response.complete({'ok': false, 'error': message});
      }
    }
    _pending.clear();
    if (!_ready.isCompleted) _ready.complete(false);
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    if (!_ready.isCompleted) _ready.complete(false);
    for (final response in _pending.values) {
      response.complete({
        'ok': false,
        'error': 'Der Editor wurde geschlossen.',
      });
    }
    _pending.clear();
    _send = null;
    super.dispose();
  }
}
