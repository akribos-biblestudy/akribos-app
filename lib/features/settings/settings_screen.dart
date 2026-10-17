import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/app_scope.dart';
import '../../widgets/action_form.dart';
import '../../widgets/remote_page.dart';
import '../../widgets/app_update_details.dart';
import '../reader/verse_text.dart';
import '../../widgets/common.dart';
import '../reader/reader_controller.dart';
import '../reader/reader_companion.dart';

/// Device-local appearance settings, also available without a signed-in account.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.readerController,
    this.onHighlightStylesChanged,
  });
  final ReaderController readerController;
  final Future<void> Function()? onHighlightStylesChanged;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _saving = false;

  Future<void> _setVersePerLine(bool value) async {
    setState(() => _saving = true);
    try {
      if (!await widget.readerController.setVersePerLine(value) && mounted) {
        showError(
          context,
          'Die Textdarstellung konnte nicht gespeichert werden.',
        );
      }
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _setCompanion(ReaderCompanion value) async {
    setState(() => _saving = true);
    try {
      if (!await widget.readerController.setCompanion(value) && mounted) {
        showError(
          context,
          'Die Kommentarspalte konnte nicht gespeichert werden.',
        );
      }
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return ListenableBuilder(
      listenable: widget.readerController,
      builder: (context, _) {
        final reader = widget.readerController;
        final enabled = !_saving && reader.canSetTextPresentation;
        return PageBody(
          maxWidth: 700,
          children: [
            Text(
              'Einstellungen',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 20),
            SectionCard(
              title: 'Textdarstellung',
              children: [
                for (final option in const [
                  (
                    true,
                    'Versweise',
                    'Jeder Vers beginnt in einer neuen Zeile.',
                  ),
                  (
                    false,
                    'Fließtext',
                    'Zusammenhängende Absätze im Blocksatz.',
                  ),
                ])
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(option.$2),
                    subtitle: Text(option.$3),
                    selected: reader.versePerLine == option.$1,
                    trailing: Icon(
                      reader.versePerLine == option.$1
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                    ),
                    enabled: enabled,
                    onTap: enabled ? () => _setVersePerLine(option.$1) : null,
                  ),
              ],
            ),
            SectionCard(
              title: 'Kommentarspalte',
              children: [
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Kommentar neben der Bibel'),
                  subtitle: const Text(
                    'Zwei Spalten auf breiten Bildschirmen. Bei wenig Platz bleibt die Bibel allein sichtbar.',
                  ),
                  value: reader.companion.enabled,
                  onChanged: !_saving && reader.canSetCompanion
                      ? (value) => _setCompanion(
                          reader.companion.copyWith(enabled: value),
                        )
                      : null,
                ),
                if (reader.companion.enabled) ...[
                  DropdownButtonFormField<String>(
                    key: ValueKey(reader.companion.resourceId),
                    initialValue: reader.companion.resourceId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Kommentar'),
                    items: [
                      const DropdownMenuItem(
                        value: '',
                        child: Text('Automatisch'),
                      ),
                      if (reader.companion.resourceId.isNotEmpty &&
                          !reader.commentaries.any(
                            (resource) =>
                                resource.id == reader.companion.resourceId,
                          ))
                        DropdownMenuItem(
                          value: reader.companion.resourceId,
                          child: const Text('Momentan nicht verfügbar'),
                        ),
                      for (final resource in reader.commentaries)
                        DropdownMenuItem(
                          value: resource.id,
                          child: Text(
                            resource.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: !_saving && reader.canSetCompanion
                        ? (value) => _setCompanion(
                            reader.companion.copyWith(resourceId: value),
                          )
                        : null,
                  ),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Kommentar links anzeigen'),
                    subtitle: const Text('Die Bibel steht dann rechts.'),
                    value: reader.companion.onLeft,
                    onChanged: !_saving && reader.canSetCompanion
                        ? (value) => _setCompanion(
                            reader.companion.copyWith(onLeft: value),
                          )
                        : null,
                  ),
                ],
              ],
            ),
            SectionCard(
              title: 'Darstellung',
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final option in const [
                      (ThemeMode.system, 'System'),
                      (ThemeMode.light, 'Hell'),
                      (ThemeMode.dark, 'Dunkel'),
                    ])
                      ChoiceChip(
                        label: Text(option.$2),
                        selected: scope.themeMode == option.$1,
                        onSelected: (_) => scope.setTheme(option.$1),
                      ),
                  ],
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('E-Ink-Modus'),
                  subtitle: const Text(
                    'Hoher Kontrast und direktes Blättern, z. B. für Boox-Tablets.',
                  ),
                  value: scope.eInk,
                  onChanged: scope.setEInk,
                ),
              ],
            ),
            if (asMap(scope.api.bootstrap['user']).isNotEmpty)
              RemotePage(
                path: '/account',
                embedded: true,
                builder: _accountSettings,
              )
            else
              SectionCard(
                title: 'Persönliche Einstellungen',
                children: [
                  const Text(
                    'Melde dich an, um Leseschrift, Standardbibel und Markierungsfarben einzustellen.',
                  ),
                  const SizedBox(height: 12),
                  FilledButton.tonalIcon(
                    onPressed: () =>
                        scope.open('/login?redirectTo=%2Fsettings'),
                    icon: const Icon(Icons.login),
                    label: const Text('Anmelden'),
                  ),
                ],
              ),
            const AppUpdateDetails(),
          ],
        );
      },
    );
  }

  Widget _accountSettings(
    BuildContext context,
    Json data,
    Future<void> Function() reload,
  ) {
    Future<void> refreshAccount() async {
      await AppScope.of(context).refreshSession();
      await reload();
    }

    Future<void> refreshStyles() async {
      await widget.onHighlightStylesChanged?.call();
      await reload();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
                for (int size = 70; size <= 200; size += 5) '$size': '$size %',
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
        SectionCard(
          title: 'Markierungsfarben',
          children: [
            for (final style in asMaps(data['highlightStyles']))
              ExpansionTile(
                key: ValueKey(style['id']),
                title: Text(asString(style['name'], 'Markierungen')),
                leading: _HighlightColorSwatch(
                  id: asString(style['id']),
                  colorValue: asString(style['color']),
                ),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: VerseText(
                      key: ValueKey('highlight-preview:${style['id']}'),
                      segments: const [
                        'So sieht diese Markierung im Text aus.',
                      ],
                      highlights: [
                        {'start': 0, 'end': 7, 'color': style['color']},
                      ],
                      fontSize: 17,
                      selectable: false,
                    ),
                  ),
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
                    reload: refreshStyles,
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
          reload: refreshStyles,
        ),
      ],
    );
  }
}

class _HighlightColorSwatch extends StatelessWidget {
  const _HighlightColorSwatch({required this.id, required this.colorValue});
  final String id, colorValue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = verseColor(colorValue);
    final fill = color ?? theme.colorScheme.surfaceContainerHighest;
    final visible = Color.alphaBlend(fill, theme.colorScheme.surface);
    final border =
        ThemeData.estimateBrightnessForColor(visible) == Brightness.light
        ? Colors.black
        : Colors.white;
    return Tooltip(
      message: color == null ? 'Farbe nicht verfügbar' : 'Farbe $colorValue',
      child: SizedBox(
        width: 36,
        height: 36,
        child: DecoratedBox(
          key: ValueKey('highlight-swatch:$id'),
          decoration: BoxDecoration(
            color: fill,
            border: Border.all(color: border, width: 1.5),
            borderRadius: BorderRadius.circular(8),
          ),
          child: color == null
              ? Icon(Icons.format_color_fill_outlined, size: 20, color: border)
              : null,
        ),
      ),
    );
  }
}
