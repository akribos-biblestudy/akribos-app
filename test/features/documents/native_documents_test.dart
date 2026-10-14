import 'dart:async';

import 'package:akribos_app/core/api_client.dart';
import 'package:akribos_app/core/app_scope.dart';
import 'package:akribos_app/features/collections/collections_screen.dart';
import 'package:akribos_app/features/documents/document_editor.dart';
import 'package:akribos_app/features/documents/documents_screen.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeApi extends AppApi {
  _FakeApi(this.data)
    : super(server: 'https://example.test', cookies: CookieJar());
  final Json data;
  final saves = <Json>[];
  final actions = <Json>[];
  ApiResult actionResult = const ApiResult(type: 'success', status: 200);
  Completer<dynamic>? pending;
  @override
  Future<Json> page(String path) async => data;
  @override
  Future<dynamic> get(String path) async => {};
  @override
  Future<ApiResult> action(String path, String action, Json fields) async {
    actions.add({'path': path, 'action': action, 'fields': fields});
    return actionResult;
  }

  @override
  Future<dynamic> send(String method, String path, {dynamic data}) async {
    saves.add(Map<String, dynamic>.from(data as Map));
    if (pending != null) return pending!.future;
    return {
      'document': {
        'id': 'one',
        'kind': 'note',
        'title': data['title'],
        'bodyMarkdown': data['markdown'],
        'bodyHtml': '<p>${data['markdown']}</p>',
        'revision': asInt(data['revision']) + 1,
      },
    };
  }
}

Widget _app(
  AppApi api,
  Widget child, {
  void Function(Object, Future<bool> Function()?)? guard,
  double textScale = 1,
  bool eInk = false,
}) => AppScope(
  api: api,
  open: (_) async {},
  refreshSession: () async {},
  setNavigationGuard: guard ?? (_, _) {},
  setTheme: (_) {},
  themeMode: ThemeMode.light,
  eInk: eInk,
  child: MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: Scaffold(body: child),
  ),
);

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets('template save failure retains the full draft for retry', (
    tester,
  ) async {
    final api = _FakeApi({'templates': []});
    api.actionResult = const ApiResult(type: 'failure', status: 503);
    await tester.pumpWidget(
      _app(api, const DocumentsScreen(path: '/sermons/templates')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vorlage'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextFormField).first,
      'Meine Gliederung',
    );
    const body =
        '# Einführung\n\nEin längerer Gedanke mit **Betonung**.\n\n## Anwendung';
    await tester.enterText(find.byType(TextFormField).last, body);
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    expect(find.text('Neue Vorlage'), findsOneWidget);
    expect(
      tester
          .widget<TextFormField>(find.byType(TextFormField).last)
          .controller!
          .text,
      body,
    );
    expect(find.textContaining('vorübergehend'), findsOneWidget);
    api.actionResult = const ApiResult(type: 'success', status: 200);
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    expect(find.text('Neue Vorlage'), findsNothing);
    expect(api.actions.last['fields'], {
      'name': 'Meine Gliederung',
      'bodyMarkdown': body,
    });
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'note creation modal keeps its fields alive through close animation',
    (tester) async {
      final api = _FakeApi({
        'documents': [],
        'filters': {},
        'pagination': {'page': 1, 'pageCount': 1},
      });
      await tester.pumpWidget(
        _app(
          api,
          const DocumentsScreen(path: '/notes?reference=Joh3,16&bible=SEEDDE'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Notiz'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextFormField).first,
        'Gedanken zum Vers',
      );
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField).last)
            .controller!
            .text,
        'Joh3,16',
      );
      await tester.tap(find.text('Anlegen'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(api.actions.single, {
        'path': '/notes',
        'action': 'create',
        'fields': {
          'title': 'Gedanken zum Vers',
          'passage': 'Joh3,16',
          'kind': 'note',
          'returnTo': '/notes?reference=Joh3,16&bible=SEEDDE',
          'resourceId': 'SEEDDE',
        },
      });
    },
  );

  testWidgets(
    'phone library and native collection threads stay within the viewport',
    (tester) async {
      tester.view.physicalSize = const Size(320, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final library = _FakeApi({
        'documents': [
          {
            'id': 'one',
            'title': 'Eine sehr ausführliche Notiz über Johannes und seine Botschaft',
            'plainText': 'Meine Gedanken',
            'revision': 1,
          },
        ],
        'filters': {},
        'pagination': {'page': 1, 'pageCount': 1},
      });
      await tester.pumpWidget(
        _app(library, const DocumentsScreen(path: '/notes'), textScale: 1.7),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Meine Notizen'), findsOneWidget);

      final collection = _FakeApi({
        'list': {'title': 'Glaube und Hoffnung'},
        'isOwner': true,
        'currentUserId': 'me',
        'members': [],
        'items': [
          {
            'id': 'verse',
            'book': 43,
            'chapter': 3,
            'verse': 16,
            'segments': ['Denn also hat Gott die Welt geliebt.'],
            'canDelete': true,
          },
        ],
        'comments': {
          'verse': [
            {
              'id': 'comment',
              'authorUserId': 'me',
              'authorName': 'Leser',
              'bodyHtml': '<p>Eine <strong>wichtige</strong> Beobachtung.</p>',
              'reactions': [
                {'emoji': '👍', 'count': 1, 'reactedByMe': true},
              ],
              'replies': [],
            },
          ],
        },
      });
      await tester.pumpWidget(
        _app(
          collection,
          const CollectionsScreen(path: '/lists/test'),
          textScale: 1.7,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Glaube und Hoffnung'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Kommentieren'),
        250,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kommentieren'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Text <script>\nAntwort');
      await tester.tap(find.text('Speichern'));
      await tester.pumpAndSettle();
      expect(collection.actions.single['action'], 'comment');
      expect(asMap(collection.actions.single['fields']), {
        'itemId': 'verse',
        'parentCommentId': '',
        'note': '<p>Text &lt;script&gt;<br>\nAntwort</p>',
      });
    },
  );

  testWidgets(
    'tablet preparation board sends revision-protected column moves',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = _FakeApi({
        'board': {
          'revision': 4,
          'columns': [
            {'id': 'idea', 'name': 'Ideen'},
            {'id': 'ready', 'name': 'Bereit'},
          ],
        },
        'sermons': [
          {
            'id': 'one',
            'title': 'Vorbereitung',
            'sermonStatus': 'idea',
            'revision': 2,
          },
        ],
        'filters': {},
      });
      await tester.pumpWidget(
        _app(api, const DocumentsScreen(path: '/sermons')),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Ideen'), findsOneWidget);
      expect(find.text('Bereit'), findsOneWidget);
      await tester.tap(find.byTooltip('Dokumentaktionen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Verschieben: Bereit'));
      await tester.pumpAndSettle();
      expect(api.actions.single, {
        'path': '/sermons',
        'action': 'move',
        'fields': {'id': 'one', 'revision': 2, 'status': 'ready'},
      });
    },
  );

  testWidgets(
    'editor serializes saves and does not overwrite text typed during request',
    (tester) async {
      final api = _FakeApi({
        'user': {'id': 'user'},
        'document': {
          'id': 'one',
          'kind': 'note',
          'title': 'Titel',
          'bodyMarkdown': 'Alt',
          'revision': 1,
        },
        'tags': [],
        'passages': [],
        'bibles': [],
      });
      final first = Completer<dynamic>();
      api.pending = first;
      Future<bool> Function()? guard;
      await tester.pumpWidget(
        _app(
          api,
          const DocumentEditor(path: '/notes/one'),
          guard: (_, callback) => guard = callback,
        ),
      );
      await tester.pumpAndSettle();
      final body = find.byType(TextField).at(1);
      await tester.enterText(body, 'Erster Text');
      await tester.pump(const Duration(milliseconds: 1300));
      expect(api.saves, hasLength(1));
      await tester.enterText(body, 'Text während der Anfrage');
      api.pending = null;
      first.complete({
        'document': {
          'id': 'one',
          'kind': 'note',
          'title': 'Titel',
          'bodyMarkdown': 'Erster Text',
          'revision': 2,
        },
      });
      await tester.pump();
      expect(
        tester.widget<TextField>(body).controller!.text,
        'Text während der Anfrage',
      );
      final canNavigate = guard!();
      await tester.pump();
      expect(await canNavigate, isTrue);
      expect(api.saves, hasLength(2));
      expect(api.saves.last['revision'], 2);
      expect(api.saves.last['markdown'], 'Text während der Anfrage');
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );

  testWidgets('e-ink opens existing documents in native reading view', (
    tester,
  ) async {
    final api = _FakeApi({
      'user': {'id': 'user'},
      'document': {
        'id': 'one',
        'kind': 'note',
        'title': 'Gedanken',
        'bodyMarkdown': 'Lesetext',
        'bodyHtml': '<p>Lesetext</p>',
        'revision': 1,
      },
      'tags': [],
      'passages': [],
    });
    await tester.pumpWidget(
      _app(api, const DocumentEditor(path: '/notes/one'), eInk: true),
    );
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    expect(find.byTooltip('Bearbeiten'), findsOneWidget);
    await tester.tap(find.byTooltip('Bearbeiten'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNWidgets(2));
  });
}
