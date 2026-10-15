import 'dart:async';
import 'dart:convert';

import 'package:akribos_app/core/api_client.dart';
import 'package:akribos_app/core/app_scope.dart';
import 'package:akribos_app/features/collections/collections_screen.dart';
import 'package:akribos_app/features/documents/document_editor.dart';
import 'package:akribos_app/features/documents/documents_screen.dart';
import 'package:akribos_app/features/documents/rich_markdown_editor.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as q;
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
    if (failure != null) throw failure!;
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
    localizationsDelegates: const [q.FlutterQuillLocalizations.delegate],
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: Scaffold(body: child),
  ),
);

RichMarkdownEditor _editor(WidgetTester tester) =>
    tester.widget<RichMarkdownEditor>(find.byType(RichMarkdownEditor));

String _replaceBody(WidgetTester tester, String text) {
  final rich = _editor(tester).controller;
  rich.quill.replaceText(
    0,
    rich.quill.document.length - 1,
    text,
    TextSelection.collapsed(offset: text.length),
  );
  return rich.markdown;
}

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
      final firstMarkdown = _replaceBody(tester, 'Erster Text');
      await tester.pump(const Duration(milliseconds: 1300));
      expect(api.saves, hasLength(1));
      final latestMarkdown = _replaceBody(tester, 'Text während der Anfrage');
      api.pending = null;
      first.complete({
        'document': {
          'id': 'one',
          'kind': 'note',
          'title': 'Titel',
          'bodyMarkdown': firstMarkdown,
          'revision': 2,
        },
      });
      await tester.pump();
      expect(_editor(tester).controller.markdown, latestMarkdown);
      final canNavigate = guard!();
      await tester.pump();
      expect(await canNavigate, isTrue);
      expect(api.saves, hasLength(2));
      expect(api.saves.last['revision'], 2);
      expect(api.saves.last['markdown'], latestMarkdown);
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
    expect(find.byType(TextField), findsNothing);
    expect(_editor(tester).readOnly, isTrue);
    expect(find.byTooltip('Details'), findsNothing);
    await tester.tap(find.text('Bearbeiten'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    expect(_editor(tester).readOnly, isFalse);
  });

  testWidgets(
    'reading toggle preserves raw Markdown, controller, history and scroll without saving',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final source =
          '# Titel  \n\n${List.filled(50, 'Ein Absatz mit **Fett** und [Link](/Joh3,16).\n\n').join()}';
      final api = _FakeApi(_documentData(markdown: source));
      asMap(api.data['document'])['title'] = 'Getragen durch Hoffnung';
      await tester.pumpWidget(
        _app(api, const DocumentEditor(path: '/notes/one')),
      );
      await tester.pumpAndSettle();
      final title = tester.widget<TextField>(find.byType(TextField));
      expect(title.maxLines, 2);
      expect(title.controller!.text, 'Getragen durch Hoffnung');
      final bounds = tester.getRect(find.byType(RichMarkdownEditor));
      final rich = _editor(tester).controller;
      final document = rich.quill.document;
      final scroll = _editor(tester).scrollController!;
      rich.quill.updateSelection(
        const TextSelection.collapsed(offset: 5),
        q.ChangeSource.local,
      );
      await tester.pump();
      scroll.jumpTo(250);
      await tester.pump();
      final offset = scroll.offset;
      final canUndo = rich.quill.hasUndo;
      expect(
        tester.getSize(find.byType(RichMarkdownEditor)).height,
        greaterThan(500),
      );
      for (final mode in ['Lesen', 'Bearbeiten', 'Lesen']) {
        await tester.tap(find.text(mode));
        await tester.pumpAndSettle();
        expect(identical(_editor(tester).controller, rich), isTrue);
        expect(identical(rich.quill.document, document), isTrue);
        expect(rich.markdown, source);
        expect(rich.quill.hasUndo, canUndo);
        expect(scroll.offset, closeTo(offset, 1));
        expect(tester.getRect(find.byType(RichMarkdownEditor)), bounds);
      }
      expect(find.byType(TextField), findsNothing);
      expect(find.byTooltip('Einfügen'), findsNothing);
      expect(find.byTooltip('Details'), findsNothing);
      await tester.pump(const Duration(seconds: 2));
      expect(api.saves, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'document actions stay at the right edge and insertion remains available without a plus button',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final api = _FakeApi(_documentData(markdown: 'Gedanke\n'));
      await tester.pumpWidget(
        _app(api, const DocumentEditor(path: '/notes/one'), textScale: 2.0),
      );
      await tester.pumpAndSettle();
      final header = find.byKey(const Key('document-header-actions'));
      final menu = find.byWidgetPredicate(
        (widget) =>
            widget is PopupMenuButton<String> &&
            widget.tooltip == 'Dokumentoptionen',
      );
      expect(find.byIcon(Icons.add), findsNothing);
      expect(
        tester.getRect(menu).right,
        closeTo(tester.getRect(header).right, 1),
      );
      await tester.tap(menu);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Einfügen …'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Überschrift 2'));
      await tester.pumpAndSettle();
      expect(_editor(tester).controller.markdown, contains('## Gedanke'));
      await tester.tap(find.text('Lesen'));
      await tester.pumpAndSettle();
      expect(
        tester.getRect(menu).right,
        closeTo(tester.getRect(header).right, 1),
      );
      await tester.tap(menu);
      await tester.pumpAndSettle();
      expect(find.text('Einfügen …'), findsNothing);
      expect(find.text('PDF exportieren'), findsOneWidget);
      await tester.tapAt(const Offset(8, 500));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 2));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('selection and title cursor movements never start autosave', (
    tester,
  ) async {
    final api = _FakeApi(_documentData());
    await tester.pumpWidget(
      _app(api, const DocumentEditor(path: '/notes/one')),
    );
    await tester.pumpAndSettle();
    final rich = _editor(tester).controller;
    rich.quill.updateSelection(
      const TextSelection(baseOffset: 0, extentOffset: 4),
      q.ChangeSource.local,
    );
    final title = tester.widget<TextField>(find.byType(TextField)).controller!;
    title.selection = const TextSelection.collapsed(offset: 2);
    await tester.pump(const Duration(seconds: 2));
    expect(api.saves, isEmpty);
    expect(rich.markdown, 'Lesetext');
  });

  testWidgets(
    'reading an unsaved local script works offline and keeps navigation protection',
    (tester) async {
      final api = _FakeApi(_documentData())..failure = StateError('Offline');
      Future<bool> Function()? guard;
      await tester.pumpWidget(
        _app(
          api,
          const DocumentEditor(path: '/notes/one'),
          guard: (_, callback) => guard = callback,
        ),
      );
      await tester.pumpAndSettle();
      final local = _replaceBody(tester, 'Lokaler neuer Predigttext');
      await tester.pump();
      await tester.tap(find.text('Lesen'));
      await tester.pumpAndSettle();
      expect(_editor(tester).readOnly, isTrue);
      expect(_editor(tester).controller.markdown, local);
      final navigation = guard!();
      await tester.pumpAndSettle();
      expect(
        find.text('Änderungen sind noch nicht gespeichert'),
        findsOneWidget,
      );
      await tester.tap(find.text('Hierbleiben'));
      await tester.pumpAndSettle();
      expect(await navigation, isFalse);
      expect(_editor(tester).controller.markdown, local);
      final raw = await const FlutterSecureStorage().read(
        key: 'document-draft:https://example.test:user:one',
      );
      expect(asMap(jsonDecode(raw!))['markdown'], local);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'recovered rich draft retains old revision and latest keystroke on immediate flush',
    (tester) async {
      FlutterSecureStorage.setMockInitialValues({
        'document-draft:https://example.test:user:one': jsonEncode({
          'title': 'Lokaler Titel',
          'markdown': 'Lokaler Entwurf',
          'revision': 1,
        }),
      });
      final api = _FakeApi(_documentData(markdown: 'Serverstand', revision: 3));
      Future<bool> Function()? guard;
      await tester.pumpWidget(
        _app(
          api,
          const DocumentEditor(path: '/notes/one'),
          guard: (_, callback) => guard = callback,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Entwurf öffnen'));
      await tester.pumpAndSettle();
      expect(_editor(tester).controller.markdown, 'Lokaler Entwurf');
      expect(api.saves, isEmpty);
      final local = _replaceBody(tester, 'Letztes Zeichen!');
      // No debounce or frame between editing and navigation: flush must observe it.
      final navigation = guard!();
      await tester.pumpAndSettle();
      expect(await navigation, isTrue);
      expect(api.saves.single['revision'], 1);
      expect(api.saves.single['title'], 'Lokaler Titel');
      expect(api.saves.single['markdown'], local);
    },
  );

  testWidgets(
    'rich editor remains bounded on narrow large text and keyboard resize',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final api = _FakeApi(_documentData());
      await tester.pumpWidget(
        _app(api, const DocumentEditor(path: '/notes/one'), textScale: 1.6),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byType(RichMarkdownEditor)).height,
        greaterThan(300),
      );
      await tester.binding.setSurfaceSize(const Size(320, 360));
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byType(RichMarkdownEditor)).height,
        greaterThan(60),
      );
      final bounds = tester.getRect(find.byType(RichMarkdownEditor));
      await tester.tap(find.text('Lesen'));
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byType(RichMarkdownEditor)), bounds);
      await tester.tap(find.text('Bearbeiten'));
      await tester.pumpAndSettle();
      api.failure = StateError('Offline');
      _replaceBody(tester, 'Offline mit Tastatur');
      await tester.pump(const Duration(milliseconds: 1300));
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byType(RichMarkdownEditor)).height,
        greaterThan(100),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('document menu exposes touch undo and redo only while editing', (
    tester,
  ) async {
    final api = _FakeApi(_documentData());
    await tester.pumpWidget(
      _app(api, const DocumentEditor(path: '/notes/one')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Dokumentoptionen'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<PopupMenuItem<String>>(
            find.widgetWithText(PopupMenuItem<String>, 'Rückgängig'),
          )
          .enabled,
      isFalse,
    );
    expect(
      tester
          .widget<PopupMenuItem<String>>(
            find.widgetWithText(PopupMenuItem<String>, 'Wiederholen'),
          )
          .enabled,
      isFalse,
    );
    Navigator.of(tester.element(find.text('Rückgängig'))).pop();
    await tester.pumpAndSettle();
    final latest = _replaceBody(tester, 'Neuer Gedanke');
    await tester.pump();
    await tester.tap(find.byTooltip('Dokumentoptionen'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<PopupMenuItem<String>>(
            find.widgetWithText(PopupMenuItem<String>, 'Rückgängig'),
          )
          .enabled,
      isTrue,
    );
    await tester.tap(find.text('Rückgängig'));
    await tester.pumpAndSettle();
    expect(_editor(tester).controller.markdown, 'Lesetext');
    await tester.tap(find.byTooltip('Dokumentoptionen'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<PopupMenuItem<String>>(
            find.widgetWithText(PopupMenuItem<String>, 'Wiederholen'),
          )
          .enabled,
      isTrue,
    );
    await tester.tap(find.text('Wiederholen'));
    await tester.pumpAndSettle();
    expect(_editor(tester).controller.markdown, latest);
    await tester.tap(find.text('Lesen'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Dokumentoptionen'));
    await tester.pumpAndSettle();
    expect(find.text('Rückgängig'), findsNothing);
    expect(find.text('Wiederholen'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
