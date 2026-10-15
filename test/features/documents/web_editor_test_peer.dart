import 'dart:async';
import 'dart:convert';

import 'package:akribos_app/core/api_client.dart';
import 'package:akribos_app/core/app_scope.dart';
import 'package:akribos_app/features/documents/web_editor_controller.dart';
import 'package:flutter/material.dart';

Widget testWebEditorBuilder(
  BuildContext context,
  WebEditorController controller,
  Json? restore,
  bool readOnly,
  VoidCallback retry,
) => TestWebEditorPeer(
  controller: controller,
  restore: restore,
  readOnly: readOnly,
);

/// Protocol peer only: these tests exercise the native host without a platform
/// view. The real Tiptap save queue/schema is covered in the server repository.
class TestWebEditorPeer extends StatefulWidget {
  const TestWebEditorPeer({
    super.key,
    required this.controller,
    this.restore,
    required this.readOnly,
    this.readyDelay,
  });
  final WebEditorController controller;
  final Json? restore;
  final bool readOnly;
  final Future<void>? readyDelay;
  @override
  State<TestWebEditorPeer> createState() => TestWebEditorPeerState();
}

class TestWebEditorPeerState extends State<TestWebEditorPeer> {
  Json current = {}, saved = {};
  final commands = <String>[];
  bool locked = true;
  bool _initialized = false, _mutation = false, _paused = false;
  bool reading = false;
  late AppApi api;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    api = AppScope.of(context).api;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_start()));
  }

  Future<void> _start() async {
    final data = await api.page('/notes/${widget.controller.documentId}');
    if (!mounted) return;
    final doc = asMap(data['document']);
    current = {
      'title': doc['title'],
      'markdown': doc['bodyMarkdown'],
      'revision': doc['revision'],
      'status': 'saved',
    };
    saved = Map.of(current);
    widget.controller.attach((script) async {
      final message = asMap(
        jsonDecode(
          script.substring(
            'window.akribosEditorBridge.receive('.length,
            script.length - 2,
          ),
        ),
      );
      commands.add(asString(message['method']));
      var ok = true;
      String? error;
      try {
        switch (message['method']) {
          case 'restore':
            if (_initialized) throw StateError('invalidRestore');
            current = {...asMap(message['snapshot']), 'status': 'dirty'};
          case 'initialize':
            if (_initialized) throw StateError('alreadyInitialized');
            _initialized = true;
            reading = message['mode'] == 'read';
            locked = false;
          case 'prepareMutation':
            if (!_initialized || _mutation || _paused) {
              throw StateError('locked');
            }
            _mutation = true;
            locked = true;
            try {
              await _flush();
            } catch (_) {
              _mutation = false;
              locked = false;
              rethrow;
            }
          case 'flush':
            if (!_initialized || _mutation || _paused) {
              throw StateError('locked');
            }
            await _flush();
          case 'setMode':
            if (!_initialized || _paused) throw StateError('locked');
            reading = message['mode'] == 'read';
          case 'pause':
            if (!_initialized) throw StateError('locked');
            _mutation = false;
            _paused = true;
            locked = true;
          case 'resume':
            if (!_initialized || _mutation) throw StateError('locked');
            _paused = false;
            locked = false;
          case 'cancelMutation':
            if (!_mutation) throw StateError('notPrepared');
            _mutation = false;
            locked = false;
          case 'finishMutation':
            if (!_mutation) throw StateError('notPrepared');
            _mutation = false;
            final doc = asMap(message['document']);
            current = {
              'title': doc['title'],
              'markdown': doc['bodyMarkdown'],
              'revision': doc['revision'],
              'status': 'saved',
            };
            saved = Map.of(current);
            locked = false;
        }
      } catch (failure) {
        current['status'] = failure is ApiException && failure.status == 409
            ? 'conflict'
            : 'error';
        ok = false;
        error = '$failure';
      }
      if (!mounted) return;
      emit('response', {
        'id': message['id'],
        'method': message['method'],
        'ok': ok,
        'error': error,
      });
      setState(() {});
    });
    await widget.readyDelay;
    if (!mounted) return;
    emit('ready');
    await widget.controller.start(
      restore: widget.restore,
      readOnly: widget.readOnly,
    );
    if (mounted) setState(() {});
  }

  void emit(String type, [Json extra = const {}]) => widget.controller.receive(
    jsonEncode({
      'protocol': 1,
      'instanceId': widget.controller.instanceId,
      'type': type,
      'documentId': widget.controller.documentId,
      'userId': widget.controller.userId,
      'snapshot': current,
      'savedSnapshot': saved,
      ...extra,
    }),
  );
  void edit(String value, {bool notify = true}) {
    if (locked || reading) throw StateError('Editor is locked');
    current = {...current, 'markdown': value, 'status': 'dirty'};
    if (notify) emit('state');
    setState(() {});
  }

  Future<void> _flush() async {
    while (current['title'] != saved['title'] ||
        current['markdown'] != saved['markdown']) {
      final submitted = Map<String, dynamic>.of(current)..remove('status');
      final response = asMap(
        await api.send(
          'PATCH',
          '/api/documents/${widget.controller.documentId}',
          data: submitted,
        ),
      );
      final doc = asMap(response['document']);
      saved = {...submitted, 'revision': doc['revision']};
      current['revision'] = doc['revision'];
    }
    current['status'] = 'saved';
  }

  @override
  Widget build(BuildContext context) =>
      Center(child: Text('Web editor: ${current['markdown'] ?? ''}'));
}
