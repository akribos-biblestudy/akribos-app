import 'dart:async';
import 'dart:convert';

import 'package:akribos_app/core/api_client.dart';
import 'package:akribos_app/core/app_scope.dart';
import 'package:akribos_app/features/collections/collections_screen.dart';
import 'package:akribos_app/features/documents/document_editor.dart';
import 'package:akribos_app/features/documents/documents_screen.dart';

import 'web_editor_test_peer.dart';

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
  Object? failure;
  @override
  Future<Json> page(String path) async => data;
  @override
  Future<dynamic> get(String path) async => path == '/api/documents/one'
      ? {'document': data['document']}
      : <String, dynamic>{};
  @override
  Future<ApiResult> action(String path, String action, Json fields) async {
    actions.add({'path': path, 'action': action, 'fields': fields});
    if (data['document'] is Map) {
      final doc = asMap(data['document']);
      doc['revision'] = asInt(doc['revision']) + 1;
    }
    return actionResult;
  }

  @override
  Future<dynamic> send(String method, String path, {dynamic data}) async {
    saves.add(Map<String, dynamic>.from(data as Map));
    if (pending != null) {
      final value = await pending!.future;
      this.data['document'] = asMap(value)['document'];
      return value;
    }
    if (failure != null) throw failure!;
    final result = {
      'document': {
        'id': 'one',
        'kind': 'note',
        'title': data['title'],
        'bodyMarkdown': data['markdown'],
        'bodyHtml': '<p>${data['markdown']}</p>',
        'revision': asInt(data['revision']) + 1,
      },
    };
    this.data['document'] = result['document'];
    return result;
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

const _draftKey = 'document-draft:https://example.test:user:one';
Widget _document() => const DocumentEditor(
  path: '/notes/one',
  webEditorBuilder: testWebEditorBuilder,
);
TestWebEditorPeerState _peer(WidgetTester tester) =>
    tester.state<TestWebEditorPeerState>(find.byType(TestWebEditorPeer));

Json _documentData({String markdown = 'Lesetext', int revision = 1}) => {
  'user': {'id': 'user'},
  'document': {
    'id': 'one',
    'kind': 'sermon',
    'title': 'Gedanken',
    'bodyMarkdown': markdown,
    'revision': revision,
  },
  'tags': [],
  'passages': [],
  'bibles': [],
};

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

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
          'returnTo': '/notes?reference=Joh3%2C16&bible=SEEDDE&kind=note',
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
    'web save barrier includes edits arriving during an earlier save',
    (tester) async {
      final api = _FakeApi(_documentData(markdown: 'Alt'));
      final first = Completer<dynamic>();
      api.pending = first;
      Future<bool> Function()? guard;
      await tester.pumpWidget(
        _app(api, _document(), guard: (_, value) => guard = value),
      );
      await tester.pumpAndSettle();
      final peer = _peer(tester);
      peer.edit('Erster Text');
      await tester.pump();
      await tester.tap(find.byTooltip('Speichern'));
      await tester.pump();
      expect(api.saves, hasLength(1));
      peer.edit('Während der Anfrage');
      final navigation = guard!();
      api.pending = null;
      first.complete({
        'document': {
          'id': 'one',
          'kind': 'sermon',
          'title': 'Gedanken',
          'bodyMarkdown': 'Erster Text',
          'revision': 2,
        },
      });
      await tester.pumpAndSettle();
      expect(await navigation, isTrue);
      expect(api.saves.map((v) => v['markdown']), [
        'Erster Text',
        'Während der Anfrage',
      ]);
      expect(api.saves.last['revision'], 2);
      expect(peer.locked, isTrue);
      expect(
        peer.commands,
        containsAllInOrder(['flush', 'prepareMutation', 'pause']),
      );
      expect(await const FlutterSecureStorage().read(key: _draftKey), isNull);
    },
  );

  testWidgets(
    'read edit toggles keep one bridge and source bytes without text writes',
    (tester) async {
      const source = '# Titel  \n\n-   Erster\n\n    -   Zweiter\n';
      final api = _FakeApi(_documentData(markdown: source));
      await tester.pumpWidget(_app(api, _document()));
      await tester.pumpAndSettle();
      final peer = _peer(tester), bridge = peer.widget.controller;
      for (final label in ['Lesen', 'Bearbeiten', 'Lesen']) {
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
        expect(_peer(tester), same(peer));
        expect(peer.widget.controller, same(bridge));
        expect(peer.current['markdown'], source);
      }
      expect(peer.reading, isTrue);
      expect(api.saves, isEmpty);
      expect(
        peer.commands,
        containsAllInOrder(['prepareMutation', 'setMode', 'cancelMutation']),
      );
      expect(find.byType(TextField), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('e ink initializes the web reader without a second renderer', (
    tester,
  ) async {
    final api = _FakeApi(_documentData());
    await tester.pumpWidget(_app(api, _document(), eInk: true));
    await tester.pumpAndSettle();
    expect(_peer(tester).reading, isTrue);
    expect(api.saves, isEmpty);
    await tester.tap(find.text('Bearbeiten'));
    await tester.pumpAndSettle();
    expect(_peer(tester).reading, isFalse);
  });

  testWidgets(
    'stale recovery keeps original revision and flush captures undelivered last key',
    (tester) async {
      FlutterSecureStorage.setMockInitialValues({
        _draftKey: jsonEncode({
          'title': 'Lokaler Titel',
          'markdown': 'Entwurf',
          'revision': 1,
        }),
      });
      final api = _FakeApi(_documentData(markdown: 'Server', revision: 3));
      Future<bool> Function()? guard;
      await tester.pumpWidget(
        _app(api, _document(), guard: (_, value) => guard = value),
      );
      await tester.pumpAndSettle();
      expect(find.text('Lokalen Entwurf wiederherstellen?'), findsOneWidget);
      await tester.tap(find.text('Entwurf öffnen'));
      await tester.pumpAndSettle();
      final peer = _peer(tester);
      expect(peer.current['revision'], 1);
      expect(api.saves, isEmpty);
      peer.edit('Letztes Zeichen!', notify: false);
      final navigation = guard!();
      await tester.pumpAndSettle();
      expect(await navigation, isTrue);
      expect(api.saves.single['revision'], 1);
      expect(api.saves.single['title'], 'Lokaler Titel');
      expect(api.saves.single['markdown'], 'Letztes Zeichen!');
    },
  );

  testWidgets(
    'offline navigation retains encrypted draft and pauses only on explicit keep',
    (tester) async {
      final api = _FakeApi(_documentData())..failure = StateError('Offline');
      Future<bool> Function()? guard;
      await tester.pumpWidget(
        _app(api, _document(), guard: (_, value) => guard = value),
      );
      await tester.pumpAndSettle();
      final peer = _peer(tester);
      peer.edit('Lokaler Predigttext');
      final stay = guard!();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hierbleiben'));
      await tester.pumpAndSettle();
      expect(await stay, isFalse);
      expect(peer.locked, isFalse);
      final raw = await const FlutterSecureStorage().read(key: _draftKey);
      expect(asMap(jsonDecode(raw!))['markdown'], 'Lokaler Predigttext');
      final leave = guard!();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Auf Gerät behalten und verlassen'));
      await tester.pumpAndSettle();
      expect(await leave, isTrue);
      expect(peer.locked, isTrue);
      expect(peer.commands.last, 'pause');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'conflicting recovery never overwrites until explicit server adoption',
    (tester) async {
      FlutterSecureStorage.setMockInitialValues({
        _draftKey: jsonEncode({
          'title': 'Mein Titel',
          'markdown': '> Mein Entwurf',
          'revision': 1,
        }),
      });
      final api = _FakeApi(
        _documentData(markdown: 'Neuer Serverstand', revision: 3),
      )..failure = const ApiException('Revision veraltet', status: 409);
      Future<bool> Function()? guard;
      await tester.pumpWidget(
        _app(api, _document(), guard: (_, value) => guard = value),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Entwurf öffnen'));
      await tester.pumpAndSettle();
      final navigation = guard!();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hierbleiben'));
      await tester.pumpAndSettle();
      expect(await navigation, isFalse);
      expect(api.saves.single['revision'], 1);
      await tester.tap(find.text('Fassungen vergleichen'));
      await tester.pumpAndSettle();
      expect(find.text('Dein Entwurf: Mein Titel'), findsOneWidget);
      await tester.tap(find.text('Serverfassung übernehmen'));
      await tester.pumpAndSettle();
      expect(_peer(tester).current['markdown'], 'Neuer Serverstand');
      expect(api.saves, hasLength(1));
      expect(await const FlutterSecureStorage().read(key: _draftKey), isNull);
    },
  );

  testWidgets(
    'metadata reserves text queue and passes latest revision back to web',
    (tester) async {
      final api = _FakeApi(_documentData());
      await tester.pumpWidget(_app(api, _document()));
      await tester.pumpAndSettle();
      final peer = _peer(tester);
      peer.edit('Geändert');
      await tester.pump();
      await tester.tap(find.byTooltip('Dokumentoptionen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dokumentart ändern'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Speichern').last);
      await tester.pumpAndSettle();
      expect(api.saves, hasLength(1));
      expect(api.actions.single['fields']['revision'], 2);
      expect(peer.current['revision'], 3);
      expect(
        peer.commands,
        containsAllInOrder(['prepareMutation', 'finishMutation']),
      );
      expect(peer.commands.last, 'finishMutation');
      expect(peer.locked, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'compact native header stays bounded with large text and keyboard resize',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final api = _FakeApi(_documentData());
      await tester.pumpWidget(_app(api, _document(), textScale: 2));
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byKey(const Key('document-text-surface'))).height,
        greaterThan(400),
      );
      await tester.binding.setSurfaceSize(const Size(320, 300));
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byKey(const Key('document-text-surface'))).height,
        greaterThan(100),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'touch insert menu sends bounded web command without native source edits',
    (tester) async {
      final api = _FakeApi(_documentData());
      await tester.pumpWidget(_app(api, _document()));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Dokumentoptionen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Einfügen …'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Überschrift 2'));
      await tester.pumpAndSettle();
      expect(_peer(tester).commands.last, 'insert');
      expect(api.saves, isEmpty);
      await tester.tap(find.text('Lesen'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Dokumentoptionen'));
      await tester.pumpAndSettle();
      expect(find.text('Einfügen …'), findsNothing);
      expect(find.text('PDF exportieren'), findsOneWidget);
    },
  );
  testWidgets(
    'late editor handshake in hidden branch pauses before it can retain focus',
    (tester) async {
      final api = _FakeApi(_documentData());
      final ready = Completer<void>();
      final active = ValueNotifier<bool>(true);
      addTearDown(active.dispose);
      final document = DocumentEditor(
        path: '/notes/one',
        webEditorBuilder: (context, controller, restore, reading, retry) =>
            TestWebEditorPeer(
              controller: controller,
              restore: restore,
              readOnly: reading,
              readyDelay: ready.future,
            ),
      );
      await tester.pumpWidget(
        _app(
          api,
          ValueListenableBuilder<bool>(
            valueListenable: active,
            builder: (context, enabled, child) =>
                TickerMode(enabled: enabled, child: child!),
            child: document,
          ),
        ),
      );
      await tester.pumpAndSettle();
      active.value = false;
      await tester.pump();
      ready.complete();
      await tester.pumpAndSettle();
      final peer = _peer(tester);
      expect(peer.commands, containsAllInOrder(['initialize', 'pause']));
      expect(peer.locked, isTrue);
      active.value = true;
      await tester.pumpAndSettle();
      expect(peer.commands.last, 'resume');
      expect(peer.locked, isFalse);
      expect(api.saves, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'unreadable secure draft prevents editor initialization and remains stored',
    (tester) async {
      FlutterSecureStorage.setMockInitialValues({_draftKey: 'invalid-json'});
      final api = _FakeApi(_documentData());
      await tester.pumpWidget(_app(api, _document()));
      await tester.pumpAndSettle();
      expect(
        find.text('Der lokale Entwurf konnte nicht gelesen werden.'),
        findsOneWidget,
      );
      expect(find.byType(TestWebEditorPeer), findsNothing);
      expect(
        await const FlutterSecureStorage().read(key: _draftKey),
        'invalid-json',
      );
      expect(api.saves, isEmpty);
    },
  );

  testWidgets('canceling external navigation resumes the same editor', (
    tester,
  ) async {
    final api = _FakeApi(_documentData());
    await tester.pumpWidget(_app(api, _document()));
    await tester.pumpAndSettle();
    final peer = _peer(tester);
    peer.emit('navigate', {'path': 'https://example.org/article'});
    await tester.pumpAndSettle();
    expect(find.text('Externen Link öffnen?'), findsOneWidget);
    expect(peer.locked, isTrue);
    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();
    expect(peer.locked, isFalse);
    expect(peer.commands.last, 'resume');
    expect(api.saves, isEmpty);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'native status reports web autosave progress and failure without a manual command',
    (tester) async {
      final api = _FakeApi(_documentData());
      await tester.pumpWidget(_app(api, _document()));
      await tester.pumpAndSettle();
      final peer = _peer(tester);
      peer.edit('Neu');
      peer.current['status'] = 'saving';
      peer.emit('state');
      await tester.pump();
      expect(find.byTooltip('Speichert …'), findsOneWidget);
      peer.current['status'] = 'error';
      peer.emit('state');
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Änderungen konnten nicht gespeichert werden. Bitte erneut speichern.',
        ),
        findsOneWidget,
      );
      expect(find.text('Speichern wiederholen'), findsOneWidget);
      peer.saved = Map.of(peer.current);
      peer.current['status'] = 'saved';
      peer.emit('state');
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Änderungen konnten nicht gespeichert werden. Bitte erneut speichern.',
        ),
        findsNothing,
      );
      expect(find.byTooltip('Gespeichert'), findsOneWidget);
      expect(api.saves, isEmpty);
    },
  );
}
