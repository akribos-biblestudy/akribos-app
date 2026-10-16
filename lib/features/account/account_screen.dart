import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api_client.dart';
import '../../core/app_scope.dart';
import '../../widgets/action_form.dart';
import '../../widgets/common.dart';
import '../../widgets/remote_page.dart';
import '../reader/books.dart';
import '../reader/verse_text.dart';

Json highlightReference(Json verse) => {
  'book': asInt(verse['book']),
  'chapter': asInt(verse['chapter']),
  'verse': asInt(verse['verse']),
  if (asInt(verse['endVerse']) > asInt(verse['verse']))
    'verseEnd': asInt(verse['endVerse']),
};

class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key, required this.path});
  final String path;
  @override
  Widget build(BuildContext context) => RemotePage(
    path: path,
    builder: (context, data, reload) {
      if (path.startsWith('/account/highlights/')) {
        return PageBody(
          children: [
            Text(
              asString(data['title'], 'Markierungen'),
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            for (final verse in asMaps(data['verses']))
              Card(
                child: ListTile(
                  title: Text(referenceLabel(highlightReference(verse))),
                  subtitle: verse['segments'] is List
                      ? VerseText(segments: verse['segments'] as List)
                      : const Text(
                          'Der Bibeltext ist derzeit nicht verfügbar.',
                        ),
                  onTap: () => AppScope.of(context)
                      .open('/${referenceLabel(highlightReference(verse))}'),
                ),
              ),
          ],
        );
      }
      final user = asMap(data['user']);
      Future<void> refreshAccount() async {
        await AppScope.of(context).refreshSession();
        await reload();
      }

      return PageBody(
        maxWidth: 850,
        children: [
          Text('Dein Konto', style: Theme.of(context).textTheme.headlineMedium),
          Text(asString(user['email'])),
          const SizedBox(height: 24),
          ActionForm(
            title: 'Profil',
            path: '/account',
            action: 'profile',
            fields: [
              FormFieldSpec(
                'displayName',
                'Anzeigename',
                value: user['displayName'],
              ),
            ],
            reload: refreshAccount,
          ),
          ActionForm(
            title: data['hasPassword'] == true
                ? 'Passwort ändern'
                : 'Passwort einrichten',
            path: '/account',
            action: 'password',
            shouldSaveAutofill: (result) => result.isSuccess,
            fields: [
              FormFieldSpec(
                'email',
                'E-Mail-Adresse',
                value: user['email'],
                kind: FieldKind.email,
                readOnly: true,
                autofillHints: const [
                  AutofillHints.username,
                  AutofillHints.email,
                ],
              ),
              if (data['hasPassword'] == true)
                const FormFieldSpec(
                  'currentPassword',
                  'Aktuelles Passwort',
                  kind: FieldKind.password,
                  autofillHints: [AutofillHints.password],
                  required: true,
                ),
              FormFieldSpec(
                'password',
                'Neues Passwort',
                kind: FieldKind.password,
                autofillHints: const [AutofillHints.newPassword],
                required: true,
                hint:
                    'Mindestens ${asInt(data['minPasswordLength'], 12)} Zeichen',
              ),
              const FormFieldSpec(
                'passwordRepeat',
                'Neues Passwort wiederholen',
                kind: FieldKind.password,
                autofillHints: [AutofillHints.newPassword],
                required: true,
              ),
            ],
            onResult: (result) async {
              if (result.isSuccess) {
                await AppScope.of(context).refreshSession();
                await reload();
              }
            },
          ),
          SectionCard(
            title: 'Konto und Daten löschen',
            children: [
              const Text(
                'Auf der Betreiberseite kannst du die Löschung deines Kontos und der zugehörigen Daten anfordern.',
              ),
              const SizedBox(height: 16),
              ActionButton(
                label: 'Löschung anfordern',
                icon: Icons.open_in_new,
                onPressed: () async {
                  final uri = AppScope.of(context).api.origin
                      .resolve('/datenschutz#konto-loeschen');
                  try {
                    if (await launchUrl(
                      uri,
                      mode: LaunchMode.inAppBrowserView,
                    )) {
                      return;
                    }
                  } catch (_) {
                    // ActionButton displays the same useful fallback for both
                    // a rejected launch and a platform exception.
                  }
                  throw ApiException(
                    'Die Seite zum Löschantrag konnte nicht geöffnet werden. Öffne $uri in deinem Browser.',
                  );
                },
              ),
            ],
          ),
          OutlinedButton.icon(
            onPressed: () => AppScope.of(context).open('/logout'),
            icon: const Icon(Icons.logout),
            label: const Text('Abmelden'),
          ),
        ],
      );
    },
  );
}
