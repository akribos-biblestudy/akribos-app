import 'dart:async';

import 'package:akribos_app/core/api_client.dart';
import 'package:akribos_app/features/reader/reader_notes_companion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'native_reader_test.dart' show ReaderApi, app, readerFixture;

class NotesApi extends ReaderApi {
  NotesApi() : super(readerFixture());

  Completer<dynamic>? pendingChapter;

  @override
  Future<dynamic> get(String path) async {
    reads.add(path);
    final chapter = Uri.parse(path).queryParameters['passage'];
    if (chapter == 'Joh2' && pendingChapter != null) {
      return pendingChapter!.future;
    }
    return {
      'documents': [
        {
          'id': 'own-note',
          'title': chapter == null ? 'Alle Notizen' : 'Notiz zu $chapter',
          'excerpt': 'Eigene Gedanken zum Text',
        },
      ],
    };
  }

  @override
  Future<ApiResult> action(String path, String action, Json fields) async {
    actions.add({'path': path, 'action': action, 'fields': fields});
    return const ApiResult(
      type: 'redirect',
      status: 303,
      location: '/notes/new-note?returnTo=%2F',
    );
  }
}

void main() {
  Future<void> mount(
    WidgetTester tester,
    NotesApi api,
    GlobalKey<ReaderNotesCompanionState> key, {
    Future<bool> Function()? flush,
    Future<void> Function(String)? open,
    bool active = true,
  }) async {
    await tester.pumpWidget(
      app(
        api,
        ReaderNotesCompanion(
          key: key,
          reference: const {'book': 43, 'chapter': 1},
          active: active,
          flush: flush ?? () async => true,
        ),
        open: open,
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('follows chapters, never refetches for every verse', (
    tester,
  ) async {
    final api = NotesApi();
    addTearDown(api.dispose);
    final key = GlobalKey<ReaderNotesCompanionState>();
    await mount(tester, api, key);
    expect(api.reads, ['/api/documents?kind=note&passage=Joh1']);
    for (var verse = 1; verse < 8; verse++) {
      key.currentState!.follow({'book': 43, 'chapter': 1, 'verse': verse});
      await tester.pump();
    }
    expect(api.reads.length, 1);
    key.currentState!.follow({'book': 43, 'chapter': 2, 'verse': 1});
    await tester.pumpAndSettle();
    expect(find.text('Notiz zu Joh2'), findsOneWidget);
    expect(api.reads.last, '/api/documents?kind=note&passage=Joh2');
    expect(api.actions, isEmpty);
    expect(api.requests, isEmpty);
  });

  testWidgets('late responses never replace the current chapter notes', (
    tester,
  ) async {
    final api = NotesApi()..pendingChapter = Completer<dynamic>();
    addTearDown(api.dispose);
    final key = GlobalKey<ReaderNotesCompanionState>();
    await mount(tester, api, key);
    key.currentState!.follow({'book': 43, 'chapter': 2});
    await tester.pump();
    expect(find.text('Notiz zu Joh1'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    key.currentState!.follow({'book': 43, 'chapter': 3});
    await tester.pumpAndSettle();
    expect(find.text('Notiz zu Joh3'), findsOneWidget);
    api.pendingChapter!.complete({
      'documents': [
        {'id': 'stale-note', 'title': 'Veraltete Notiz'},
      ],
    });
    await tester.pumpAndSettle();
    expect(find.text('Veraltete Notiz'), findsNothing);
    expect(find.text('Notiz zu Joh3'), findsOneWidget);
  });

  testWidgets('chapter filter can be disabled across Bible translations', (
    tester,
  ) async {
    final api = NotesApi();
    addTearDown(api.dispose);
    final key = GlobalKey<ReaderNotesCompanionState>();
    await mount(tester, api, key);
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    expect(api.reads.last, '/api/documents?kind=note');
    final requests = api.reads.length;
    key.currentState!.follow({'book': 43, 'chapter': 2});
    await tester.pumpAndSettle();
    expect(api.reads.length, requests);
    expect(find.text('Alle Notizen'), findsOneWidget);
  });

  testWidgets('opening an existing note flushes and uses the shared editor', (
    tester,
  ) async {
    final api = NotesApi();
    addTearDown(api.dispose);
    final key = GlobalKey<ReaderNotesCompanionState>();
    final opened = <String>[];
    var mayLeave = false;
    var flushes = 0;
    await mount(
      tester,
      api,
      key,
      flush: () async {
        flushes++;
        return mayLeave;
      },
      open: (path) async => opened.add(path),
    );
    await tester.tap(find.text('Notiz zu Joh1'));
    await tester.pumpAndSettle();
    expect(opened, isEmpty);
    mayLeave = true;
    await tester.tap(find.text('Notiz zu Joh1'));
    await tester.pumpAndSettle();
    expect(opened, ['/notes/own-note?returnTo=%2F']);
    expect(flushes, 2);
    expect(api.actions, isEmpty);
  });

  testWidgets(
    'creating a note anchors the visible verse and opens the editor',
    (tester) async {
      final api = NotesApi();
      addTearDown(api.dispose);
      final key = GlobalKey<ReaderNotesCompanionState>();
      final opened = <String>[];
      await mount(tester, api, key, open: (path) async => opened.add(path));
      key.currentState!.follow({'book': 43, 'chapter': 1, 'verse': 5});
      await tester.tap(find.text('Neue Notiz'));
      await tester.pumpAndSettle();
      expect(find.text('Joh1,5'), findsOneWidget);
      await tester.enterText(
        find.byType(TextFormField).first,
        'Meine Gedanken',
      );
      await tester.tap(find.text('Anlegen'));
      await tester.pumpAndSettle();
      expect(api.actions, [
        {
          'path': '/notes',
          'action': 'create',
          'fields': {
            'title': 'Meine Gedanken',
            'passage': 'Joh1,5',
            'kind': 'note',
            'returnTo': '/',
          },
        },
      ]);
      expect(opened, ['/notes/new-note?returnTo=%2F']);
    },
  );

  testWidgets('returning from the editor refreshes note summaries', (
    tester,
  ) async {
    final api = NotesApi();
    addTearDown(api.dispose);
    final key = GlobalKey<ReaderNotesCompanionState>();
    await mount(tester, api, key);
    await mount(tester, api, key, active: false);
    expect(api.reads.length, 1);
    await mount(tester, api, key);
    expect(api.reads.length, 2);
  });

  testWidgets('guests see sign in without requesting private documents', (
    tester,
  ) async {
    final api = NotesApi()..bootstrap['user'] = null;
    addTearDown(api.dispose);
    final opened = <String>[];
    await mount(
      tester,
      api,
      GlobalKey<ReaderNotesCompanionState>(),
      open: (path) async => opened.add(path),
    );
    expect(api.reads, isEmpty);
    await tester.tap(find.text('Anmelden'));
    await tester.pumpAndSettle();
    expect(opened, ['/login']);
  });
}
