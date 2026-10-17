import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/operator_browser.dart';
import '../../widgets/common.dart';
import '../../widgets/app_update_details.dart';

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key, required this.path});
  final String path;
  @override
  Widget build(BuildContext context) => PageBody(
    maxWidth: 700,
    children: [
      Text(
        'Hilfe & Anleitungen',
        style: Theme.of(context).textTheme.headlineMedium,
      ),
      const SizedBox(height: 24),
      const Icon(Icons.menu_book_outlined, size: 56),
      const SizedBox(height: 20),
      Text(
        'Die App-Hilfe entsteht noch',
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: 12),
      const Text(
        'Hier findest du künftig Anleitungen für die Akribos-App auf deinem Smartphone und Tablet.',
      ),
      const SizedBox(height: 12),
      const Text(
        'Sobald die App fertig ist, ergänzen wir Schritt-für-Schritt-Anleitungen zu ihren Funktionen.',
      ),
    ],
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
        Uri.parse(path).path == '/datenschutz'
            ? 'Datenschutz'
            : Uri.parse(path).path == '/impressum'
            ? 'Impressum'
            : path.startsWith('/api')
            ? 'API-Dokumentation'
            : 'Über Akribos',
        style: Theme.of(context).textTheme.headlineMedium,
      ),
      const SizedBox(height: 20),
      if (Uri.parse(path).path == '/about') const AppUpdateDetails(),
      const Text(
        'Akribos verbindet Bibeltext, Wortstudien, Notizen und gemeinsame Stellensammlungen. Deine Inhalte werden auf deinem Akribos-Server gespeichert.',
      ),
      const SizedBox(height: 16),
      const Text(
        'Die App speichert deine Sitzung und noch nicht übertragene Dokumententwürfe im sicheren Gerätespeicher. Sie lädt kein Analyseskript. Exportdateien liegen vorübergehend im privaten App-Verzeichnis, damit du sie speichern oder teilen kannst.',
      ),
      const SizedBox(height: 16),
      ActionButton(
        onPressed: () =>
            openOperatorPage(AppScope.of(context).api.origin.resolve(path)),
        icon: Icons.open_in_new,
        label: 'Aktuelle Angaben des Betreibers öffnen',
      ),
      const SizedBox(height: 16),
      OutlinedButton(
        onPressed: () =>
            showLicensePage(context: context, applicationName: 'Akribos'),
        child: const Text('Open-Source-Lizenzen'),
      ),
    ],
  );
}
