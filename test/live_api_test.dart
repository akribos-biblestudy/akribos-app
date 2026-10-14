import 'package:akribos_app/core/api_client.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:flutter_test/flutter_test.dart';

const _server = String.fromEnvironment('AKRIBOS_TEST_SERVER');

void main() {
  test(
    'native HTTP client completes normal-user session, reading, editing and collections',
    () async {
      final origin = Uri.parse(_server);
      expect(
        ['localhost', '127.0.0.1', '::1'],
        contains(origin.host),
        reason: 'Live tests may only mutate an explicitly isolated local seed server.',
      );
      final api = AppApi(server: _server, cookies: CookieJar());
      addTearDown(api.dispose);
      await api.initializeReader(1000);
      final bootstrap = await api.loadBootstrap();
      expect(bootstrap['protocolVersion'], 1);
      expect(asMaps(bootstrap['readerResources']), isNotEmpty);
      var path = '/Joh1';
      Json? reader;
      for (var count = 0; count < 6; count++) {
        try {
          reader = await api.page(path);
          break;
        } on AppRedirect catch (redirect) {
          path = redirect.location;
        }
      }
      expect(asMap(reader?['reference'])['book'], 43);
      final login = await api.action('/login', 'login', {
        'email': 'reader@example.com',
        'password': 'seed-reader-password',
        'redirectTo': '/notes',
      });
      expect(login.isRedirect, isTrue);
      final account = await api.loadBootstrap();
      expect(asMap(account['user'])['email'], 'reader@example.com');
      final created = await api.action('/notes', 'create', {
        'kind': 'note',
        'title': 'Flutter integration ${DateTime.now().microsecondsSinceEpoch}',
      });
      expect(created.isRedirect, isTrue);
      final note = asMap((await api.page(created.location!))['document']);
      final id = asString(note['id']);
      final revision = asInt(note['revision']);
      try {
        final saved = asMap(
          await api.send(
            'PATCH',
            '/api/documents/$id',
            data: {
              'revision': revision,
              'title': 'Native integration',
              'markdown': '## Gedanken\n\nJoh 1,1',
            },
          ),
        );
        expect(asMap(saved['document'])['bodyMarkdown'], contains('Joh 1,1'));
        await expectLater(
          api.send(
            'PATCH',
            '/api/documents/$id',
            data: {
              'revision': revision,
              'title': 'Stale title',
              'markdown': 'Stale',
            },
          ),
          throwsA(isA<ApiException>().having((e) => e.status, 'status', 409)),
        );
        final collection = await api.action('/lists', 'createList', {
          'title': 'Flutter collection integration',
        });
        expect(collection.isRedirect, isTrue);
        final listPath = collection.location!;
        try {
          expect(
            (await api.action(listPath, 'addVerse', {
              'reference': 'Joh1,1',
            })).isSuccess,
            isTrue,
          );
          expect(asMaps((await api.page(listPath))['items']), isNotEmpty);
        } finally {
          await api.action(listPath, 'delete', {});
        }
      } finally {
        await api.send('DELETE', '/api/documents/$id');
      }
      expect((await api.action('/logout', 'default', {})).isRedirect, isTrue);
      expect((await api.loadBootstrap())['user'], isNull);
    },
    skip: _server.isEmpty
        ? 'Run against an isolated seeded server with --dart-define=AKRIBOS_TEST_SERVER=http://127.0.0.1:4176'
        : false,
  );
}
