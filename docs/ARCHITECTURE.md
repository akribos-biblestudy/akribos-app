# Architektur

`lib/main.dart` stellt Navigation, responsive Shell, Theme, E-Ink und App-Links bereit.
`AppScope` liegt oberhalb des Navigators, damit auch Dialoge denselben authentifizierten
Client und dieselben Darstellungseinstellungen verwenden. Ein Navigationsschutz wartet
auf ausstehende Reader-/Dokumentspeicherung. Die Nutzeroberfläche enthält keine WebView.

| Pfad | Verantwortung |
| --- | --- |
| `lib/core` | Origin-gebundener HTTP-Client, Cookie-Speicher, Protokollumschläge und App-Kontext |
| `lib/features/reader` | Workspace-Modelle, Layouts, Kapitelstreams, Verse, Markierungen und Notiz-Sidecar |
| `lib/features/search` | Suche, Strong, Statistik, Morphologie |
| `lib/features/documents` | Bibliothek, Ausarbeitungen, Markdown-Editor, Entwürfe, Import |
| `lib/features/collections` | Sammlungen, Mitglieder, Kommentare |
| `lib/features/account` | Anmeldung, Konto, Markierungsstile |
| `lib/features/help` | Native Hilfe, Abbildungen, rechtliche Betreiberlinks |
| `lib/widgets` | Gemeinsame Formulare, Lade-/Fehlerzustände und sicherer HTML-Renderer |

## Sitzung und Transport

Alle HTTP-Anfragen gehen an den beim Build festgelegten Origin. Redirects werden explizit
ausgewertet; ein Schreib-POST wird nicht automatisch erneut gesendet. Der Cookie-Interceptor
ordnet `Set-Cookie` nur dem ausstellenden Server zu, nicht dessen Redirect-Ziel. Cookie-
Domain, Pfad, Secure und Ablauf werden beachtet. Sitzungscookies liegen verschlüsselt über
`flutter_secure_storage` im Android-Keystore bzw. iOS-Keychain.

Bilder aus eigenen Inhalten nutzen denselben Client. Der HTML-Renderer darf keine eigenen
Netzwerk-, Datei-, Daten- oder Asset-Provider verwenden. Externe Bilder werden nicht automatisch
geladen. Externe Links benötigen eine bewusste Bestätigung und öffnen den Systembrowser.

Die Anwendung besitzt keine API-Geheimnisse. Der Protokollheader ist keine Berechtigung.
Ressourcenzugriff wird serverseitig für jede Anfrage geprüft. Es gibt keine dauerhafte Kopie
privater Bibeltexte. Gerätesicherungen schließen App-Daten aus; die iOS-Keychain bleibt von
Apple-Plattformregeln abhängig.

## Reader-Zustand

Ein zufälliger `x-reader-browser-tab` trennt die laufende App-Instanz von anderen Clients.
Gespeicherte Arbeitsbereiche gehören zum Konto, die aktuelle Arbeitskopie zur Sitzung und
App-Instanz. Schreibanfragen führen `workspaceId`, `workspaceVersion` und
`workspaceContentVersion` mit; die Serverantwort wird auf diese drei Clientfelder abgebildet.
Anfragen werden serialisiert. Eine fremde Ansicht überschreibt keinen benannten Stand allein
beim Lesen. Ein direkter Arbeitsbereichslink zeigt zuerst eine schreibfreie Öffnungsansicht.

Jeder Ressourcentab behält seinen Kapitelcache und seine Stelle. Die Kopplung A–E gilt
für aktive und inaktive Tabs derselben Gruppe. Die mobile Darstellung verändert die gespeicherte
Anordnung nicht. Nach Rückkehr in den Vordergrund wird die Sitzung aktualisiert; Reader-Follow
verwendet die bestehenden Versionsprüfungen.

## Dokumente

Autosave arbeitet mit der aktuellen positiven Dokumentrevision. Ein Bearbeitungsstand wird
zusätzlich unter einem Schlüssel aus Server, Konto und Dokument sicher gespeichert. Der
Speicherprozess merkt Änderungen während einer laufenden Übertragung und sendet anschließend
den neuen Stand. Bei Revisionkonflikt bleibt der eigene Entwurf erhalten und kann mit dem
Serverstand verglichen werden. Navigation wartet oder bietet Speichern/Verwerfen/Abbrechen.
Abmeldung macht Entwürfe eines anderen Kontos nicht sichtbar.

## Plattformen

Nur `android/` und `ios/` sind Buildziele. App-ID: `de.akribos.app`. Android benötigt Internet,
aber keine pauschalen Kamera-/Speicherrechte. Auswahl und Export laufen über Systemdialoge.
iOS verwendet Keychain-Entitlements und Privacy-Manifeste für lokale Einstellungen.
Eigenes URL-Schema: `akribos://open?path=<URL-kodierter lokaler Pfad>`.
Verifizierte HTTPS-App-Links benötigen zusätzlich die spätere Domain-/Signierzuordnung.
