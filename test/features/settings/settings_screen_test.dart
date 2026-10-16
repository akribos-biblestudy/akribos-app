import 'dart:convert';

import 'package:akribos_app/core/api_client.dart';
import 'package:akribos_app/core/app_scope.dart';
import 'package:akribos_app/features/account/account_screen.dart';
import 'package:akribos_app/features/reader/reader_screen.dart';
import 'package:akribos_app/features/reader/verse_text.dart';
import 'package:akribos_app/main.dart';
import 'package:akribos_app/widgets/action_form.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../reader/native_reader_test.dart' show ReaderApi, readerFixture;

class _SettingsApi extends ReaderApi {
  _SettingsApi() : super(readerFixture());
  int fontScale = 100;
  String defaultBible = '';
  bool accountOffline = false;
  final accountActions = <Json>[];
  final styles = <Json>[
    {'id': 'yellow', 'name': 'Verheißung', 'color': '#facc15'},
  ];

  @override
  Future<Json> loadBootstrap() async {
    bootstrap = {
      ...bootstrap,
      'readerFontScale': fontScale,
      'defaultBibleId': defaultBible,
    };
    return bootstrap;
  }

  @override
  Future<Json> page(String path) async {
    if (path == '/account') {
      if (accountOffline) {
        throw const ApiException('Test: Konto nicht erreichbar');
      }
      return {
        ...bootstrap,
        'hasPassword': true,
        'highlightStyles': jsonDecode(jsonEncode(styles)),
        'apiKeys': [
          {
            'id': 'private-key',
            'name': 'Verborgener API-Schlüssel',
            'scope': 'personal',
          },
        ],
      };
    }
    data['readerFontScale'] = fontScale;
    data['highlightStyles'] = jsonDecode(jsonEncode(styles));
    return super.page(path);
  }

  @override
  Future<ApiResult> action(String path, String action, Json fields) async {
    if (path != '/account') return super.action(path, action, fields);
    accountActions.add({
      'path': path,
      'action': action,
      'fields': Map.of(fields),
    });
    switch (action) {
      case 'reader':
        fontScale = int.parse(asString(fields['fontScale']));
      case 'defaultBible':
        defaultBible = asString(fields['defaultBibleId']);
      case 'renameHighlightStyle':
        styles.firstWhere((style) => style['id'] == fields['id'])['name'] =
            fields['name'];
      case 'addHighlightStyle':
        styles.add({
          'id': 'new-style',
          'name': fields['name'],
          'color': fields['color'],
        });
      default:
        throw StateError('Unexpected account action $action');
    }
    return const ApiResult(type: 'success', status: 200, data: {});
  }
}

Finder form(String action) =>
    find.byWidgetPredicate((w) => w is ActionForm && w.action == action);
Finder fieldIn(Finder parent, String label) => find.descendant(
  of: parent,
  matching: find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.labelText == label,
  ),
);

Future<void> submit(WidgetTester tester, String action) async {
  final save = find.descendant(
    of: form(action),
    matching: find.text('Speichern'),
  );
  await tester.ensureVisible(save);
  await tester.tap(save);
  await tester.pumpAndSettle();
}

Future<void> settings(WidgetTester tester) async {
  await tester.tap(find.text('Mehr'));
  await tester.pumpAndSettle();
  expect(find.text('Konto & Darstellung'), findsNothing);
  await tester.tap(find.text('Einstellungen'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'settings save existing account contracts and refresh reading font and style choices',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = _SettingsApi();
      addTearDown(api.dispose);
      await tester.pumpWidget(AkribosApp(api: api, enableLinks: false));
      await tester.pumpAndSettle();
      await AppScope.of(tester.element(find.byType(ReaderScreen)))
          .open('/Joh1,16');
      await tester.pumpAndSettle();
      final initialFont = tester
          .widget<VerseText>(find.byType(VerseText).first)
          .fontSize;
      final savedPath = (await api.localStore.read())?['path'];
      await settings(tester);
      expect(find.text('Darstellung'), findsOneWidget);
      expect(find.text('Leseschrift'), findsOneWidget);
      expect(find.text('Standardbibel'), findsOneWidget);
      expect(find.text('Markierungsfarben'), findsOneWidget);
      expect(find.text('API-Schlüssel'), findsNothing);
      final fontDropdown = find.descendant(
        of: form('reader'),
        matching: find.byType(DropdownButtonFormField<String>),
      );
      await tester.ensureVisible(fontDropdown);
      await tester.tap(fontDropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text('105 %').last);
      await tester.pumpAndSettle();
      await submit(tester, 'reader');
      expect(api.accountActions.last, {
        'path': '/account',
        'action': 'reader',
        'fields': {'fontScale': '105'},
      });
      await tester.tap(find.text('Lesen'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<VerseText>(find.byType(VerseText).first).fontSize,
        closeTo(initialFont * 1.05, .001),
      );
      expect((await api.localStore.read())?['path'], savedPath);

      await settings(tester);
      final bibleDropdown = find.descendant(
        of: form('defaultBible'),
        matching: find.byType(DropdownButtonFormField<String>),
      );
      await tester.ensureVisible(bibleDropdown);
      await tester.tap(bibleDropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bibelübersetzung 0').last);
      await tester.pumpAndSettle();
      await submit(tester, 'defaultBible');
      expect(api.accountActions.last['fields'], {'defaultBibleId': 'BIBLE0'});
      expect(api.bootstrap['defaultBibleId'], 'BIBLE0');

      final style = find.widgetWithText(ExpansionTile, 'Verheißung');
      await tester.ensureVisible(style);
      await tester.tap(style);
      await tester.pumpAndSettle();
      await tester.enterText(
        fieldIn(form('renameHighlightStyle'), 'Name'),
        'Zusagen',
      );
      await submit(tester, 'renameHighlightStyle');
      expect(api.accountActions.last['fields'], {
        'id': 'yellow',
        'name': 'Zusagen',
      });
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is ExpansionTile &&
              w.title is Text &&
              (w.title as Text).data == 'Zusagen',
        ),
        findsOneWidget,
      );
      final addName = fieldIn(form('addHighlightStyle'), 'Name');
      await tester.ensureVisible(addName);
      await tester.enterText(addName, 'Hoffnung');
      await tester.enterText(
        fieldIn(form('addHighlightStyle'), 'Farbe'),
        '#123abc',
      );
      await submit(tester, 'addHighlightStyle');
      expect(api.accountActions.last['fields'], {
        'name': 'Hoffnung',
        'color': '#123abc',
      });
      await tester.tap(find.text('Lesen'));
      await tester.pumpAndSettle();
      expect((await api.localStore.read())?['path'], savedPath);
      final verse = tester.widget<VerseText>(find.byType(VerseText).first);
      verse.onVerseNumber!();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('verse-action-marks')));
      await tester.pumpAndSettle();
      expect(find.text('Zusagen'), findsOneWidget);
      expect(find.text('Hoffnung'), findsOneWidget);
      expect(find.text('Verheißung'), findsNothing);
      expect(api.actions, isEmpty);
      expect(api.requests, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'person icon keeps profile and security without duplicate settings or API management',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final api = _SettingsApi();
      addTearDown(api.dispose);
      await tester.pumpWidget(AkribosApp(api: api, enableLinks: false));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Konto'));
      await tester.pumpAndSettle();
      expect(find.byType(AccountScreen), findsOneWidget);
      expect(find.text('Profil'), findsOneWidget);
      expect(find.text('Passwort ändern'), findsOneWidget);
      expect(find.text('Abmelden'), findsOneWidget);
      for (final label in [
        'Darstellung',
        'Leseschrift',
        'Standardbibel',
        'Markierungsfarben',
        'API-Schlüssel',
        'Neuer API-Schlüssel',
        'Verborgener API-Schlüssel',
      ]) {
        expect(find.text(label), findsNothing);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'an unavailable account settings response leaves local controls usable',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final api = _SettingsApi()..accountOffline = true;
      addTearDown(api.dispose);
      await tester.pumpWidget(AkribosApp(api: api, enableLinks: false));
      await tester.pumpAndSettle();
      await settings(tester);
      expect(
        find.textContaining('Test: Konto nicht erreichbar'),
        findsOneWidget,
      );
      final flow = find.widgetWithText(ListTile, 'Fließtext');
      await tester.ensureVisible(flow);
      await tester.tap(flow);
      await tester.pumpAndSettle();
      expect(tester.widget<ListTile>(flow).selected, isTrue);
      expect((await api.localStore.read())?['versePerLine'], isFalse);
      expect(api.accountActions, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
