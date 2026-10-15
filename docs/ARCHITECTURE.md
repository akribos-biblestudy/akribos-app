# Architektur

`lib/main.dart` stellt Navigation, responsive Shell und App-Links bereit;
`lib/theme/akribos_theme.dart` übernimmt PWA-Farben, Typografie und E-Ink-Darstellung.
`AppScope` liegt oberhalb des Navigators, damit auch Dialoge denselben authentifizierten
Client und dieselben Darstellungseinstellungen verwenden. Ein Navigationsschutz wartet
auf ausstehende Reader-/Dokumentspeicherung. Die Nutzeroberfläche enthält keine WebView.

Lesen, Suche, Dokumente und weitere Funktionen werden erst bei Bedarf erzeugt und als
getrennte Bereiche im `IndexedStack` gehalten. Ein bloßer Hauptbereichswechsel baut den
Reader nicht neu und lädt seine Daten nicht erneut. Explizite Reader-Navigation
invalidiert ihn hingegen auch bei identischer URL, weil die Kontoidentität
nicht in geteilten URLs steht. Versteckte Redirects werden für den nächsten Besuch
vorgemerkt, ohne die aktuelle Ansicht zu übernehmen. Guards gehören zum jeweiligen Bereich.

Anmeldung/Abmeldung invalidieren private Bereiche unmittelbar über
`AppScope.authenticationChanged()`, auch wenn der folgende Bootstrap fehlschlägt. Ein vor
dem Authwechsel gestarteter Bootstrap darf den alten Kontostand nicht wiederherstellen.
Die aktive Authform bleibt bis zu ihrem Redirect bestehen. Ein tatsächlicher Kontowechsel
beim Resume bereinigt ebenfalls alle alten Bereiche. Schriftgrößenänderungen invalidieren
gezielt den Reader nach einem erfolgreichen Flush; normale Bereichswechsel tun dies nicht.

| Pfad | Verantwortung |
| --- | --- |
| `lib/core` | Origin-gebundener HTTP-Client, Cookie-Speicher, Protokollumschläge und App-Kontext |
| `lib/features/reader` | Workspace-Modelle, flache Ressourcen-Tabs, Kapitelstreams, Verse, Markierungen und Notiz-Sidecar |
| `lib/features/search` | Suche, Strong, Statistik, Morphologie |
| `lib/features/documents` | Notizbibliothek, Ausarbeitungen, Markdown-Editor mit Lesemodus, Entwürfe, Anhänge und Export |
| `lib/features/collections` | Sammlungen, Mitglieder, Kommentare |
| `lib/features/account` | Anmeldung, Konto, Markierungsstile |
| `lib/features/help` | Lokaler Hilfeplatzhalter, Über Akribos und Lizenzen |
| `lib/widgets` | Gemeinsame Formulare, Lade-/Fehlerzustände und sicherer HTML-Renderer |

## Sitzung und Transport

Alle HTTP-Anfragen gehen an den beim Build festgelegten Origin. Redirects werden explizit
ausgewertet; ein Schreib-POST wird nicht automatisch erneut gesendet. Der Cookie-Interceptor
ordnet `Set-Cookie` nur dem ausstellenden Server zu, nicht dessen Redirect-Ziel. Cookie-
Domain, Pfad, Secure und Ablauf werden beachtet. Sitzungscookies liegen verschlüsselt über
`flutter_secure_storage` im Android-Keystore bzw. iOS-Keychain.

Vor dem Schreiben der Reader-Einstellungscookies lädt `initializeReader` die vorhandene
Host-Cookieablage ausdrücklich über `loadForRequest(origin)`. Die verwendete Cookie-Bibliothek
liest diese Ablage bei `saveFromResponse` nicht automatisch; ohne vorheriges Laden würde ein
Kaltstart die gespeicherte Session durch die beiden Einstellungen ersetzen. Schlüssel,
Namespace und Verschlüsselung bleiben bei Updates unverändert. Tests erzeugen neue
Client-/CookieJar-Instanzen über derselben Ablage und prüfen auch erneute Neustarts.

Anmeldefelder melden ihre Autofill-Rolle ausdrücklich an das Betriebssystem. Im Passwortschritt
bleibt die E-Mail-Adresse als Login-Identifier in derselben Autofill-Gruppe vorhanden.
Erst ein serverseitig bestätigter Erfolg schließt den Kontext zum Speichern ab; ein
fehlgeschlagener oder abgebrochener Versuch speichert keine Zugangsdaten. Der Passwortmanager
bleibt für Auswahl, Freigabe und Ablage zuständig; die App speichert selbst keine Passwörter.

Bilder aus eigenen Inhalten nutzen denselben Client. Der HTML-Renderer darf keine eigenen
Netzwerk-, Datei-, Daten- oder Asset-Provider verwenden. Externe Bilder werden nicht automatisch
geladen. Externe Links benötigen eine bewusste Bestätigung und öffnen den Systembrowser.

Die Anwendung besitzt keine API-Geheimnisse. Der Protokollheader ist keine Berechtigung.
Ressourcenzugriff wird serverseitig für jede Anfrage geprüft. Es gibt keine dauerhafte Kopie
privater Bibeltexte. Gerätesicherungen schließen App-Daten aus; die iOS-Keychain bleibt von
Apple-Plattformregeln abhängig.

## Reader-Zustand

Die App besitzt ihre Tabs selbst. `ReaderLocalStore` speichert den vollständigen Readerpfad
mit URL-Snapshot und `layoutSizes` im verschlüsselten Plattform-Speicher, getrennt nach
Server-Origin und Konto-ID; Gäste verwenden einen eigenen Bereich. Start und Neustart laden
diesen lokalen Stand. Ohne Stand beginnt die App mit der ersten verfügbaren Bibel bei Johannes 1.
Browser-Arbeitsbereiche werden nicht importiert. Abmelden macht den bisherigen Kontostand nicht
für andere Konten oder Gäste sichtbar; er bleibt für eine erneute Anmeldung desselben Kontos erhalten.

Die App sendet `x-akribos-app: 1` und `x-akribos-reader-mode: local`. Der Server leitet daraus im
App-Adapter `locals.localReader` ab. Bootstrap und Seitenauflösung lesen keine benannten
Arbeitsbereiche und schreiben keine Workspace-/Positionscookies. Der lokale Modus erteilt keine
Zugriffsrechte: Sitzung, Rolle, persönliche Ressourcenfreigaben und Dokumentrevisionen gelten weiter.
Strukturaktionen liefern einen bereinigten Reader-Snapshot mit `saved:false, reason:detached`,
ohne ihn auf dem Server zu speichern. Das gilt auch ohne Client-Detached-Flag und bei mitgesendeten
Workspaceversionen. Benannte Workspace-Seiten/-Aktionen sind für diesen Modus gesperrt, ebenso
die Workspace-REST-Endpunkte. Web und ältere App-Clients ohne Opt-in behalten ihr bisheriges Verhalten.

Tabauswahl, Lesepositionen, Suchen und Notizfilter werden lokal gespeichert. Die App verwendet
weder Workspace-View noch Follow und bietet keine Verwaltung benannter Arbeitsbereiche.
Ein normaler Stellenlink navigiert innerhalb des lokalen Readerstands. Ein Gerätestand verändert
weder Browser-Tabs noch ein anderes App-Gerät. Speichern und Navigation bleiben koordiniert,
damit ein ausstehender lokaler Stand oder Dokumententwurf nicht still verloren geht.

`ReaderController` verbindet Shell und Reader mit Tabanzahl, Ansichtenübersicht, aktuellem Werk
und Flush. Beim Öffnen übernimmt „Suche“ Ressourcen-ID und Werktitel. Nach einem Werkwechsel
wird ein vorhandener Suchbegriff für das neue Werk erneut ausgeführt; Buchfilter und Ergebnisseite
werden zurückgesetzt. Das gleiche Werk behält seinen geladenen Suchstand. Während des Lesens
läuft keine Hintergrundsuche. Das Werk wird im Reader gewählt; die Suchmaske hat keinen eigenen
Werkwechsler. Die lokale Tab-Suche bleibt im Tabmenü, ohne Suchbutton neben dem Stellenfeld.

Auf jeder Fensterbreite stellt eine einzige `PageView` alle geöffneten Ressourcen als flache
Tabfolge dar. Die interne Kachel-/Tabstruktur dient weiterhin dem Reader-URL-Vertrag; leere Kacheln
erscheinen nicht als leere Seiten oder Tabkarten. Ein Breitenwechsel ordnet die lokalen Tabs nicht
um. Es gibt keine Split-, Layout- oder Trennerbedienung. Jeder Ressourcentab behält Kapitelcache,
Suchkontext und Lesestelle; A–E koppelt aktive und inaktive Tabs derselben Gruppe innerhalb dieses
lokalen Stands. Verse werden in Sliver-Listen um den Viewport aufgebaut, Referenzanker ermöglichen
den exakten Sprung.

Wortklicks öffnen das Lexikon vorübergehend als fast bildschirmhohen Dialog von unten.
Die bestehende Strong-API bekommt Quellressource, Stelle, Wort und Wortposition; der
Dialog legt keinen Tab an und verändert weder lokale Tabs noch Bibelposition.
Wischen nach unten, Zurück oder Schließen kehren zum weiterhin geladenen Reader zurück.
Bewusst geöffnete Lexikonressourcen bleiben normale Tabs. Tabgruppen zeigen den Buchstaben
zusammen mit derselben A–E-Farbpalette wie das Web-Portal; E-Ink verwendet deutliche Konturen.

## Dokumente

Der Floating-Navigationseintrag „Notizen“ öffnet immer `/notes?kind=note`, auch wenn zuvor
eine Ausarbeitung geöffnet war. Ein interner Wechsel führt zu `/sermons`. Auch neue Notizen
kehren zur reinen Notizbibliothek zurück. Die App bietet weder Import noch Vorlagenverwaltung
oder Vorlagenwahl; alte direkte Import-/Vorlagenpfade führen zur jeweiligen Übersicht.
Boardspalten werden nur angezeigt, Dokumente lassen sich weiterhin zwischen ihnen verschieben.

Die Notizübersichten rendern keine vollständige Tagwolke. Tagfilter werden bei Bedarf
geöffnet, Tagdetails am Dokument bleiben eingeklappt und bearbeitbar. Die Zahl vorhandener
Tags darf den eigentlichen Notizinhalt nicht aus dem sichtbaren Bereich verdrängen.

`MarkdownSourceEditor` bearbeitet die kanonische Markdown-Quelle unmittelbar in einem
nativen Flutter-Textfeld. Es gibt keine Delta-Projektion und keine Rückkonvertierung beim
Speichern. Alle Formatierungen bleiben als Markdown bzw. unterstütztes Inline-HTML
bearbeitbar; Lesen zeigt die formatierte Darstellung. Auswahl und Moduswechsel ändern
keinen Inhalt. Der vorhandene `DocumentDraft` bleibt die Quelle für Revisionen und Saves.

Der Modusschalter steht links, das Dokumentmenü rechts. An der Textauswahl stehen
Formatierungsaktionen; weitere Einfügungen und Details liegen im Dokumentmenü. Es gibt
weder Plus-Button noch dauerhafte Formatleiste. Getippte Markdown-Präfixe bleiben im
Quelltext sichtbar; die Lesedarstellung interpretiert sie. Der Editor bleibt beim Lesen
gemountet, aber ohne Fokus und Semantik, damit Flutter seinen Undo-Verlauf erhält.
Bearbeiten und Lesen behalten eigene Scrollpositionen. Titel und Metadaten sind beim
Lesen nicht veränderbar. Der Lesemodus ändert die Bildschirm-Standby-Einstellung nicht.

`MarkdownDocumentReader` verwendet `HtmlContent` mit dokumentbezogenen Abständen,
Listeneinzügen, Zitatlinie und Tabellenrändern. Die HTML-Listen setzen ihre Marker an der
Baseline der ersten Textzeile; Folgezeilen und verschachtelte Listen behalten ihren
nativen Einzug. Der für Dokumente eingeschaltete Marker-Builder verwendet skalierbaren
Text, da der private TextPainter des Paketstandards die Systemschriftgröße ignoriert.
Die Positionierung übernimmt weiterhin das native HTML-Listenlayout. Kein Aufteilen an Leerzeilen: Lose Listen aus dem Web-Editor, Zitate in
Listeneinträgen und echte Codeblöcke werden als vollständiges Dokument interpretiert.
Es gibt keine WebView. Bilder verwenden weiterhin ausschließlich den authentifizierten,
originbeschränkten HTML-Bildpfad; externe Medien werden nicht automatisch geladen.

Für einen mit dem Serverstand identischen Quelltext wird dessen `bodyHtml` verwendet.
Ein aktueller lokaler Entwurf wird dagegen unmittelbar mit dem vorhandenen Dart-Markdown-
Parser gerendert, auch offline und ohne Schreibanfrage. Die lokale Vorschau ist kein
zweites Speicherformat. Spezielle automatische Bibelverweise und seltene Syntaxgrenzfälle
können vom Server abweichen; gespeicherte Quellen werden deshalb nie aus Vorschau-HTML
zurückgewonnen. Tabellen, Fußnoten und Inline-HTML bleiben direkt bearbeitbar.
Fußnoten öffnen ein natives Leseblatt; Schließen kehrt zur unveränderten Leseposition
zurück. Andere Dokumentanker bleiben lokale Scrollziele. Ein eng begrenzter Override der
`FootnoteDefSyntax` legt Rücklinks in einem Absatz an, weil markdown 7.3.1 bei einer
Liste am Ende einer Fußnote sonst eine Typausnahme wirft.

Auswahlgrundlage: [Flutter TextField](https://api.flutter.dev/flutter/material/TextField-class.html),
[Dart Markdown](https://pub.dev/packages/markdown) und
[nativer HTML-Renderer](https://pub.dev/packages/flutter_widget_from_html_core).
FlutterQuill samt eigenem Roundtrip-Adapter ist entfernt. Die einfachere Quelltexteingabe
ist eine bewusste Produktentscheidung nach wiederholten Fehlern bei Listen und Zitaten.

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
Android-App-Links sind im Manifest mit `autoVerify` ausschließlich für `akribos.de` (HTTP und
HTTPS, alle Pfade) konfiguriert. Die Zuordnung zum tatsächlichen Android-Signierzertifikat liegt
serverseitig unter `/.well-known/assetlinks.json`. HTTP-Links desselben Hosts auf dem Standardport
werden intern zum HTTPS-Origin aufgewertet; fremde Hosts oder Ports werden nicht übernommen.
Veröffentlichung und Geräteverifikation sind getrennte Schritte; ihr tatsächlicher Stand steht in [VALIDATION.md](VALIDATION.md).
Vorerst wird nur Android veröffentlicht. Die Apple-Organisationsanmeldung ist noch offen;
iOS-Team-ID, Signierung und vollständige Domainzuordnung folgen nach deren Bestätigung;
das Entitlement `applinks:akribos.de` ist bereits vorbereitet.

`HelpScreen` zeigt einen lokalen Platzhalter ohne Laden der Webhilfe. Eine eigenständige
App-Hilfe nach Fertigstellung sowie die iOS-Freigabe stehen in [TODO.md](TODO.md).
