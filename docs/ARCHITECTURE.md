# Architektur

`lib/main.dart` stellt Navigation, responsive Shell und App-Links bereit;
`lib/theme/akribos_theme.dart` übernimmt PWA-Farben, Typografie und E-Ink-Darstellung.
`AppScope` liegt oberhalb des Navigators, damit auch Dialoge denselben authentifizierten
Client und dieselben Darstellungseinstellungen verwenden. Ein Navigationsschutz wartet
auf ausstehende Reader-/Dokumentspeicherung. Die Nutzeroberfläche enthält keine WebView.

Lesen, Suche, Dokumente und weitere Funktionen werden erst bei Bedarf erzeugt und als
getrennte Bereiche im `IndexedStack` gehalten. Ein bloßer Hauptbereichswechsel baut den
Reader nicht neu und lädt seine Daten nicht erneut. Explizite Reader-/Workspace-Navigation
invalidiert ihn hingegen auch bei identischer URL, weil Konto-ID und Auswahlversionen
nicht in geteilten URLs stehen. Versteckte Redirects werden für den nächsten Besuch
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

Ein zufälliger `x-reader-browser-tab` trennt die laufende App-Instanz von anderen Clients.
Gespeicherte Arbeitsbereiche gehören zum Konto, die aktuelle Arbeitskopie zur Sitzung und
App-Instanz. Schreibanfragen führen `workspaceId`, `workspaceVersion` und
`workspaceContentVersion` mit; die Serverantwort wird auf diese drei Clientfelder abgebildet.
Anfragen werden serialisiert. Eine fremde Ansicht überschreibt keinen benannten Stand allein
beim Lesen. Ein direkter Arbeitsbereichslink zeigt zuerst eine schreibfreie Öffnungsansicht.

`ReaderController` verbindet Shell und Reader mit Tabanzahl, Ansichtenübersicht und Flush.
Jeder Ressourcentab behält seine Widgets, seinen Kapitelcache, Suchkontext und seine Stelle.
Tabauswahl wird lokal sofort angezeigt und dann serialisiert mit Serverversionen bestätigt;
Fehler bleiben sichtbar und können keinen unbestätigten Wechsel still als gespeichert melden.
Bestätigte reine Tabwechsel benötigen keinen vollständigen Reader-GET. Verse werden in
Sliver-Listen nur um den Viewport aufgebaut; Referenzanker erhalten den exakten Sprung.

Reine Lesepositionen verwenden die bestehende View-API mit `resume:true`. Filteränderungen
werden bei Bedarf anschließend mit der zurückgelieferten Version regulär gespeichert.
Beide Schritte verwenden denselben eingefrorenen Snapshot. Änderungen während laufender
Anfragen bleiben für den folgenden Speicherdurchgang ausstehend; Suchfilter dürfen durch
den Positionsabgleich nicht verloren gehen. Die Kopplung A–E gilt
für aktive und inaktive Tabs derselben Gruppe. Die mobile Darstellung verändert die gespeicherte
Anordnung nicht. Nach Rückkehr in den Vordergrund wird die Sitzung aktualisiert; Reader-Follow
verwendet die bestehenden Versionsprüfungen.

Wortklicks öffnen das Lexikon vorübergehend als fast bildschirmhohen Dialog von unten.
Die bestehende Strong-API bekommt Quellressource, Stelle, Wort und Wortposition; der
Dialog legt keinen Tab an und verändert weder Arbeitsbereich noch Bibelposition.
Wischen nach unten, Zurück oder Schließen kehren zum weiterhin geladenen Reader zurück.
Bewusst geöffnete Lexikonressourcen bleiben normale Tabs. Tabgruppen zeigen den Buchstaben
zusammen mit derselben A–E-Farbpalette wie das Web-Portal; E-Ink verwendet deutliche Konturen.

## Dokumente

Die Notizübersichten rendern keine vollständige Tagwolke. Tagfilter werden bei Bedarf
geöffnet, Tagdetails am Dokument bleiben eingeklappt und bearbeitbar. Die Zahl vorhandener
Tags darf den eigentlichen Notizinhalt nicht aus dem sichtbaren Bereich verdrängen.

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
