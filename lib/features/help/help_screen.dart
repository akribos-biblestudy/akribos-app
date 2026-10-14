import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_scope.dart';
import '../../core/json.dart';
import '../../widgets/common.dart';
import '../../widgets/remote_page.dart';

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key, required this.path});
  final String path;
  @override
  Widget build(BuildContext context) => RemotePage(
    path: path,
    builder: (context, data, reload) {
      final article = asMap(data['article']);
      return PageBody(
        maxWidth: 850,
        children: [
          Text(
            article.isEmpty
                ? 'Hilfe & Anleitungen'
                : asString(article['title']),
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 16),
          if (article.isEmpty)
            TextField(
              decoration: const InputDecoration(
                labelText: 'Hilfe durchsuchen',
                prefixIcon: Icon(Icons.search),
              ),
              onSubmitted: (query) =>
                  AppScope.of(context)
                      .open('/help?q=${Uri.encodeQueryComponent(query)}'),
            ),
          if (article.isNotEmpty) Text(asString(article['description'])),
          const SizedBox(height: 16),
          for (final result in asMaps(data['results']))
            Card(
              child: ListTile(
                title: Text(asString(result['title'])),
                subtitle: Text(asString(result['description'])),
                trailing: const Icon(Icons.chevron_right),
                onTap: () =>
                    AppScope.of(context).open(asString(result['path'])),
              ),
            ),
          for (final section in asMaps(article['sections']))
            SectionCard(
              title: asString(section['title']),
              children: [
                HtmlContent(html: asString(section['html'])),
                if (section['screenshot'] != null)
                  _HelpScreenshot(data: asMap(section['screenshot'])),
              ],
            ),
          for (final guide in asMaps(data['guides']))
            ListTile(
              title: Text(asString(guide['title'])),
              subtitle: Text(asString(guide['description'])),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => AppScope.of(context).open(asString(guide['path'])),
            ),
          if (article.isEmpty)
            for (final topic in asMaps(data['topics']))
              Card(
                child: ListTile(
                  leading: const Icon(Icons.menu_book),
                  title: Text(asString(topic['title'])),
                  subtitle: Text(asString(topic['description'])),
                  onTap: () =>
                      AppScope.of(context).open(asString(topic['path'])),
                ),
              ),
        ],
      );
    },
  );
}

class InformationScreen extends StatelessWidget {
  const InformationScreen({super.key, required this.path});
  final String path;
  @override
  Widget build(BuildContext context) => PageBody(
    maxWidth: 700,
    children: [
      Text(
        path == '/datenschutz'
            ? 'Datenschutz'
            : path == '/impressum'
            ? 'Impressum'
            : path.startsWith('/api')
            ? 'API-Dokumentation'
            : 'Über Akribos',
        style: Theme.of(context).textTheme.headlineMedium,
      ),
      const SizedBox(height: 20),
      const Text(
        'Akribos verbindet Bibeltext, Wortstudien, Notizen und gemeinsame Stellensammlungen. Deine Inhalte werden auf deinem Akribos-Server gespeichert.',
      ),
      const SizedBox(height: 16),
      const Text(
        'Die App speichert deine Sitzung und noch nicht übertragene Dokumententwürfe im sicheren Gerätespeicher. Sie lädt kein Analyseskript. Exportdateien liegen vorübergehend im privaten App-Verzeichnis, damit du sie speichern oder teilen kannst.',
      ),
      const SizedBox(height: 16),
      FilledButton.tonalIcon(
        onPressed: () => launchUrl(
          AppScope.of(context).api.origin.resolve(path),
          mode: LaunchMode.externalApplication,
        ),
        icon: const Icon(Icons.open_in_new),
        label: const Text('Aktuelle Angaben des Betreibers öffnen'),
      ),
      const SizedBox(height: 16),
      OutlinedButton(
        onPressed: () => showLicensePage(
          context: context,
          applicationName: 'Akribos',
          applicationVersion: '0.1.0',
        ),
        child: const Text('Open-Source-Lizenzen'),
      ),
    ],
  );
}

class _HelpScreenshot extends StatelessWidget {
  const _HelpScreenshot({required this.data});
  final Json data;
  String get html =>
      '<img src="${const HtmlEscape().convert(asString(data['src']))}" alt="${const HtmlEscape().convert(asString(data['alt']))}">';
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          button: true,
          label: 'Abbildung vergrößern',
          child: InkWell(
            onTap: () => showDialog<void>(
              context: context,
              builder: (context) => Dialog.fullscreen(
                child: Scaffold(
                  appBar: AppBar(
                    title: Text(asString(data['alt'], 'Abbildung')),
                    leading: IconButton(
                      tooltip: 'Schließen',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ),
                  body: Center(
                    child: InteractiveViewer(
                      minScale: 1,
                      maxScale: 5,
                      child: HtmlContent(html: html),
                    ),
                  ),
                ),
              ),
            ),
            child: HtmlContent(html: html),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          asString(data['caption']),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    ),
  );
}
