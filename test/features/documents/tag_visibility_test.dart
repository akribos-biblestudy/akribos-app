import 'package:akribos_app/core/api_client.dart';
import 'package:akribos_app/core/app_scope.dart';
import 'package:akribos_app/features/documents/document_editor.dart';
import 'package:akribos_app/features/documents/documents_screen.dart';
import 'package:akribos_app/features/reader/reader_notes.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

class _TagApi extends AppApi {
  _TagApi(this.data)
    : super(server: 'https://example.test', cookies: CookieJar());

  final Json data;
  final requests = <Uri>[];

  @override
  Future<Json> page(String path) async => data;

  @override
  Future<dynamic> get(String path) async {
    requests.add(Uri.parse(path));
    return Uri.parse(path).path == '/api/documents'
        ? data
        : <String, dynamic>{};
  }
}

List<Json> _tags() => List.generate(
  1000,
  (index) => {'id': '$index', 'path': 'Tag${index.toString().padLeft(4, '0')}'},
);

const _document = <String, dynamic>{
  'id': 'one',
  'kind': 'note',
  'title': 'Meine Notiz',
  'excerpt': 'Ein Gedanke zum Bibeltext.',
  'bodyMarkdown': 'Ein Gedanke zum Bibeltext.',
  'bodyHtml': '<p>Ein Gedanke zum Bibeltext.</p>',
  'revision': 1,
};

Widget _app(AppApi api, Widget child, {List<String>? opened}) => AppScope(
  api: api,
  open: (path) async => opened?.add(path),
  refreshSession: () async {},
  setNavigationGuard: (_, _) {},
  setTheme: (_) {},
  themeMode: ThemeMode.light,
  child: MaterialApp(home: Scaffold(body: child)),
);

Finder _tagField() => find.byWidgetPredicate(
  (widget) =>
      widget is TextField && widget.decoration?.labelText == 'Tag / Untertag',
);

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets(
    '1000 library tags stay hidden and the tag filter remains usable',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final opened = <String>[];
      final api = _TagApi({
        'tagTree': _tags(),
        'documents': [_document],
        'filters': {},
        'pagination': {'page': 1, 'pageCount': 1},
      });
      await tester.pumpWidget(
        _app(api, const DocumentsScreen(path: '/notes'), opened: opened),
      );
      await tester.pumpAndSettle();
      expect(find.text('Meine Notiz').hitTestable(), findsOneWidget);
      expect(find.byType(ActionChip), findsNothing);
      expect(find.text('Tag0999'), findsNothing);

      await tester.tap(find.byTooltip('Filtern'));
      await tester.pumpAndSettle();
      await tester.enterText(_tagField(), 'Tag0999');
      await tester.tap(find.text('Anwenden'));
      await tester.pumpAndSettle();
      expect(Uri.parse(opened.single).queryParameters['tag'], 'Tag0999');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('reader filters 1000 tags on demand without a huge dropdown', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final filters = <String>[];
    final api = _TagApi({
      'tags': _tags(),
      'documents': [_document],
    });
    await tester.pumpWidget(
      _app(
        api,
        ReaderNotes(
          reference: 'Joh1',
          resourceId: 'BIBLE',
          initialState: '',
          onFilters: (_, tag, _) => filters.add(tag),
          onOpen: (_) {},
          onCreate: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Meine Notiz').hitTestable(), findsOneWidget);
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    expect(find.text('Tag0999'), findsNothing);

    await tester.tap(find.text('Filtern'));
    await tester.pumpAndSettle();
    await tester.enterText(_tagField(), ' Tag0999 ');
    await tester.tap(find.text('Anwenden'));
    await tester.pumpAndSettle();
    expect(filters, ['Tag0999']);
    expect(api.requests.last.queryParameters['tag'], 'Tag0999');
    expect(find.text('Tagfilter aktiv'), findsOneWidget);

    await tester.tap(find.byTooltip('Tagfilter zurücksetzen'));
    await tester.pumpAndSettle();
    expect(filters, ['Tag0999', '']);
    expect(api.requests.last.queryParameters.containsKey('tag'), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'published note tags expand only on request, even with 1000 tags',
    (tester) async {
      final api = _TagApi({
        'publication': {..._document, 'tags': _tags()},
      });
      await tester.pumpWidget(
        _app(api, const DocumentsScreen(path: '/notes/published/one')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Meine Notiz').hitTestable(), findsOneWidget);
      expect(find.byType(Chip), findsNothing);

      await tester.tap(find.text('Tags'));
      await tester.pumpAndSettle();
      expect(find.byType(Chip), findsNWidgets(1000));
      expect(find.text('Tag0999'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'editor hides 1000 tags by default and keeps tag editing available',
    (tester) async {
      final api = _TagApi({
        'user': {'id': 'user'},
        'document': _document,
        'tags': _tags(),
        'passages': [],
        'bibles': [],
      });
      await tester.pumpWidget(
        _app(api, const DocumentEditor(path: '/notes/one')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(Chip), findsNothing);
      expect(find.text('Tag0999'), findsNothing);

      await tester.tap(find.byTooltip('Dokumentoptionen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Details'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Tags'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tags'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.widgetWithText(ActionChip, 'Bearbeiten'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ActionChip, 'Bearbeiten'));
      await tester.pumpAndSettle();
      expect(find.text('Tags bearbeiten'), findsOneWidget);
      final field = tester.widget<TextFormField>(find.byType(TextFormField));
      expect(field.controller!.text.split(', '), hasLength(1000));
      expect(field.controller!.text, contains('Tag0999'));
      await tester.tap(find.text('Abbrechen'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
