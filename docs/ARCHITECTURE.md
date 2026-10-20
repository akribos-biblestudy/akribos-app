# Architektur

`lib/main.dart` stellt Navigation, responsive Shell und App-Links bereit;
`lib/theme/akribos_theme.dart` übernimmt PWA-Farben, Typografie und E-Ink-Darstellung.
`AppScope` liegt oberhalb des Navigators, damit auch Dialoge denselben authentifizierten
Client und dieselben Darstellungseinstellungen verwenden. Ein Navigationsschutz wartet
auf ausstehende Reader-/Dokumentspeicherung. Nur der Notizeditor verwendet die
isolierte HTTPS-WebView mit der bestehenden Akribos-Webkomponente.

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

Öffentliche Betreiberseiten (einschließlich `/datenschutz#konto-loeschen`) werden
auf Android über `lib/core/operator_browser.dart` und den nativen Kanal
`de.akribos.app/browser` ausdrücklich an einen Browser übergeben. Eine generische
URL-/Custom-Tab-Öffnung würde durch die verifizierten App-Links wieder Akribos
starten. Der Browser erhält die vollständige URL mit Fragment, aber keine native
Sitzung oder zusätzlichen Header. iOS verwendet weiterhin den System-Browserdialog.
Beide Einstiegspunkte zeigen bei einem Fehler die manuell aufrufbare Adresse.

Alle Anfragen des Akribos-Clients gehen an den beim Build festgelegten Origin. Redirects werden explizit
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

## Installierte Version und Store-Updates

`AppUpdateController` wird einmal für die App erzeugt. `PlatformAppUpdateGateway` liest
Version und Build aus dem tatsächlich installierten Paket/Bundle über den MethodChannel
`de.akribos.app/updates`. Einstellungen und Über Akribos zeigen dieselben Angaben.
GitHub-Tags und `pubspec.yaml` dienen nicht als Laufzeitquelle oder Update-Katalog.

Android verwendet Googles `AppUpdateManager.appUpdateInfo` und dessen Verfügbarkeit für
die installierte App und das Play-Konto, einschließlich zugänglicher Testtracks. Nur
`UPDATE_AVAILABLE` mit höherem Versionscode erzeugt ein Angebot. Fehlender Play-Zugriff
ist „nicht verfügbar“, ein Übertragungsfehler niemals „aktuell“. Direkte APKs werden anhand
des Installers ausgeschlossen. Der feste Play-Link öffnet ausdrücklich die Play-App,
mit dem bestehenden öffentlichen Browser als Rückfall.

iOS ermittelt den tatsächlichen `Storefront.current` getrennt von den sofort verfügbaren
Bundle-Metadaten. Die ISO-3-Kennung wird in Apples ISO-2-Lookup-Parameter übersetzt, niemals
aus der Gerätesprache geraten. Ein eigener Dio-Client fragt ausschließlich
`https://itunes.apple.com/lookup` für Bundle-ID und Store-Land ab, ohne Akribos-Cookies,
Protokollheader oder Kontodaten. Nur ein eindeutiger Softwaretreffer mit passender Bundle-ID,
positiver Store-ID, höherer numerischer Version und passender Mindest-iOS-Version erzeugt
einen Hinweis. Die Zieladresse wird aus validierter ID und Land unter `apps.apple.com`
aufgebaut; eine gelieferte URL wird nicht übernommen. Ohne öffentliche Listung gibt es keine
Updateaussage. Entwicklungs-/Simulatorbuilds und erkannte Sandbox-Receipts sind ausgeschlossen;
ein fehlendes Receipt allein beweist keine Entwicklungsinstallation. TestFlight-Verfügbarkeit
wird nicht geprüft, und es ist keine erfundene Apple-App-ID hinterlegt.

Beim Start und Resume prüft der Controller automatisch: erfolgreiche Ergebnisse höchstens
alle zwölf Stunden, Fehler oder fehlende Store-Unterstützung nach frühestens 15 Minuten.
Gleichzeitige Anfragen werden zusammengefasst; Zeitlimits werden beim Dispose abgebrochen.
Manuelles „Nach Updates suchen“ umgeht die Wartezeit. Ein nichtmodaler Hinweis lässt sich
für die angebotene Version 24 Stunden gerätelokal schließen. Neue Versionen erscheinen wieder.
Prüfungsfehler bleiben in der Versionskarte nachvollziehbar, ohne die Lektüre zu unterbrechen.

„Im Store öffnen“ wartet auf aktive Dokument-/Navigationsguards und die Speicherung des
beibehaltenen Readers. Fehler verhindern den Wechsel; zwischenzeitliche Navigation oder ein
Kontowechsel verwerfen einen verspäteten Öffnungsversuch. Es gibt keine erzwungene Installation,
keine Push-Berechtigung und keine automatische Veröffentlichung durch diese Funktion.

## Reader-Zustand

Die App besitzt ihre Tabs selbst. `ReaderLocalStore` speichert den vollständigen Readerpfad
mit URL-Snapshot, `layoutSizes`, `versePerLine` und den `companion`-Darstellungsoptionen im verschlüsselten Plattform-Speicher, getrennt nach
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
um. Es gibt keinen Layouteditor oder verschiebbaren Trenner. Jeder Ressourcentab behält Kapitelcache,
Suchkontext und Lesestelle; A–E koppelt aktive und inaktive Tabs derselben Gruppe innerhalb dieses
lokalen Stands. Die Tabübersicht endet immer mit einer leeren Plus-Karte zum Öffnen der
Werkauswahl. Erst die Auswahl eines Werkes legt einen Tab an.

Beim horizontalen Wischen übernimmt der Reader die Tabauswahl nach Ende der
`PageView`-Bewegung. Damit laufen Gruppenabgleich und lokale Speicherung nicht am
halben Seitenübergang. Unterbricht eine Navigation die Geste, sichert ihr Guard auch
die gerade sichtbare Auswahl. Erfolgreiches Speichern ohne Fehleränderung erzeugt
keinen zusätzlichen Reader-Neuaufbau.

Kapitel behalten bei reinen Auswahl-/Speicheränderungen ihren Sliver-Baum; `VerseText`
behält unveränderte Textspans, Gestenerkennung und das geformte Fußnoten-Overlay.
Kapitelersatz, Schriftgröße, Darstellungsmodus und relevante geerbte Stile invalidieren
die Präsentation. Ein Kapitelreload ersetzt seine Segmentlisten; der lokale Cache
vergleicht ihre Identität und Darstellungsmetadaten, ohne Texte erneut zu serialisieren
oder zu zerlegen. Gespeicherte Aktionen rufen weiterhin die aktuellen Handler auf.
Positionsmessung betrachtet nur die am Viewport aufgebauten Einträge und verwendet
für Fließtext die tatsächliche Glyphenposition. Regressionen prüfen diese Darstellung
ausdrücklich neben versweisen Listen; Gerätebildraten erfordern einen Release-Build
auf dem betreffenden Gerät.

`ReaderRichText` verwendet weiterhin Flutters `RenderParagraph` für Layout, Zeichnung
und sämtliche semantischen Wortknoten. Deren Hierarchie wird rekursiv in Gruppen
mit höchstens 32 Kindern aufgeteilt. Lange Fließtextabsätze können sonst tausende
Geschwister erzeugen, deren räumliche Sortierung bei aktivierten Bedienungshilfen
quadratische Arbeit auslöst. Ordinale Sortierschlüssel allein verhindern diese vorher
ausgeführte Sortierung nicht. Unbenannte Strukturknoten behalten die nativen Labels,
Aktionen, IDs, Sichtbarkeitsmerkmale und Rechtecke der Wortknoten bei. Alle Rechtecke
bleiben im Koordinatensystem des Absatzes; die vorhandenen Aktionen zum Sichtbarmachen
eines Wortes dürfen keine zusätzliche Verschiebung erhalten.

Ein nativer Semantikaufbau erzeugt neue Sortierschlüssel und markiert dadurch auch
unveränderte Wortknoten als geändert. Nach dem initialen Aufbau werden daher für reine
Viewport-Verschiebungen die nativen Knoten, ihre Gruppenzuordnung und ihre Konfiguration
wiederverwendet. Nur Wörter mit geändertem Sichtbarkeitsstatus werden aktualisiert.
Ein Sammelknoten übernimmt die nativen Kinder, ohne sie zunächst aus ihren Gruppen
zu entfernen; solche Zwischenzustände würden alle Wörter erneut an Android übertragen.
Layout, semantische Metadaten oder geänderte Recognizer-Callbacks invalidieren diesen
Cache. Nicht unterstützte Inline-Inhalte verwenden weiterhin den nativen Aufbau.
Beim Abschalten der
Semantik werden nur eigene Referenzen verworfen, weil deren Owner bereits zerstört
sein kann. Regressionen vergleichen die native Darstellung mit aktivierter Semantik,
einschließlich Schrift-/Breitenwechsel, RTL, schnellen Gesten und erneuter Aktivierung.
Die Semantik läuft nach dem Compositing: niedrige `FrameTiming`-Build-/Rasterwerte allein
schließen deshalb lange Blockaden der Eingabeverarbeitung nicht aus.

Langes Drücken und Ziehen verschiebt die Tabkarten, einschließlich automatischem Scrollen am
oberen/unteren Rand; die Plus-Karte ist auch ein Ablageziel für das Ende der Folge. Screenreader
erhalten entsprechende Verschiebeaktionen. Beim Verschieben wird eine importierte Mehrkachel-
Adresse zu einer einzelnen lokalen Kachel normalisiert. Alle Tabinhalte, IDs, Gruppen, Suchen,
Wortstudien und die aktive Auswahl bleiben erhalten. Die neue Reihenfolge steht im gespeicherten
Reader-URL-Snapshot und damit auch in bewusst geteilten Ansichten.

„Einstellungen → Notizenspalte“ ergänzt auf Wunsch eine zweite Spalte neben der aktuell
sichtbaren Bibel. Sichtbarkeit und „Notizen links anzeigen“ werden lokal pro Server/Konto
gespeichert; standardmäßig steht die Bibel links. Die Spalte erscheint nur ab 760 logischen
Pixeln und genügend Platz für die Systemschrift. Schmale Fenster, OS-Split-Screen und große
Schrift behalten die Präferenz, zeigen aber nur den normalen Reader. Die Zusatzspalte ist
kein Tab und verändert die Tabgruppen nicht. Alte Kommentar-Ressourcenpräferenzen werden
ignoriert; ausdrücklich geöffnete Kommentar-Tabs bleiben vollständig erhalten.

Die native Notizliste lädt ausschließlich eigene Notiz-Zusammenfassungen über
`/api/documents?kind=note&passage=Joh3` und zeigt standardmäßig das sichtbare Kapitel über
alle Übersetzungen hinweg. Der Kapitelbezug lässt sich ausschalten; Suche und Tagfilter
bleiben verfügbar. Erst ein Kapitelwechsel löst eine neue Anfrage aus, nie jeder gescrollte
Vers. Während einer neuen Anfrage und bei Fehlern bleibt die alte Kapitel-Liste verborgen;
verspätete Antworten dürfen die aktuelle Auswahl nicht ersetzen. Eine sichtbare
Wiederholen-Aktion lädt die angefragte Stelle erneut. Gäste erhalten einen Anmeldehinweis.

Öffnen und Anlegen einer Notiz sichern zuerst die Reader-Position und verwenden anschließend
den vorhandenen WebView-Editor mit seinen Speicher- und Navigationsguards. Neue Notizen
werden an den sichtbaren Vers gebunden. Beim Zurückkehren wird die Liste neu geladen.
Scrollen in der Notizliste verändert keine Bibelstelle. Nach einer Breitenänderung wird
die gespeicherte Bibelstelle anhand des neu umbrochenen Textes ausgerichtet; alte
Pixelpositionen gelten nur bei gleicher Spaltenbreite. Die Messung wartet den Layout-Frame
eines vorherigen Sofort-Scrolls ab.

„Mehr → Einstellungen“ bündelt Darstellung/E-Ink und die Textdarstellung auch für Gäste.
Angemeldete Nutzer laden darunter Leseschrift, Standardbibel und Markierungsfarben über den
bestehenden `/account`-Vertrag. `RemotePage.embedded` begrenzt Lade-/Fehlerzustände auf diesen
kontogebundenen Bereich, damit lokale Einstellungen weiter bedienbar bleiben. Schriftänderungen
aktualisieren den Reader über den Bootstrap-Vergleich; neue/umbenannte Markierungsfarben laden
seinen Datenstand nach, jeweils erst nach Sicherung der lokalen Lesestelle. Das Personen-Icon
öffnet weiterhin Profil, Passwort und Abmelden. Unter Mehr gibt es keinen Konto-Eintrag mehr,
API-Schlüsselverwaltung ist kein Bestandteil der mobilen Kontooberfläche.

Unter „Mehr → Einstellungen“ bietet „Textdarstellung“ die Optionen „Versweise“ und „Fließtext“
(Standard bei Neuinstallation und fehlender gespeicherter Wahl). Eine ausdrücklich gespeicherte
Auswahl bleibt bei Updates erhalten. Diese gerätelokale Seite ist auch für Gäste
erreichbar; die Tabübersicht enthält keine Darstellungsumschaltung. Fließtext steht im Blocksatz,
Versweise bleibt am Zeilenanfang ausgerichtet. Der angehängte `ReaderController` sichert beim
Wechsel zuerst die Lesestelle und ändert den erhaltenen Reader auch außerhalb der sichtbaren
Leseansicht. Beim Zurückkehren wird derselbe Vers im neuen Absatzlayout ausgerichtet. Verse
beziehungsweise durch Quellüberschriften getrennte Absätze werden in Sliver-Listen um den Viewport
aufgebaut. Quellzeilenumbrüche bleiben erhalten. Fließtext ist
ein echter RichText-Absatz; Versnummern, Fußnoten, Wortaktionen und Langdruck bleiben an den
jeweiligen Vers gebunden. Die tatsächlichen Glyphenpositionen dienen der Ausrichtung und
Lesestellenerfassung innerhalb des Absatzes, auch nach einem Darstellungswechsel.

`VerseMarkerPainter` zeichnet gespeicherte Markierungen hinter den Glyphen. Die Auswahlboxen
des tatsächlichen `RenderParagraph` verbinden Leerzeichen und gemischte Wortstile zu einer
leicht unregelmäßigen Farbfläche pro Zeile, ohne neue Wortindizes oder Strong-Positionen zu
erfinden. Teilmarkierungen behalten ihre gespeicherten Grenzen. E-Ink verwendet stattdessen
schwarze Unterstreichungen und benannte Markierungen. Abschnitts- und Kapitelüberschriften
verwenden das 1,2- beziehungsweise 1,4-Fache der gewählten Leseschriftgröße.
Kommentar- und Lexikontexte sowie die Fundstellen verwenden ebenfalls die persönliche
Leseskalierung; UI-Labels bleiben unabhängig davon. Versnummer und erstes Wort verbindet
ein geschütztes Leerzeichen, ohne die gespeicherten Wortpositionen zu verändern.
E-Ink-Unterstreichungen sind deckend, pixelgenau und ohne Kantenglättung gezeichnet,
damit dünne Linien beim Schwellenwert-Rendering nicht verschwinden.

`ReaderVerseMenu` zeigt vier feste Aktionen: Markieren, Sammlungen, Notiz und Teilen.
Symbole stehen neben einzeiligen Beschriftungen. Die tatsächlichen Textbreiten einschließlich
Systemskalierung bestimmen die Spaltenzahl; auf Telefonen entsteht typischerweise ein
2×2-Raster, bei großer Schrift eine Liste, bei ausreichender Breite eine Zeile.
Die Buttons bleiben gleich breit und mindestens 48 Pixel hoch. Der separate Kopierbutton
entfällt; Kopieren steht im nativen Teilen-Dialog bereit. Teilen behält Vers, Referenz, URL
und den bestehenden `sharePositionOrigin` für das iPad. iOS verwendet über `share_plus`
die normale `UIActivityViewController`-Aktion
[`copyToPasteboard`](https://developer.apple.com/documentation/uikit/uiactivity/activitytype-swift.struct/copytopasteboard)
für den geteilten Text; diese Aktivität wird nicht ausgeschlossen. Das wurde anhand der
Apple-Dokumentation und des installierten Plugin-Codes geprüft, nicht auf einem iOS-Gerät.
Neue Markierungen betreffen ausschließlich den ganzen Vers.
Der Einstieg und Handler zum Erstellen von Wort-/Teilmarkierungen sind entfernt.
Vorhandene Teilmarkierungen werden weiterhin mit ihren gespeicherten Grenzen dargestellt
und lassen sich gezielt löschen; es gibt keine Datenmigration oder automatische Löschung.
Normale Strong-Wortaktionen bleiben erhalten. Beliebig viele Farben, vorhandene
Markierungen und Sammlungen stehen auf eigenen Auswahlseiten; System-Zurück führt zunächst
zum Hauptmenü. Dieses passt auf den geprüften Telefon-/Tabletgrößen in Hoch- und Querformat
ohne Scrollen. Sehr große Systemschrift erhält stattdessen eine Scrollmöglichkeit, damit
Beschriftungen und Touchflächen nicht schrumpfen oder abgeschnitten werden. Aktionscodes,
Gastgrenzen und quellgebundene Teilmarkierungs-Löschungen bleiben unverändert.

Wortklicks öffnen das Lexikon vorübergehend als fast bildschirmhohen Dialog von unten.
Die bestehende Strong-API bekommt Quellressource, Stelle, Wort und Wortposition; der
Dialog legt keinen Tab an und verändert weder lokale Tabs noch Bibelposition.
Wischen nach unten, Zurück oder Schließen kehren zum weiterhin geladenen Reader zurück.
Bewusst geöffnete Lexikonressourcen bleiben normale Tabs. Tabgruppen zeigen den Buchstaben
zusammen mit derselben A–E-Farbpalette wie das Web-Portal; E-Ink verwendet deutliche Konturen.

## Dokumente

Der Floating-Navigationseintrag „Notizen“ öffnet `/notes?kind=note`, auch wenn zuvor
eine Ausarbeitung geöffnet war. Nach dem Flush liefert der Reader seine aktuelle Stelle;
standardmäßig ergänzt die Shell `passage` mit deren ganzem Kapitel. Der vorhandene
Serverfilter erfasst sowohl Stellenanker als auch Verweise im Text, übersetzungsübergreifend
und vor der Paginierung. „Aktuelles Kapitel“ in der Bibliothek schaltet dies ab oder wieder an;
die boolesche Präferenz bleibt lokal pro Server/Konto erhalten. Neue Notizen übernehmen den
aktiven Stellenfilter als editierbare Vorgabe. Ein interner Wechsel führt zu `/sermons`. Auch neue Notizen
kehren zur reinen Notizbibliothek zurück. Die App bietet weder Import noch Vorlagenverwaltung
oder Vorlagenwahl; alte direkte Import-/Vorlagenpfade führen zur jeweiligen Übersicht.
Boardspalten werden nur angezeigt, Dokumente lassen sich weiterhin zwischen ihnen verschieben.

Die Notizübersichten rendern keine vollständige Tagwolke. Tagfilter werden bei Bedarf
geöffnet, Tagdetails am Dokument bleiben eingeklappt und bearbeitbar. Die Zahl vorhandener
Tags darf den eigentlichen Notizinhalt nicht aus dem sichtbaren Bereich verdrängen.

### Gemeinsamer aktiver Webeditor

`WebEditor` lädt ausschließlich `/app/editor/[id]` auf dem konfigurierten HTTPS-Origin.
`EditorWebSession` überträgt die vorhandene Session über einen nativen MethodChannel
an CookieManager/WKHTTPCookieStore: hostgebunden, HttpOnly, Secure und Pfad `/`.
Abmelden/Kontowechsel löscht den Webkontext. Gleiche bereits bestätigte Sitzungen
werden nur prozesslokal erkannt, damit normale Notizwechsel nicht alle Assets neu laden.
Kein Sessionwert gelangt in JavaScript, URLs oder Logs.

Die Webkomponente besitzt die einzige Text-Speicherqueue. `WebEditorController` wartet
auf versionierte Antworten für Flush, Lesen/Bearbeiten und reservierte Metadatenaktionen.
Aktueller Text und bestätigter Serverstand bleiben getrennt. Snapshots sichern den
bestehenden verschlüsselten Entwurf samt Ursprungsrevision; Konflikte überschreiben
keinen neueren Stand. Navigation benötigt eine Speicherbestätigung oder eine ausdrückliche
Entwurfsentscheidung. Der Editor bleibt beim Moduswechsel samt Undo-History erhalten.

Rootlayout und Clientinitialisierung der Embedroute greifen nicht auf Reader-/Browser-
Arbeitsbereiche zu. Native Navigation und Meta-/Dateidialoge bleiben im Flutter-Host.
Die Seite benötigt Netzwerk beim Öffnen; lokale Entwurfssicherung ist keine Zusage
für einen vollständig offline verfügbaren Webeditor.

### Erhaltene native Widgets aus dem vorherigen Editor

Die folgenden Widgets bleiben separat testbar, sind aber nicht mehr die aktive
Bearbeitungs- oder Lesefläche einer geöffneten Notiz:

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
