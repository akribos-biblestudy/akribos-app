import 'package:akribos_app/core/api_client.dart';
import 'package:akribos_app/features/reader/passage_picker.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class NavigationApi extends AppApi {
  NavigationApi() : super(server: 'https://example.test', cookies: CookieJar());
  String? requested;
  bool fail = false;

  @override
  Future<dynamic> get(String path) async {
    requested = path;
    if (fail) throw Exception('offline');
    return {
      'books': [
        {
          'book': 1,
          'chapters': [1, 3],
        },
        {'book': 19, 'chapters': List.generate(150, (i) => i + 1)},
        {
          'book': 43,
          'chapters': [1, 3, 5],
        },
      ],
    };
  }
}

void main() {
  Future<void> openPicker(
    WidgetTester tester,
    NavigationApi api,
    void Function(String?) result,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async => result(
                await showModalBottomSheet<String>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => PassagePicker(
                    initial: const {'book': 43, 'chapter': 3},
                    resourceId: 'my resource',
                    api: api,
                  ),
                ),
              ),
              child: const Text('Öffnen'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Öffnen'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'shows resource-specific abbreviations and selects an existing chapter',
    (tester) async {
      final api = NavigationApi();
      String? selection;
      await openPicker(tester, api, (value) => selection = value);
      expect(api.requested, '/api/reader/resources/my%20resource/navigation');
      expect(find.text('Joh'), findsOneWidget);
      expect(find.text('Mt'), findsNothing);
      await tester.tap(find.text('Joh'));
      await tester.pumpAndSettle();
      expect(find.text('3'), findsOneWidget);
      expect(find.text('2'), findsNothing);
      await tester.tap(find.text('5'));
      await tester.pumpAndSettle();
      expect(selection, 'Joh5');
    },
  );

  testWidgets('switches testaments, pages chapters and returns to books', (
    tester,
  ) async {
    final api = NavigationApi();
    await openPicker(tester, api, (_) {});
    await tester.tap(find.text('AT'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ps'));
    await tester.pumpAndSettle();
    expect(find.text('1–42 / 150'), findsOneWidget);
    await tester.tap(find.byTooltip('Nächste Kapitel'));
    await tester.pumpAndSettle();
    expect(find.text('43–84 / 150'), findsOneWidget);
    await tester.tap(find.text('Ps'));
    await tester.pumpAndSettle();
    expect(find.text('1Mo'), findsOneWidget);
  });

  testWidgets('offers retry when navigation cannot be loaded', (tester) async {
    final api = NavigationApi()..fail = true;
    await openPicker(tester, api, (_) {});
    expect(
      find.text('Die Buchauswahl konnte nicht geladen werden.'),
      findsOneWidget,
    );
    api.fail = false;
    await tester.tap(find.text('Erneut versuchen'));
    await tester.pumpAndSettle();
    expect(find.text('Joh'), findsOneWidget);
  });

  testWidgets('keeps long abbreviations readable at large text scale', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = NavigationApi();
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(400, 850),
            textScaler: TextScaler.linear(2),
          ),
          child: Scaffold(
            body: PassagePicker(
              initial: const {'book': 1},
              resourceId: 'bible',
              api: api,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('1Mo'), findsOneWidget);
  });
}
