import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/app_scope.dart';
import '../../widgets/action_form.dart';
import '../../widgets/common.dart';
import '../../widgets/remote_page.dart';

class AuthScreen extends StatelessWidget {
  const AuthScreen({super.key, required this.path});
  final String path;
  @override
  Widget build(BuildContext context) {
    if (Uri.parse(path).path == '/logout') {
      return PageBody(
        maxWidth: 560,
        children: [
          ActionForm(
            title: 'Abmelden',
            path: '/logout',
            action: 'default',
            fields: const [],
            submitLabel: 'Auf diesem Gerät abmelden',
            onResult: (result) async {
              if (result.isSuccess || result.isRedirect) {
                final scope = AppScope.of(context);
                await scope.api.clearSession();
                await scope.refreshSession();
                await scope.open('/Joh1');
              }
            },
          ),
        ],
      );
    }
    return RemotePage(
      path: path,
      builder: (context, data, reload) {
        final route = Uri.parse(path).path;
        if (route == '/login' || route == '/register') {
          return _LoginForm(
            key: ValueKey(path),
            path: path,
            data: data,
            reload: reload,
          );
        }
        if (route == '/register/check-email') {
          return const PageBody(
            maxWidth: 560,
            children: [
              Text(
                'Bitte prüfe dein E-Mail-Postfach und bestätige deine Adresse.',
              ),
            ],
          );
        }
        final reset = route.startsWith('/password-reset/');
        final verify =
            route.startsWith('/login/verify/') ||
            route.startsWith('/register/verify/');
        final pending = asMap(data['pending']);
        if (verify &&
            (route.startsWith('/login/verify/')
                ? pending.isEmpty
                : data['valid'] != true)) {
          return PageBody(
            maxWidth: 560,
            children: [
              const Text(
                'Dieser Link ist ungültig, abgelaufen oder wurde bereits verwendet.',
              ),
              TextButton(
                onPressed: () => AppScope.of(context).open('/login?restart=1'),
                child: const Text('Neue Anmeldung starten'),
              ),
            ],
          );
        }
        return PageBody(
          maxWidth: 560,
          children: [
            if (verify)
              Text(
                asString(pending['email']),
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ActionForm(
              title: reset
                  ? 'Neues Passwort'
                  : verify
                  ? 'E-Mail bestätigen'
                  : 'Passwort zurücksetzen',
              path: path,
              action: 'default',
              fields: reset
                  ? const [
                      FormFieldSpec(
                        'password',
                        'Neues Passwort',
                        kind: FieldKind.password,
                        required: true,
                      ),
                      FormFieldSpec(
                        'passwordRepeat',
                        'Passwort wiederholen',
                        kind: FieldKind.password,
                        required: true,
                      ),
                    ]
                  : verify
                  ? const []
                  : const [
                      FormFieldSpec(
                        'email',
                        'E-Mail-Adresse',
                        kind: FieldKind.email,
                        required: true,
                      ),
                    ],
              submitLabel: verify
                  ? 'Bestätigen'
                  : reset
                  ? 'Passwort speichern'
                  : 'Link senden',
              onResult: (result) async {
                if (result.isRedirect) {
                  await AppScope.of(context).refreshSession();
                  if (context.mounted) {
                    await AppScope.of(context).open(result.location!);
                  }
                } else if (result.isSuccess && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Die Anfrage wurde verarbeitet. Bitte prüfe gegebenenfalls dein Postfach.',
                      ),
                    ),
                  );
                }
              },
            ),
          ],
        );
      },
    );
  }
}

class _LoginForm extends StatefulWidget {
  const _LoginForm({
    super.key,
    required this.path,
    required this.data,
    required this.reload,
  });
  final String path;
  final Json data;
  final Future<void> Function() reload;
  @override
  State<_LoginForm> createState() => _LoginFormState();
}

class _LoginFormState extends State<_LoginForm> {
  String _step = 'email', _email = '';
  bool _unverified = false;
  @override
  void initState() {
    super.initState();
    _readPending();
  }

  @override
  void didUpdateWidget(_LoginForm old) {
    super.didUpdateWidget(old);
    if (old.data != widget.data) _readPending();
  }

  void _readPending() {
    final pending = asMap(widget.data['pending']);
    if (pending.isNotEmpty) {
      _step = 'code';
      _email = asString(pending['email']);
    } else {
      _step = 'email';
    }
  }

  Future<void> _result(ApiResult result) async {
    if (!mounted) return;
    if (result.isRedirect) {
      if (result.location!.startsWith('/login')) {
        await AppScope.of(context).open(result.location!);
      } else {
        await AppScope.of(context).refreshSession();
        if (mounted) await AppScope.of(context).open(result.location!);
      }
    } else if (result.data['step'] != null) {
      setState(() {
        _step = asString(result.data['step']);
        _email = asString(result.data['email'], _email);
        _unverified = result.data['error'] == 'unverified';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final redirectTo = asString(widget.data['redirectTo'], '/');
    return AutofillGroup(
      child: PageBody(
        maxWidth: 520,
        children: [
          const SizedBox(height: 24),
          Icon(
            Icons.auto_stories_rounded,
            size: 48,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text(
            'Willkommen bei Akribos',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text(
              'Deine Bibel. Deine Gedanken. Auf allen Geräten.',
              textAlign: TextAlign.center,
            ),
          ),
          if (_step != 'email')
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(_email, textAlign: TextAlign.center),
            ),
          ActionForm(
            key: ValueKey('$_step:$_email'),
            title: switch (_step) {
              'password' => 'Mit Passwort anmelden',
              'code' => 'Code aus deiner E-Mail',
              _ => 'Anmelden oder Konto erstellen',
            },
            path: '/login',
            action: switch (_step) {
              'password' => 'login',
              'code' => 'code',
              _ => 'start',
            },
            hidden: {
              'redirectTo': redirectTo,
              if (_step != 'email') 'email': _email,
              'company': '',
            },
            fields: switch (_step) {
              'password' => const [
                FormFieldSpec(
                  'password',
                  'Passwort',
                  kind: FieldKind.password,
                  required: true,
                ),
              ],
              'code' => const [
                FormFieldSpec(
                  'code',
                  'Sechsstelliger Code',
                  kind: FieldKind.number,
                  required: true,
                ),
              ],
              _ => [
                FormFieldSpec(
                  'email',
                  'E-Mail-Adresse',
                  value: _email,
                  kind: FieldKind.email,
                  required: true,
                ),
              ],
            },
            submitLabel: _step == 'email' ? 'Weiter' : 'Anmelden',
            onResult: _result,
          ),
          if (_step == 'code')
            ActionButton(
              label: 'Neuen Code senden',
              onPressed: () async {
                final result = await AppScope.of(context).api.action(
                  '/login',
                  'start',
                  {'email': _email, 'redirectTo': redirectTo},
                );
                if (!result.isSuccess &&
                    !result.isRedirect &&
                    context.mounted) {
                  showError(context, result.message);
                }
                await _result(result);
              },
            ),
          if (_step == 'password')
            TextButton(
              onPressed: () => AppScope.of(context).open('/password-reset'),
              child: const Text('Passwort vergessen?'),
            ),
          if (_step == 'password' && _unverified)
            ActionButton(
              label: 'Aktivierungslink erneut senden',
              onPressed: () async {
                final result = await AppScope.of(context).api
                    .action('/login', 'resend', {'email': _email});
                if (context.mounted) {
                  showError(
                    context,
                    result.isSuccess
                        ? 'Bitte prüfe dein E-Mail-Postfach.'
                        : result.message,
                  );
                }
              },
            ),
          if (_step != 'email')
            TextButton(
              onPressed: () => AppScope.of(context).open(
                '/login?restart=1&redirectTo=${Uri.encodeComponent(redirectTo)}',
              ),
              child: const Text('Andere E-Mail-Adresse verwenden'),
            ),
          TextButton(
            onPressed: () => AppScope.of(context).open('/Joh1'),
            child: const Text('Ohne Anmeldung lesen'),
          ),
        ],
      ),
    );
  }
}
