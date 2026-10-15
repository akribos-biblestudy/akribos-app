import 'dart:convert';
import 'dart:io';

import 'package:akribos_app/core/json.dart';
import 'package:akribos_app/features/documents/web_editor_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Json snapshot(String text, {int revision = 1, String status = 'saved'}) => {
    'title': 'Titel',
    'markdown': text,
    'revision': revision,
    'status': status,
  };
  Json decode(String script) => asMap(
    jsonDecode(
      script.substring(
        'window.akribosEditorBridge.receive('.length,
        script.length - 2,
      ),
    ),
  );
  void emit(WebEditorController controller, String type, Json extra) =>
      controller.receive(
        jsonEncode({
          'protocol': 1,
          'instanceId': controller.instanceId,
          'documentId': 'one',
          'userId': 'user',
          'type': type,
          'snapshot': snapshot('current'),
          'savedSnapshot': snapshot('saved'),
          ...extra,
        }),
      );

  test(
    'identity and protocol checks reject foreign snapshots and navigation',
    () async {
      final controller = WebEditorController(documentId: 'one', userId: 'user');
      addTearDown(controller.dispose);
      var navigated = false;
      controller.onNavigate = (_) => navigated = true;
      for (final change in [
        {'userId': 'other'},
        {'documentId': 'other'},
        {'protocol': 2},
      ]) {
        controller.receive(
          jsonEncode({
            'protocol': 1,
            'instanceId': controller.instanceId,
            'documentId': 'one',
            'userId': 'user',
            'type': 'navigate',
            'path': '/Joh3,16',
            'snapshot': snapshot('private'),
            ...change,
          }),
        );
      }
      expect(controller.snapshot, isNull);
      expect(navigated, isFalse);
      controller.receive('broken');
    },
  );

  test(
    'ready restore initialize preserves stale revision and JSON source exactly',
    () async {
      final controller = WebEditorController(documentId: 'one', userId: 'user');
      addTearDown(controller.dispose);
      final requests = <Json>[];
      controller.attach((script) async {
        final request = decode(script);
        requests.add(request);
        emit(controller, 'response', {
          'id': request['id'],
          'method': request['method'],
          'ok': true,
          'snapshot': snapshot('server', revision: 4),
        });
      });
      const source = 'Text " </script> \\ ` \nἸησοῦς שָׁלוֹם';
      final start = controller.start(
        restore: snapshot(source, revision: 1, status: 'dirty'),
        readOnly: false,
      );
      expect(requests, isEmpty);
      emit(controller, 'ready', {'snapshot': snapshot('server', revision: 4)});
      await start;
      expect(requests.map((v) => v['method']), ['restore', 'initialize']);
      expect(requests.first['snapshot']['markdown'], source);
      expect(requests.first['snapshot']['revision'], 1);
      expect(controller.initialized, isTrue);
    },
  );

  test('commands serialize and preserve current plus separately acknowledged source', () async {
    final controller = WebEditorController(documentId: 'one', userId: 'user');
    addTearDown(controller.dispose);
    final requests = <Json>[];
    controller.attach((script) async {
      requests.add(decode(script));
    });
    final first = controller.command('snapshot');
    final second = controller.command('setMode', {'mode': 'read'});
    await Future<void>.delayed(Duration.zero);
    expect(requests, hasLength(1));
    emit(controller, 'response', {
      'id': requests.first['id'],
      'method': requests.first['method'],
      'ok': true,
      'snapshot': snapshot('new', revision: 2, status: 'dirty'),
      'savedSnapshot': snapshot('old', revision: 2),
    });
    await first;
    await Future<void>.delayed(Duration.zero);
    expect(requests, hasLength(2));
    expect(controller.snapshot!['markdown'], 'new');
    expect(controller.savedSnapshot!['markdown'], 'old');
    emit(controller, 'response', {
      'id': requests.last['id'],
      'method': requests.last['method'],
      'ok': true,
    });
    await second;
  });

  test(
    'timeout fails closed and a late response cannot acknowledge text',
    () async {
      final controller = WebEditorController(
        documentId: 'one',
        userId: 'user',
        commandTimeout: const Duration(milliseconds: 20),
      );
      addTearDown(controller.dispose);
      Json? request;
      controller.attach((script) async {
        request = decode(script);
      });
      await expectLater(controller.command('flush'), throwsStateError);
      expect(controller.failed, isTrue);
      emit(controller, 'response', {
        'id': request!['id'],
        'method': request!['method'],
        'ok': true,
        'snapshot': snapshot('late'),
      });
      expect(controller.snapshot, isNull);
      await expectLater(controller.command('restore'), throwsStateError);
    },
  );

  test(
    'dispose completes a pending command without late notifications',
    () async {
      final controller = WebEditorController(documentId: 'one', userId: 'user');
      controller.attach((_) async {});
      final result = controller.command('snapshot');
      await Future<void>.delayed(Duration.zero);
      controller.dispose();
      await expectLater(result, throwsStateError);
      emit(controller, 'state', {'snapshot': snapshot('late')});
      expect(controller.snapshot, isNull);
    },
  );
  test('same document old instance and malformed snapshots cannot replace current source', () {
    final controller = WebEditorController(documentId: 'one', userId: 'user');
    addTearDown(controller.dispose);
    emit(controller, 'state', {'snapshot': snapshot('kept')});
    controller.receive(
      jsonEncode({
        'protocol': 1,
        'instanceId': 'old',
        'documentId': 'one',
        'userId': 'user',
        'type': 'state',
        'snapshot': snapshot('stale'),
        'savedSnapshot': snapshot('stale'),
      }),
    );
    expect(controller.snapshot!['markdown'], 'kept');
    emit(controller, 'state', {
      'snapshot': snapshot('invalid', status: 'unknown'),
    });
    expect(controller.failed, isTrue);
    expect(controller.snapshot!['markdown'], 'kept');
  });

  test('oversized UTF8 source and unsafe revisions fail without truncating saved draft', () {
    for (final invalid in [
      snapshot(List.filled(600000, 'ä').join()),
      snapshot('x', revision: 0),
    ]) {
      final controller = WebEditorController(documentId: 'one', userId: 'user');
      emit(controller, 'state', {'snapshot': snapshot('kept')});
      emit(controller, 'state', {'snapshot': invalid});
      expect(controller.failed, isTrue);
      expect(controller.snapshot!['markdown'], 'kept');
      controller.dispose();
    }
  });
  test(
    'replays genuine server bridge transcripts for native command sequences',
    () async {
      final fixture = asMap(
        jsonDecode(
          File('test/features/documents/fixtures/web_editor_protocol.json')
              .readAsStringSync(),
        ),
      );
      for (final scenario in asMaps(fixture['scenarios'])) {
        final controller = WebEditorController(
          documentId: 'doc',
          userId: 'user',
        );
        final messages = asMaps(scenario['messages']);
        final requests = asMaps(scenario['requests']);
        var index = 0;
        controller.attach((script) async {
          final actual = decode(script), expected = requests[index++];
          expect(
            actual['method'],
            expected['method'],
            reason: asString(scenario['name']),
          );
          final response = messages.firstWhere(
            (message) =>
                message['type'] == 'response' &&
                message['id'] == expected['id'],
          );
          controller.receive(
            jsonEncode({
              ...response,
              'id': actual['id'],
              'instanceId': controller.instanceId,
            }),
          );
        });
        controller.receive(
          jsonEncode({
            ...messages.firstWhere((message) => message['type'] == 'ready'),
            'instanceId': controller.instanceId,
          }),
        );
        for (final request in requests) {
          final response = messages.firstWhere(
            (message) =>
                message['type'] == 'response' && message['id'] == request['id'],
          );
          final result = controller.command(
            asString(request['method']),
            request,
          );
          if (response['ok'] == true) {
            await result;
          } else {
            await expectLater(result, throwsStateError);
          }
        }
        expect(index, requests.length);
        expect(controller.failed, isFalse, reason: asString(scenario['name']));
        expect(controller.snapshot, messages.last['snapshot']);
        controller.dispose();
      }
    },
  );
}
