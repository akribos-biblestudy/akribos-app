import 'package:flutter/material.dart';

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
          SectionCard(
            title: 'Darstellung',
            children: [
              SegmentedButton<ThemeMode>(
                segments: const [
                  ButtonSegment(value: ThemeMode.system, label: Text('System')),
                  ButtonSegment(value: ThemeMode.light, label: Text('Hell')),
                  ButtonSegment(value: ThemeMode.dark, label: Text('Dunkel')),
                ],
                selected: {AppScope.of(context).themeMode},
                onSelectionChanged: (values) {
                  AppScope.of(context).setTheme(values.first);
                },
              ),
            ],
          ),
          ActionForm(
            title: 'Leseschrift',
            path: '/account',
            action: 'reader',
            fields: [
              FormFieldSpec(
                'fontScale',
                'Schriftgröße',
                value: asString(data['readerFontScale'], '100'),
                kind: FieldKind.select,
                options: {
                  for (int size = 70; size <= 200; size += 5)
                    '$size': '$size %',
                },
              ),
            ],
            reload: refreshAccount,
          ),
          ActionForm(
            title: 'Standardbibel',
            path: '/account',
            action: 'defaultBible',
            fields: [
              FormFieldSpec(
                'defaultBibleId',
                'Bibel für Vorschauen und Zitate',
                value: data['defaultBibleId'] ?? '',
                kind: FieldKind.select,
                options: {
                  '': 'Automatisch',
                  for (final bible in asMaps(data['bibles']))
                    asString(bible['id']): asString(bible['name']),
                },
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
            title: 'Markierungsfarben',
            children: [
              for (final style in asMaps(data['highlightStyles']))
                ExpansionTile(
                  key: ValueKey(style['id']),
                  title: Text(asString(style['name'], 'Markierungen')),
                  leading: const Icon(Icons.format_color_fill),
                  children: [
                    TextButton(
                      onPressed: () =>
                          AppScope.of(context)
                              .open('/account/highlights/${style['id']}'),
                      child: const Text('Markierte Verse öffnen'),
                    ),
                    ActionForm(
                      title: 'Bezeichnung',
                      path: '/account',
                      action: 'renameHighlightStyle',
                      hidden: {'id': style['id']},
                      fields: [
                        FormFieldSpec('name', 'Name', value: style['name']),
                      ],
                      reload: reload,
                    ),
                  ],
                ),
            ],
          ),
          ActionForm(
            title: 'Markierungsfarbe hinzufügen',
            path: '/account',
            action: 'addHighlightStyle',
            fields: const [
              FormFieldSpec('name', 'Name', required: true),
              FormFieldSpec(
                'color',
                'Farbe',
                value: '#f4d35e',
                kind: FieldKind.color,
                options: {
                  '#f4d35e': 'Gold',
                  '#87c6a2': 'Grün',
                  '#8abde3': 'Blau',
                  '#d6a0c8': 'Violett',
                  '#edb58b': 'Orange',
                  '#f0a8b0': 'Rot',
                },
              ),
            ],
            reload: reload,
          ),
          SectionCard(
            title: 'API-Schlüssel',
            children: [
              for (final key in asMaps(data['apiKeys']))
                ListTile(
                  title: Text(asString(key['name'])),
                  subtitle: Text(asString(key['scope'])),
                  trailing: IconButton(
                    tooltip: 'Widerrufen',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      if (await confirmAction(
                            context,
                            'API-Schlüssel widerrufen?',
                          ) &&
                          context.mounted) {
                        await runAction(context, '/account', 'revokeApiKey', {
                          'id': key['id'],
                        }, reload: reload);
                      }
                    },
                  ),
                ),
            ],
          ),
          ActionForm(
            title: 'Neuer API-Schlüssel',
            path: '/account',
            action: 'createApiKey',
            reload: reload,
            fields: const [
              FormFieldSpec('name', 'Name', required: true),
              FormFieldSpec(
                'scope',
                'Zugriff',
                value: 'public',
                kind: FieldKind.select,
                options: {
                  'public': 'Öffentliche Inhalte',
                  'personal': 'Persönliche Inhalte',
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
