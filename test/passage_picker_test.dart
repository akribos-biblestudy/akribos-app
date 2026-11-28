import 'package:akribos_app/core/api_client.dart';
import 'package:akribos_app/features/reader/passage_picker.dart';
import 'package:akribos_app/theme/akribos_theme.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class NavigationApi extends AppApi {
  NavigationApi() : super(server: 'https://example.test', cookies: CookieJar());
  String? requested;
  bool fail = false;
  bool empty = false;

  @override
  Future<dynamic> get(String path) async {
    requested = path;
    if (fail) throw Exception('offline');
    return {
      'books': [
        if (!empty) ...[
          {
            'book': 1,
            'chapters': [1, 3],
          },
          {
            'book': 18,
            'chapters': [1],
          },
          {'book': 19, 'chapters': List.generate(150, (i) => i + 1)},
          {
            'book': 20,
            'chapters': [1, 3],
          },
          {
            'book': 23,
            'chapters': [1],
          },
          {
            'book': 43,
            'chapters': [5, 1, 3, 3, 0, 22],
          },
          {
            'book': 53,
            'chapters': [1, 3],
          },
          {
            'book': 66,
            'chapters': [1, 22],
          },
        ],
      ],
    };
  }
}

Finder _book(int id) => find.byKey(ValueKey('passage-book-$id'));
Finder _chapter(int number) => find.byKey(ValueKey('passage-chapter-$number'));
Finder get _bookList => find.byKey(const ValueKey('passage-books-scroll'));
Finder get _chapterList =>
    find.byKey(const ValueKey('passage-chapters-scroll'));
Finder get _chapterScrollable =>
    find.descendant(of: _chapterList, matching: find.byType(Scrollable));

void _expectCentered(WidgetTester tester, Finder row, Finder viewport) {
  expect(row, findsOneWidget);
  expect(tester.getCenter(row).dy, closeTo(tester.getCenter(viewport).dy, .1));
  expect(tester.widget<Semantics>(row).properties.selected, isTrue);
}

Future<void> _openPicker(
  WidgetTester tester,
  NavigationApi api, {
  Json initial = const {'book': 43, 'chapter': 3},
  VoidCallback? afterDismiss,
  ValueChanged<String?>? result,
  Map<int, List<int>>? localChapters,
  Size size = const Size(414, 850),
  double textScale = 1,
  double keyboard = 0,
  bool eInk = false,
  bool isLexicon = false,
  Brightness brightness = Brightness.light,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAkribosTheme(brightness, eInk: eInk),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
          viewInsets: EdgeInsets.only(bottom: keyboard),
        ),
        child: child!,
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              final value = await showModalBottomSheet<String>(
                context: context,
                isScrollControlled: true,
                showDragHandle: true,
                builder: (_) => localChapters == null
                    ? PassagePicker(
                        initial: initial,
                        resourceId: 'my resource',
                        api: api,
                        isLexicon: isLexicon,
                      )
                    : PassagePicker.local(
                        initial: initial,
                        chapters: localChapters,
                      ),
              );
              result?.call(value);
              afterDismiss?.call();
            },
            child: const Text('Öffnen'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Öffnen'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('opens a resource-specific chapter from the two panes', (
    tester,
  ) async {
    final api = NavigationApi();
    String? selection;
    await _openPicker(tester, api, result: (value) => selection = value);
    expect(api.requested, '/api/reader/resources/my%20resource/navigation');
    expect(find.text('Johannes'), findsNWidgets(2));
    expect(_book(40), findsNothing);
    expect(_chapter(1), findsOneWidget);
    expect(_chapter(3), findsOneWidget);
    expect(_chapter(2), findsNothing);
    expect(_chapter(22), findsNothing);
    expect(_bookList, findsOneWidget);
    expect(_chapterList, findsOneWidget);
    expect(find.byType(GridView), findsNothing);
    expect(find.byType(DropdownButton<int>), findsNothing);
    await tester.tap(_chapter(5));
    await tester.pumpAndSettle();
    expect(selection, 'Joh5');
  });

  for (final current in [1, 118, 150]) {
    testWidgets('centers Psalmen and chapter $current exactly on opening', (
      tester,
    ) async {
      await _openPicker(
        tester,
        NavigationApi(),
        initial: {'book': 19, 'chapter': current},
      );
      _expectCentered(tester, _book(19), _bookList);
      _expectCentered(tester, _chapter(current), _chapterList);
    });
  }

  testWidgets('centers sparse first and last entries and reflects reopening', (
    tester,
  ) async {
    final initial = <String, dynamic>{'book': 1, 'chapter': 1};
    await _openPicker(tester, NavigationApi(), initial: initial);
    _expectCentered(tester, _book(1), _bookList);
    _expectCentered(tester, _chapter(1), _chapterList);
    await tester.tap(find.byTooltip('Schließen'));
    await tester.pumpAndSettle();

    initial.addAll({'book': 66, 'chapter': 22});
    await tester.tap(find.text('Öffnen'));
    await tester.pumpAndSettle();
    _expectCentered(tester, _book(66), _bookList);
    _expectCentered(tester, _chapter(22), _chapterList);
    expect(_chapter(2), findsNothing);
  });

  testWidgets('scrolls Psalm 1–150 independently and opens the last chapter', (
    tester,
  ) async {
    String? selection;
    await _openPicker(
      tester,
      NavigationApi(),
      initial: const {'book': 19, 'chapter': 118},
      result: (value) => selection = value,
    );
    await tester.tap(_chapter(119));
    await tester.pumpAndSettle();
    expect(selection, 'Ps119');
    await tester.tap(find.text('Öffnen'));
    await tester.pumpAndSettle();

    final divider = find.descendant(
      of: find.byKey(const ValueKey('passage-chapters-pane')),
      matching: find.byType(Divider),
    );
    final dividerBounds = tester.getRect(divider);
    expect(
      dividerBounds.top,
      greaterThan(tester.getRect(find.text('150 Kapitel')).bottom),
    );
    expect(dividerBounds.bottom, lessThan(tester.getRect(_chapterList).top));

    await tester.scrollUntilVisible(
      _chapter(1),
      -650,
      scrollable: _chapterScrollable,
    );
    await tester.pumpAndSettle();
    final openedBookY = tester.getCenter(_book(19)).dy;
    final firstY = tester.getCenter(_chapter(1)).dy;
    await tester.tap(find.text('Psalmen').first);
    await tester.pumpAndSettle();
    expect(tester.getCenter(_chapter(1)).dy, closeTo(firstY, .1));

    await tester.scrollUntilVisible(
      _chapter(150),
      650,
      scrollable: _chapterScrollable,
    );
    expect(tester.getCenter(_book(19)).dy, closeTo(openedBookY, .1));
    expect(tester.getRect(divider), dividerBounds);
    expect(find.byTooltip('Nächste Kapitel'), findsNothing);
    await tester.tap(_chapter(150));
    await tester.pumpAndSettle();
    expect(selection, 'Ps150');
  });

  testWidgets('switches testaments and updates the chapter pane in place', (
    tester,
  ) async {
    await _openPicker(tester, NavigationApi());
    await tester.tap(find.text('Altes Testament'));
    await tester.pumpAndSettle();
    expect(_book(43), findsNothing);
    expect(find.text('Bücher Mose'), findsOneWidget);
    expect(find.text('Poesie und Weisheit'), findsOneWidget);
    await tester.ensureVisible(_book(19));
    final position = tester.getCenter(_book(19)).dy;
    await tester.tap(_book(19));
    await tester.pumpAndSettle();
    expect(tester.getCenter(_book(19)).dy, closeTo(position, .1));
    expect(find.text('150 Kapitel'), findsOneWidget);
    expect(_chapter(1), findsOneWidget);
  });

  testWidgets('uses chapter evidence and skips API traffic in local mode', (
    tester,
  ) async {
    final api = NavigationApi();
    String? selection;
    await _openPicker(
      tester,
      api,
      initial: const {'book': 19, 'chapter': 118},
      localChapters: {
        19: [118, 119, 150, 151],
      },
      result: (value) => selection = value,
    );
    expect(api.requested, isNull);
    expect(find.byType(TextField), findsNothing);
    expect(_chapter(120), findsNothing);
    expect(_chapter(151), findsOneWidget);
    _expectCentered(tester, _book(19), _bookList);
    _expectCentered(tester, _chapter(118), _chapterList);
    await tester.tap(_chapter(119));
    await tester.pumpAndSettle();
    expect(selection, 'Ps119');
  });

  testWidgets('retains the lexicon selection without a navigation request', (
    tester,
  ) async {
    final api = NavigationApi();
    await _openPicker(tester, api, isLexicon: true);
    expect(api.requested, isNull);
    expect(_book(40), findsOneWidget);
    _expectCentered(tester, _chapter(3), _chapterList);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('offers retry and falls back to an available testament', (
    tester,
  ) async {
    final api = NavigationApi()..fail = true;
    await _openPicker(tester, api);
    expect(
      find.text('Die Buchauswahl konnte nicht geladen werden.'),
      findsOneWidget,
    );
    api.fail = false;
    await tester.tap(find.text('Erneut versuchen'));
    await tester.pumpAndSettle();
    _expectCentered(tester, _book(43), _bookList);
    _expectCentered(tester, _chapter(3), _chapterList);
    await tester.tap(find.byTooltip('Schließen'));
    await tester.pumpAndSettle();
    final local = NavigationApi();
    // Only the other testament and a sparse, nonmatching chapter are present.
    await _openPicker(
      tester,
      local,
      initial: const {'book': 43, 'chapter': 3},
      localChapters: {
        1: [3],
      },
    );
    expect(find.text('Altes Testament'), findsOneWidget);
    expect(_book(1), findsOneWidget);
    expect(_chapter(1), findsNothing);
    expect(_chapter(3), findsOneWidget);
  });

  testWidgets('Back, close and direct reference keep their route contract', (
    tester,
  ) async {
    String? result;
    var dismissals = 0;
    await _openPicker(
      tester,
      NavigationApi(),
      result: (value) => result = value,
      afterDismiss: () => dismissals++,
    );
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Buch und Kapitel'), findsNothing);
    expect(dismissals, 1);
    expect(result, isNull);

    await tester.tap(find.text('Öffnen'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), ' Joh 3,16 ');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(result, 'Joh 3,16');
  });

  testWidgets('category colors supplement labels in light, dark and E-Ink', (
    tester,
  ) async {
    Color? color(Finder finder) => tester
        .widget<Material>(
          find.descendant(of: finder, matching: find.byType(Material)).first,
        )
        .color;
    for (final (brightness, eInk) in [
      (Brightness.light, false),
      (Brightness.dark, false),
      (Brightness.light, true),
    ]) {
      await _openPicker(
        tester,
        NavigationApi(),
        initial: const {'book': 19, 'chapter': 118},
        brightness: brightness,
        eInk: eInk,
      );
      expect(find.text('Poesie und Weisheit'), findsOneWidget);
      expect(find.text('Propheten'), findsOneWidget);
      expect(color(_book(18)) == color(_book(23)), eInk);
      _expectCentered(tester, _book(19), _bookList);
      await tester.tap(find.byTooltip('Schließen'));
      await tester.pumpAndSettle();
    }
  });

  testWidgets('keeps full names and touch targets at 200% on narrow phones', (
    tester,
  ) async {
    await _openPicker(
      tester,
      NavigationApi(),
      initial: const {'book': 53, 'chapter': 3},
      size: const Size(320, 850),
      textScale: 2,
      eInk: true,
    );
    expect(tester.takeException(), isNull);
    expect(find.text('2. Thessalonicher'), findsOneWidget);
    _expectCentered(tester, _book(53), _bookList);
    _expectCentered(tester, _chapter(3), _chapterList);
    expect(tester.getSize(_book(53)).height, greaterThanOrEqualTo(48));
    expect(tester.getSize(_chapter(3)).height, greaterThanOrEqualTo(48));
  });

  for (final (scale, keyboard) in [(1.0, 0.0), (2.0, 0.0), (2.0, 160.0)]) {
    testWidgets(
      'shows centered selections in landscape at $scale×, keyboard $keyboard',
      (tester) async {
        await _openPicker(
          tester,
          NavigationApi(),
          initial: const {'book': 19, 'chapter': 118},
          size: const Size(640, 360),
          textScale: scale,
          keyboard: keyboard,
        );
        _expectCentered(tester, _book(19), _bookList);
        _expectCentered(tester, _chapter(118), _chapterList);
        expect(_book(19).hitTestable(), findsOneWidget);
        expect(_chapter(118).hitTestable(), findsOneWidget);
        expect(tester.getCenter(_chapter(118)).dy, lessThan(360 - keyboard));
        expect(tester.takeException(), isNull);
      },
    );
  }
}
