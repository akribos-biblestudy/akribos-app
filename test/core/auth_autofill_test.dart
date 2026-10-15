import 'package:akribos_app/core/api_client.dart';
import 'package:akribos_app/core/app_scope.dart';
import 'package:akribos_app/features/account/account_screen.dart';
import 'package:akribos_app/features/account/auth_screen.dart';
import 'package:akribos_app/widgets/action_form.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _AuthApi extends AppApi {
  _AuthApi({this.data = const {}})
    : super(server: 'https://example.test', cookies: CookieJar());
  final Json data;
  ApiResult response = const ApiResult(type: 'failure', status: 400);
  final submissions = <Json>[];

  @override
  Future<Json> page(String path) async => data;

  @override
  Future<ApiResult> action(String path, String action, Json fields) async {
    submissions.add({...fields});
    if (action == 'start') {
      return ApiResult(
        type: 'success',
        status: 200,
        data: {'step': 'password', 'email': fields['email']},
      );
    }
    return response;
  }
}

Widget _app(_AuthApi api, Widget child, {List<String>? opened}) => AppScope(
  api: api,
  open: (path) async => opened?.add(path),
  refreshSession: () async {},
  setNavigationGuard: (_, _) {},
  setTheme: (_) {},
  themeMode: ThemeMode.light,
  child: MaterialApp(home: Scaffold(body: child)),
);

Finder _field(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);

List<Object?> _finishes(WidgetTester tester) => tester.testTextInput.log
    .where((call) => call.method == 'TextInput.finishAutofillContext')
    .map((call) => call.arguments)
    .toList();

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _passwordStep(WidgetTester tester, _AuthApi api) async {
  await tester.pumpWidget(_app(api, const AuthScreen(path: '/login')));
  await tester.pumpAndSettle();
  expect(tester.widget<TextField>(_field('E-Mail-Adresse')).autofillHints, [
    AutofillHints.username,
    AutofillHints.email,
  ]);
  await tester.enterText(_field('E-Mail-Adresse'), 'reader@example.test');
  await _tap(tester, find.text('Weiter'));
  expect(_finishes(tester), isNot(contains(true)));
}

void main() {
  testWidgets(
    'password step exposes and accepts username plus password together',
    (tester) async {
      final api = _AuthApi();
      await _passwordStep(tester, api);
      await tester.showKeyboard(_field('Passwort'));
      await tester.pump();
      final fields = asMaps(tester.testTextInput.setClientArgs!['fields']);
      expect(fields, hasLength(2));
      final username = fields.singleWhere(
        (field) => (asMap(field['autofill'])['hints'] as List).contains(
          AutofillHints.username,
        ),
      );
      final password = fields.singleWhere(
        (field) => (asMap(field['autofill'])['hints'] as List).contains(
          AutofillHints.password,
        ),
      );
      expect(
        asMap(asMap(username['autofill'])['editingValue'])['text'],
        'reader@example.test',
      );
      // Model the platform returning both values, including a different saved account.
      tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        SystemChannels.textInput.name,
        SystemChannels.textInput.codec.encodeMethodCall(
          MethodCall('TextInputClient.updateEditingStateWithTag', [
            0,
            {
              asString(
                asMap(username['autofill'])['uniqueIdentifier'],
              ): const TextEditingValue(text: 'other@example.test')
                  .toJSON(),
              asString(
                asMap(password['autofill'])['uniqueIdentifier'],
              ): const TextEditingValue(text: 'synthetic-test-password')
                  .toJSON(),
            },
          ]),
        ),
        (_) {},
      );
      await tester.pump();
      expect(
        tester.widget<TextField>(_field('E-Mail-Adresse')).controller!.text,
        'other@example.test',
      );
      expect(tester.widget<TextField>(_field('Passwort')).obscureText, isTrue);
      await _tap(tester, find.text('Anmelden'));
      expect(api.submissions.last['email'], 'other@example.test');
      expect(_finishes(tester), isNot(contains(true)));

      api.response = const ApiResult(
        type: 'redirect',
        status: 303,
        location: '/Joh1',
      );
      await _tap(tester, find.text('Anmelden'));
      expect(_finishes(tester).where((value) => value == true), hasLength(1));
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      expect(_finishes(tester).where((value) => value == true), hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('abandoning a failed password login cancels instead of saving', (
    tester,
  ) async {
    final api = _AuthApi();
    await _passwordStep(tester, api);
    await tester.enterText(_field('Passwort'), 'wrong-test-password');
    await _tap(tester, find.text('Anmelden'));
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(_finishes(tester), isNot(contains(true)));
    expect(_finishes(tester).last, isFalse);
  });

  testWidgets('email codes use oneTimeCode and never save a password context', (
    tester,
  ) async {
    final api = _AuthApi(
      data: {
        'pending': {'email': 'reader@example.test'},
      },
    );
    api.response = const ApiResult(
      type: 'redirect',
      status: 303,
      location: '/Joh1',
    );
    await tester.pumpWidget(_app(api, const AuthScreen(path: '/login')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(_field('Sechsstelliger Code')).autofillHints,
      [AutofillHints.oneTimeCode],
    );
    await tester.enterText(_field('Sechsstelliger Code'), '123456');
    await _tap(tester, find.text('Anmelden'));
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(_finishes(tester), isNot(contains(true)));
  });

  testWidgets(
    'ordinary form fields explicitly opt out of credential autofill',
    (tester) async {
      final api = _AuthApi();
      await tester.pumpWidget(
        _app(
          api,
          const ActionForm(
            title: 'Profil',
            path: '/account',
            action: 'profile',
            fields: [
              FormFieldSpec('displayName', 'Anzeigename'),
              FormFieldSpec('contact', 'Kontakt', kind: FieldKind.email),
            ],
          ),
        ),
      );
      expect(find.byType(AutofillGroup), findsNothing);
      expect(
        tester.widget<TextField>(_field('Anzeigename')).autofillHints,
        isNull,
      );
      expect(tester.widget<TextField>(_field('Kontakt')).autofillHints, isNull);
    },
  );

  testWidgets(
    'password reset marks new passwords and commits only confirmed reset',
    (tester) async {
      final api = _AuthApi();
      await tester.pumpWidget(
        _app(api, const AuthScreen(path: '/password-reset/token')),
      );
      await tester.pumpAndSettle();
      for (final label in ['Neues Passwort', 'Passwort wiederholen']) {
        expect(tester.widget<TextField>(_field(label)).autofillHints, [
          AutofillHints.newPassword,
        ]);
        await tester.enterText(_field(label), 'synthetic-new-password');
      }
      await _tap(tester, find.text('Passwort speichern'));
      expect(_finishes(tester), isNot(contains(true)));
      api.response = const ApiResult(
        type: 'redirect',
        status: 303,
        location: '/account',
      );
      await _tap(tester, find.text('Passwort speichern'));
      expect(_finishes(tester).where((value) => value == true), hasLength(1));
    },
  );

  testWidgets(
    'account password form groups only its immutable account identifier and passwords',
    (tester) async {
      final api = _AuthApi(
        data: {
          'user': {'email': 'reader@example.test'},
          'hasPassword': true,
        },
      );
      await tester.pumpWidget(_app(api, const AccountScreen(path: '/account')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(_field('E-Mail-Adresse')).readOnly,
        isTrue,
      );
      await tester.showKeyboard(_field('Neues Passwort'));
      await tester.pump();
      final fields = asMaps(tester.testTextInput.setClientArgs!['fields']);
      final hints = fields.map((field) => asMap(field['autofill'])['hints']);
      expect(fields, hasLength(4));
      expect(
        hints.where(
          (value) => (value as List).contains(AutofillHints.newPassword),
        ),
        hasLength(2),
      );
      expect(
        tester.widget<TextField>(_field('Anzeigename')).autofillHints,
        isNull,
      );
      for (final label in [
        'Aktuelles Passwort',
        'Neues Passwort',
        'Neues Passwort wiederholen',
      ]) {
        await tester.enterText(_field(label), 'synthetic-account-password');
      }
      final form = find.byWidgetPredicate(
        (widget) => widget is ActionForm && widget.action == 'password',
      );
      final save = find.descendant(of: form, matching: find.text('Speichern'));
      api.response = const ApiResult(
        type: 'redirect',
        status: 303,
        location: '/login',
      );
      await _tap(tester, save);
      expect(_finishes(tester), isNot(contains(true)));
      api.response = const ApiResult(
        type: 'success',
        status: 200,
        data: {'passwordSaved': true},
      );
      await _tap(tester, save);
      expect(_finishes(tester).where((value) => value == true), hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );
}
