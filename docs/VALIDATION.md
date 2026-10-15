# Prüfstand 15. Oktober 2026

## Notizlisten, Tippkürzel und kompakte Kopfleiste, Build 10

Version `0.2.7+10` richtet das Dokumentmenü am rechten Rand aus und entfernt den
separaten Plus-Button sowie leere reservierte Aktionsplätze. Einfügen und Details
bleiben im Dokumentmenü erreichbar. Listenmarkierungen und Einzüge verwenden die
skalierte Geometrie der Leseschrift; Punkte stehen mittig zur ersten Textzeile.

Der gemeldete Unterlistenfehler wurde mit einem synthetischen HTML-Beispiel durch
den tatsächlichen Web-Serializer `documentHtmlToMarkdown()` reproduziert. Dessen
Ausgabe enthält `-   `, Leerzeilen zwischen Einträgen und vier Leerzeichen vor
Unterpunkten. Vor der Korrektur ergab der App-Parser zwei Hauptpunkte und Codeblöcke;
nach der Korrektur erhält er beide Hauptpunkte und vier echte Unterpunkte, auch nach
Bearbeiten und erneutem Öffnen. Unveränderte Quellen bleiben bytegenau erhalten.

Tippkürzel `- `, `* `, `+ `, `1. `, `> ` sowie `# ` bis `###### ` wandeln eine noch
unformatierte Zeile nach einem einzelnen eingegebenen Leerzeichen um. Der Adapter
bedient sowohl native Bildschirmtastatureingabe als auch Hardware-Tasten. Bulk-Paste,
Laden, Wiederherstellen, Code, aktive Komposition und Lesen lösen keine Umwandlung aus.

Gezielte Prüfungen, keine vollständige lokale Testsuite:

- 27 Codec-/Markdown-Tests erfolgreich, darunter das echte Web-Ausgabeformat,
  gemischte und lose Listen, mehrstellige Nummerierung, Fortsetzungsabsätze und
  echte Codeblöcke innerhalb von Listen.
- 19 Tippkürzeltests erfolgreich: native Texteingabe, Hardware, Undo/Redo, Cursor,
  Export/Reload, Schutzfälle und Verdrahtung im tatsächlichen RichMarkdownEditor.
- 21 Dokument-/Editor-/Tagtests erfolgreich: Menü am rechten Rand bei 320 Pixeln
  und 200 % OS-Textgröße, erreichbare Einfüge-/Detailfunktionen, mehrzeilige Listen,
  100/160 % Leseschrift, OS-Skalierung, Autosave, Lesemodus und Scrollposition.
- Zehn Release-Guardtests nach Anheben des Versionscodes auf 10 erfolgreich.
- Gesamte statische Flutter-Analyse ohne Befunde.

Fünf echte DocumentEditor-Aufnahmen mit synthetischen Inhalten aktualisiert und visuell
geprüft: Smartphone Bearbeiten/Lesen jeweils hell/dunkel sowie Tablet. Punkte stehen
an der ersten Zeile, Unterpunkte sind eingerückt und Folgezeilen bündig zum Text.
Keine privaten Nutzernotizen oder Geräteaufnahmen wurden gespeichert.

ARM64-AOT-Build für `https://akribos.de` erfolgreich; bisherige Signatur, Version,
16-KiB-Alignment und fehlendes Debuggable-Flag geprüft.
APK: `artifacts/akribos-0.2.7-akribos-de-release.apk`.
SHA-256: `6b1bbcfd75b2a76ba346fbec72def140498410702e3a532bdcaf6f292a8d78d9`.
Am 15. Oktober um **13:21:41 Uhr** erfolgreich per `adb install -r` auf dem Pixel
aktualisiert und gestartet. Android bestätigt `0.2.7`, Code `10` sowie unverändert
**14. Oktober, 22:28 Uhr** als Erstinstallation. Keine Datenlöschung/Deinstallation.
Die reale Bedienung der neuen Tippkürzel wurde durch native Texteingabe im Widgettest,
noch nicht durch manuelles Tippen in einer privaten Notiz auf dem Pixel geprüft.

Der vollständige GitHub-CI-Lauf des vorigen Editorstands `8023d60` ist inzwischen
[erfolgreich abgeschlossen](https://github.com/akribos-biblestudy/akribos-app/actions/runs/38723469755),
einschließlich Tests und Android-Prüf-APK.

## Nativer Richtext-Editor und Lesemodus, Build 9

Version `0.2.6+9` ersetzt das Markdown-Textfeld durch FlutterQuill mit einem eigenen
quellenerhaltenden Markdown-Adapter. Formatierung erscheint an der Textauswahl;
Überschriften, Listen, Tabellen, Fußnoten und Bibelzitate stehen im Einfügen-Menü.
Lesen/Bearbeiten verwendet dasselbe Dokument, dieselbe History und Scrollposition.
Lesen zeigt auch einen aktuellen lokalen Entwurf, ohne Titel- oder Metadatenbearbeitung.
Details stehen in einem separaten Blatt. Normale Markdown-Trennzeilen werden nicht
als zusätzliche leere Absätze dargestellt.

Gezielte Prüfung, keine vollständige lokale Testsuite:

- 20 Codec-/Markdown-Regressionen erfolgreich: unveränderte Quellblöcke, Tabellen,
  Fußnoten, verschachtelte Formatierung, Escapes, HTML-Erweiterungen, Undo, Einfügen,
  sofortiger Export vor verzögertem Dokumentereignis und unabhängige Speichersnapshots.
- 15 gezielte Dokument-/Tagtests einschließlich Autosave während weiterer Eingabe,
  Wiederherstellung mit ursprünglicher Revision, sofortigem Flush, Offline-Lesemodus,
  320-Pixel-Layout bei großer Schrift und bedienbarem Undo/Redo erfolgreich.
- Vier Richtext-Widgettests erfolgreich: Auswahlmenü bei 320 Pixeln und großer Schrift,
  unveränderter Scrollstand/History beim Lesen, Tabellenzellenbearbeitung und Fußnoten
  ohne Navigation, Tastatur, Netzwerkzugriff oder Inhaltsänderung im Lesemodus.
- Zehn Konto-/Inhaltstests einschließlich lokaler Dokumentanker erfolgreich.
- Zehn Release-Guardtests nach Anheben der Versionscode-Untergrenze auf 9 erfolgreich.
- Statische Flutter-Analyse und Formatprüfung ohne Befunde. Echte DocumentEditor-
  Widgets mit synthetischer Ausarbeitung unter `docs/screenshots/editor-*.png`
  aufgenommen und visuell geprüft; keine privaten Kontodaten oder Geräteaufnahmen.

ARM64-AOT-Release für `https://akribos.de` erfolgreich gebaut; Version, bisheriger
Signer, 16-KiB-Alignment und fehlendes Debuggable-Flag durch das Buildskript geprüft.
APK: `artifacts/akribos-0.2.6-akribos-de-release.apk`.
SHA-256: `a4edfa4993811be877d05936ab4bd7a621594d96b6cd8c6c39e9689026b49ad9`.
Am 15. Oktober um **12:52:30 Uhr** erfolgreich mit `adb install -r` auf dem Pixel
aktualisiert und gestartet. Android bestätigt `0.2.6`, Code `9` und unveränderte
Erstinstallation **14. Oktober, 22:28 Uhr**. Keine Datenlöschung oder Deinstallation.
App Links bleiben `verified`, erlaubt und für `akribos.de` ausgewählt. Der neue
Editor wurde nicht mit privaten Nutzernotizen am echten Gerät redaktionell abgenommen.

Die App liegt auf GitHub unter `akribos-biblestudy/akribos-app`. Der erste vollständige
[Android-CI-Lauf](https://github.com/akribos-biblestudy/akribos-app/actions/runs/38720445222)
für den vorherigen Stand `1d1a7e8` ist erfolgreich einschließlich aller Flutter-Tests
und APK-Artefakt. Store-Secrets sind weiterhin nicht eingerichtet; kein Play-Upload.
Die Versionscode-Untergrenze im Environment ist auf 9 angehoben.

Tabellenzellen sind bearbeitbar; Zeilen-/Spaltenumbau ist im Dialog noch nicht enthalten.
Unbekannte Strukturen bleiben erhalten und werden nur ausdrücklich im Originalformat
bearbeitet. Es gibt keinen vergleichenden Pixel-/PWA-Performancebenchmark und noch
keine vollständige redaktionelle Abnahme auf iOS oder Boox. Der Lesemodus verhindert
kein automatisches Standby des Geräts.

## Ausarbeitungen nur über Notizen, Build 8

Version `0.2.5+8` entfernt zusätzlich den Eintrag „Ausarbeitungen“ unter „Mehr“.
Der Wechsel auf der Notizen-Seite bleibt erhalten. Zwei betroffene Navigationstests
und die zehn Release-Guardtests sind erfolgreich; keine vollständige lokale Testsuite.
Die Play-Versionscode-Untergrenze steht nun im Workflow und im GitHub-Environment auf 8.

APK: `artifacts/akribos-0.2.5-akribos-de-release.apk`.
SHA-256: `8d9c02e1172816c0c5c3c67957effcab25330ae4669f9c3ddadf89f79bf2a9a8`.
Optimierter ARM64-Build, Signatur, Alignment, Version und fehlendes Debuggable-Flag
geprüft. Am 15. Oktober um **12:27 Uhr** erfolgreich mit `adb install -r` auf dem
Pixel aktualisiert. Android bestätigt `0.2.5`, Code `8`, unveränderte Erstinstallation
**14. Oktober, 22:28 Uhr**; die Activity wurde gestartet. Kein Löschen von App-Daten.

## Lokale Tabs und vereinfachte mobile Abläufe, Build 7

Version `0.2.4+7` verwaltet die Reader-Tabs verschlüsselt auf der jeweiligen Installation,
getrennt nach Server und Konto. Sie übernimmt oder veröffentlicht keine Browser-Arbeitsbereiche.
Alle Werke erscheinen unabhängig von der ursprünglichen Spaltenzahl als flache Tabs auf
Telefon und Tablet. Die Workspace- und Spaltenverwaltung ist entfernt. Ein neuer lokaler
Stand beginnt mit einer Bibel; Browseransichten werden nicht als mobile Ausgangsauswahl kopiert.

Der Notizen-Einstieg öffnet immer Notizen, mit Wechsel zu Ausarbeitungen. Import, Vorlagen,
Spaltenbearbeitung, doppelte Informationslinks und der manuelle Linköffner sind entfernt.
Ausarbeitungen können weiterhin bestehenden Vorbereitungsschritten zugeordnet werden.
Die Suche nennt das sichtbare Werk und wiederholt beim Werkwechsel dieselbe Anfrage nur
darin. Wort-Lexikonblätter und bestehende Dokument-Speichergrenzen bleiben erhalten.
Die Hilfe zeigt vorläufig ausschließlich einen lokalen App-Platzhalter; die spätere
App-Anleitung ist in TODO.md vorgemerkt.

Gezielte Prüfungen, ohne vollständigen lokalen Testlauf:

- Backend: 70 Tests für Adapter, lokale Reader-Isolation und werkbezogene Lexikonsuche
  erfolgreich. Svelte-/TypeScript-Prüfung ohne Fehler (14 bestehende Backup-Adminwarnungen),
  gezieltes ESLint, Prettier und Diffcheck sauber.
- Reader, Lexikon und URL-Vertrag: 30 gezielte Tests erfolgreich. Darunter Neustart mit
  eigener lokaler Tabwahl, Scroll-/Suchzustand, Speicherfehler und schnelle A–B–A-Wechsel.
  Ein dabei reproduzierter Queuefehler wurde behoben und mit verzögertem Schreiben geprüft.
- Lokaler Store: vier Tests zu Konto-/Server-/Gerätetrennung, serialisierten Schreibvorgängen,
  Fehlern/Retry und beschädigten Daten erfolgreich.
- Shell und Anmeldung: 16 Tests erfolgreich; zusätzlich echte Navbar-Regression mit Suche
  nach „Liebe“, Reader-Swipe auf ein anderes Werk und erneuter Suche mit unverändertem Begriff
  und ausschließlich neuer Ressourcen-ID erfolgreich. Kein globaler Suchseitenaufruf.
- Acht werkbezogene Suchtests, neun betroffene Dokument-/Tagprüfungen und drei Linktests
  erfolgreich. Gesamte Flutter-Analyse ohne Befunde.
- Fünf synthetische Flutter-Aufnahmen mit anonymen öffentlichen Daten aktualisiert: Telefon
  hell/dunkel, Tabs, Tablet und E-Ink. Capturetest erfolgreich, visuell keine Überläufe.
  Die breiten Tabletansichten verwenden weiterhin lange Textzeilen.

Optimierter ARM64-Release erfolgreich gebaut; erwartete Version, bisheriger Signer,
16-KiB-Alignment und fehlendes Debuggable-Flag durch das Buildskript geprüft.
APK: `artifacts/akribos-0.2.4-akribos-de-release.apk`.
SHA-256: `1114753b8fae75b0af2a3c48233e82cefa35f655bc0991a371ece0767ff5a610`.

Die Android-Store-Automatisierung hat zehn gezielte Release-Guardtests und Actionlint
für alle drei Workflows bestanden. Gepinnte Python-Abhängigkeiten wurden mit Hashprüfung
installiert und importiert. Das private GitHub-Repository und das Environment
`android-play-internal` sind angelegt; dessen Deploymentregel erlaubt nach API-Rücklesung
nur Branch `main`, keine Tags. Bootstrap ist deaktiviert, die Versionscode-Untergrenze
steht auf 7. Es wurden keine Google-Zugangsdaten oder Store-Schlüssel erzeugt/hinterlegt
und kein echter Store-Upload durchgeführt; die Einrichtung steht in PLAY-STORE.md.

Backend-Commit `0622517` ergänzt den expliziten lokalen Reader-Modus, den lesenden
Lexikonsuch-Endpunkt und die Domainzuordnung für Android. Die vollständige GitHub-CI
[38718224383](https://github.com/akribos-biblestudy/akribos/actions/runs/38718224383)
ist grün einschließlich Imageveröffentlichung und Coolify-Aufruf. Live geprüft: `/healthz` 200,
Domainzuordnung 200 JSON mit tatsächlichem Pixel-Signer, Lexikonsuche mit G26 im ausgewählten
Werk und `private, no-store`, lokaler Bootstrap ohne benannte Ansichten oder Workspace-/
Lesestellen-Cookies. Auch ein altes Vier-Spalten-Cookie beeinflusst die lokale Startansicht nicht.

Am 15. Oktober um **12:22 Uhr** per `adb install -r` auf dem Pixel aktualisiert (`Success`),
Version `0.2.4+7`, unveränderter Erstinstallationszeitpunkt **14. Oktober, 22:28 Uhr**.
Kein Löschen von App-Daten oder Entsperren. App gestartet. Android bestätigt `akribos.de: verified`.
Die bisher konkurrierende Akribos-PWA blieb zunächst der bevorzugte Linkhandler; für die
gewünschte native Zuordnung wurde deren automatische Linkübernahme deaktiviert und die
native App ausgewählt. Der unveränderte echte Verifikationsstatus bleibt `verified`.
Android löst normale HTTPS-Links nun ohne erzwungenes Paket zu `de.akribos.app/.MainActivity`
auf; ein gewöhnlicher VIEW-Intent wurde an die laufende App zugestellt. Keine zusätzliche
vollständige visuelle Geräteabnahme oder Prüfung privater Sitzungsdaten.

## Sichtbare Markierungsfarben, Build 6

Version `0.2.3+6` ersetzt das farblose Symbol jeder gespeicherten Markierungsfarbe in den
Kontoeinstellungen durch eine 36-Pixel-Farbkachel aus dem tatsächlichen Farbwert. Ein
kontrastierender Rand hält auch Weiß und Schwarz erkennbar; der Name bleibt sichtbar.
Aufgeklappt zeigt der Eintrag eine Textmarkierung über denselben `VerseText`-Renderer wie
im Reader, einschließlich dessen Deckkraft. Bezeichnungen und bestehende Farben werden
nicht verändert. Kein neuer API-Endpunkt und keine Backendänderung.

Die bestehenden acht Konto-/Inhaltstests bestanden; Flutter-Analyse, Formatierung und
`git diff --check` waren sauber. Der optimierte ARM64-Release wurde erfolgreich gebaut;
Signatur, Version, 16-KiB-Alignment und fehlendes Debuggable-Flag sind geprüft. Ein
vollständiger lokaler Testlauf wurde wie gewünscht nicht ausgeführt. Synthetische
Widget-Aufnahmen der echten Kontoeinstellung wurden im hellen und dunklen Modus geprüft:
Farben, Namen und Textvorschau sind sichtbar, ohne Überläufe.

APK: `artifacts/akribos-0.2.3-akribos-de-release.apk`.
SHA-256: `1d019646004643d09ac7ee76fd0c4d391a55a6d9151d6241b39138c2b7fb99d7`.

Die APK wurde am 15. Oktober 2026 um **11:33 Uhr** mit `adb install -r` erfolgreich
auf dem wieder angeschlossenen Pixel 9 Pro aktualisiert (`Success`). Android bestätigt
`versionName=0.2.3`, `versionCode=6` und den unveränderten Erstinstallationszeitpunkt
**14. Oktober, 22:28 Uhr**. Die App wurde anschließend in den Vordergrund gebracht.
Es gab keine Deinstallation und kein Löschen von App-Daten. Die Darstellung wurde
per Widget-Aufnahmen geprüft; eine visuelle Abnahme auf dem Pixel steht noch aus.

## Sitzungserhalt und Passwortmanager, Build 5

Version `0.2.2+5` behebt einen reproduzierten Kaltstartfehler. `initializeReader` speicherte
zwei Hostcookies, bevor `PersistCookieJar` die vorhandene Hostablage geladen hatte. Dadurch
wurde ein vorhandenes Sitzungscookie überschrieben. Es war kein Deinstallationsschritt:
Das Pixel meldete vor dem Update weiterhin den ursprünglichen Installationszeitpunkt
14. Oktober 2026, 22:28 Uhr; die bisherigen Aktualisierungen erfolgten mit `adb install -r`.

Der Fix lädt dieselbe verschlüsselte Cookieablage vor dem Schreiben. Namespace, Schlüssel,
Verschlüsselung, Paket-ID und Signatur ändern sich nicht. Ein bereits durch ältere App-Starts
überschriebenes Cookie kann nicht wiederhergestellt werden; dann ist einmal eine reguläre
Anmeldung nötig. Gültige noch vorhandene Sitzungen werden weiterbenutzt. Serverseitiger
Ablauf, Widerruf und explizite Abmeldung bleiben wirksam.

Anmelde- und Passwortfelder besitzen explizite Autofill-Rollen. Im Passwortschritt stehen
E-Mail und Passwort gemeinsam bereit. Neue Passwörter und E-Mail-Codes sind gesondert
gekennzeichnet; normale Formularfelder sind vom Credential-Autofill ausgeschlossen.
Speichern wird nur nach bestätigtem Erfolg angefordert, bei Abbruch wird der Kontext verworfen.

Gezielte Prüfungen ohne vollständigen lokalen Testlauf:

- Vor dem Fix scheiterten drei der vier neuen Persistenzregressionen; danach bestanden
  zusammen mit den vorhandenen API-Tests alle 12 Tests.
- Die Persistenztests verwenden reale `PersistCookieJar`-/`SecureCookieStorage`-Abläufe mit
  synthetischem Plattformstore, drei frische App-Instanzen, wechselnde Breite, vorhandene
  Schlüssel und Session-/Challenge-/Workspace-Cookies. Logout und ein fehlschlagender
  Hostread ohne Überschreiben sind ebenfalls geprüft. Keine echten Zugangsdaten verwendet.
- Sechs neue Autofilltests bestanden, einschließlich simulierter
  `TextInputClient.updateEditingStateWithTag`-Befüllung beider Loginfelder sowie Commit/Cancel,
  OTP und Passwortwechsel/-reset. Zwölf bestehende Auth-/Konto-Tests ebenfalls erfolgreich.
- Der Name des konfigurierten Android-Autofill-Dienstes bestätigt Bitwarden. Der private
  Tresor wurde nicht geöffnet oder verändert; reale Passwortvorschläge sind damit noch
  nicht als Geräteabnahme bestätigt. Hinweise zur App-URI stehen in [RELEASE.md](RELEASE.md).

Die finale Flutter-Analyse war ohne Befunde; Formatierung und `git diff --check` ebenfalls
sauber. Die optimierte ARM64-APK wurde am 15. Oktober 2026 um **09:41 Uhr** mit
`adb install -r` erfolgreich als Update auf dem Pixel 9 Pro installiert und die Activity
gestartet. Android bestätigt `versionName=0.2.2`, `versionCode=5`, kein `DEBUGGABLE`-Flag und
den unveränderten Erstinstallationszeitpunkt **14. Oktober, 22:28 Uhr**. Der APK-Signer
entspricht weiterhin den Builds 2–4. Der Server bleibt `https://akribos.de`.

APK: `artifacts/akribos-0.2.2-akribos-de-release.apk`.
SHA-256: `a3dcda7d08498caca6f17ff5558a1f4fe916dda4be3625c54cccd6dc3cb2fe4c`.

Die Sitzungserhaltung wurde über die reproduzierten Persistenztests belegt, nicht durch
Auslesen einer echten Sitzung oder Anmeldung mit privaten Zugangsdaten auf dem Pixel.
Kein Entsperren, kein Zugriff auf Bitwarden-Tresorinhalte, keine Backendänderung.

## Tagdarstellung, Tabgruppen und Lexikon-Dialog, Build 4

Version `0.2.1+4` blendet die globale Tagwolke in Notizübersichten aus. Tagfilter sind
bei Bedarf erreichbar; Tags im Editor und in veröffentlichten Notizen sind zunächst
zugeklappt. Tabgruppen nutzen die A–E-Webfarben mit sichtbaren Buchstaben in Pane-Kopf,
Tabstreifen, Karten und Gruppenmenüs.

Wortklicks öffnen das Lexikon als fast bildschirmhohen, herunterwischbaren Dialog. Der
Bibeltext bleibt einschließlich Scrollposition und Tabanzahl erhalten. Lokale Strong-
Querverweise bleiben im Dialog; Schließen und System-Zurück führen zur Bibel zurück.
Eine ausdrücklich gewählte Fundstelle oder andere Navigation schließt den Dialog zuerst.
Die bestehenden API-Endpunkte reichen aus; es gibt keine Backendänderung.

Gezielte Prüfungen ohne vollständigen lokalen Testlauf:

- `flutter analyze --no-pub`: keine Befunde; Formatierung und `git diff --check` sauber.
- Vier neue Widgettests mit jeweils 1000 Tags erfolgreich, zusätzlich bestehende Prüfung
  schmaler Notizansichten bei großer Schrift. Filter, Rücksetzen, Aufklappen und Bearbeiten
  bleiben nutzbar; die Übersicht rendert keine vollständige Tagliste.
- Sieben Badge-/Karten-Tests erfolgreich: Webpalette, Kontrast mindestens 4,5:1 für die
  Buchstaben in Hell/Dunkel, E-Ink sowie schmale Karten mit großer Schrift.
- 22 gezielte Reader-/Lexikon-/Performance-Tests erfolgreich: Wischen und System-Zurück,
  unveränderter Scrollcontroller und Pixeloffset, keine Workspace-Mutation beim Nachschlagen,
  exakte Wortposition, lokale Strong-Querverweise ohne veraltete Artikelanzeige, Fehler/Retry,
  ausdrücklich gewählte Navigation nach vollständigem Schließen und 320 Pixel bei 200 %
  Schrift/E-Ink. Explizite Lexikon-Tabs bleiben reguläre Tabs.
- Aktuelle Flutter-Aufnahmen mit anonymen öffentlichen Daten visuell geprüft.

Die optimierte ARM64-APK `artifacts/akribos-0.2.1-akribos-de-release.apk` wurde am
15. Oktober 2026 um 09:24 Uhr als Update auf dem **Pixel 9 Pro** installiert (`adb install
-r`: `Success`). Android bestätigt `versionName=0.2.1`, `versionCode=4`, denselben Signer
und kein `DEBUGGABLE`-Flag. Das Activity-Startkommando war erfolgreich. App-Daten wurden
nicht gelöscht; der Server bleibt fest `https://akribos.de`.

SHA-256: `756e8701dd82cc6903e09df33fc57c7a668dcea273b0816839c27f1a42435ec2`.

Das Pixel war bei der anschließenden Sichtprüfung gesperrt. Die automatische Freigabeprüfung
lehnte das Schließen der Displaysperre ohne ausdrückliche Erlaubnis ab; es wurde kein anderer
Entsperrversuch unternommen. Die neue Lexikonbedienung ist deshalb durch Widgettests,
noch nicht durch eine zusätzliche Bedienprüfung dieses Builds am echten Gerät bestätigt.

## Neue mobile Oberfläche, Build 3

Version `0.2.0+3` übernimmt die Akribos-PWA-Farben und gebündelte Leseschrift. Die
Hauptnavigation steht mit seitlichem Abstand am unteren Rand. Geöffnete Werke lassen
sich über Vorschaukarten und Wischen wechseln; am Telefon ist ein geteilter Bildschirm
mit zwei Bereichen optional. Die Quellen und konkrete Übertragung der Logos-Mobile-
Bedienmuster stehen in [MOBILE-DESIGN.md](MOBILE-DESIGN.md).

Gezielte lokale Prüfungen, ohne vollständigen lokalen Testlauf:

- `flutter analyze --no-pub`: keine Befunde; Formatierung und `git diff --check` sauber.
- Shell und schwebende Navigation: 14 Tests erfolgreich. Bereiche behalten ihren Zustand,
  versteckte Weiterleitungen werden beim nächsten Öffnen verarbeitet; bewusstes erneutes
  Öffnen einer Ansicht lädt auch bei identischer URL deren aktuelle Auswahlversion.
- Anmeldung und Kontoinhalte: 12 Tests erfolgreich. Abmeldung entfernt private Ansichten
  auch bei anschließendem Netzfehler; verspätete Antworten stellen kein altes Konto wieder
  her. Änderungen der Schriftgröße erreichen einen bereits geöffneten Reader.
- Vorschaukarten: drei Tests erfolgreich, einschließlich 160–260 Pixel breiter Karten,
  100–300 % Textskalierung, getrennter Menübedienung und E-Ink-Darstellung.
- Reader: 21 gezielte Widget- und Vertragstests erfolgreich. Bei 300 Versen werden weniger als 20
  `VerseText`-Widgets aufgebaut. Ein Tab wird vor seiner verzögerten Serverbestätigung
  angezeigt; die Rückkehr verwendet denselben Scrollcontroller und benötigt keine neue
  Seiten-/Kapitelabfrage. Konflikte bleiben sichtbar und blockieren ungesichertes Verlassen.
  Rasche Tabwechsel speichern seriell mit aktuellen Versionen.
- Die Positionsspeicherung verwendet `resume:true`; geänderte Such-/Notizfilter folgen
  separat mit der zurückgelieferten Version. Genau dieser Ablauf wird gezielt geprüft.
- Reproduzierbare Flutter-Aufnahmen: Telefon hell/dunkel, Tabübersicht, Tablet und E-Ink
  mit anonym abgerufenen öffentlichen Daten. Keine privaten Kontodaten in den Bildern.

Die ARM64-APK `artifacts/akribos-0.2.0-akribos-de-release.apk` wurde als optimierter
AOT-Release gebaut, mit dem vorhandenen Build-2-Schlüssel signiert und am 15. Oktober
um 08:58 Uhr als Update auf dem angeschlossenen **Pixel 9 Pro** installiert (`adb install
-r`: `Success`). Android bestätigt `versionName=0.2.0`, `versionCode=3` und fehlendes
`DEBUGGABLE`-Flag. Die App verwendet weiterhin fest `https://akribos.de`; kein neuer
Backend-Deploy war nötig.

SHA-256: `08315b848d0281dbaeb912ff4871eda83054a9684d24bf9e22de32cb0aa312f3`.

Direkt am Gerät wurden Start, dunkle Leseransicht, eingerückte Hauptnavigation,
Tabübersicht mit Textvorschau, Scrollen und Wechsel Suche → Lesen geprüft. Die Position
blieb nach der Rückkehr erhalten; der vorher sichtbare Speicherfehler erschien nicht.
Im anschließenden gefilterten Flutter-/Android-Runtime-Fehlerlog standen keine Einträge.
Der vorhandene Gerätestand enthielt ein geöffnetes Werk; Wechsel zwischen mehreren
Werken und Smartphone-Split wurden daher über gezielte Widgettests geprüft. Private
Geräteaufnahmen sind nicht im Repository gespeichert. App-Daten wurden weder gelöscht
noch die App vor dem Update deinstalliert.

Diese Prüfungen belegen vermiedene Aufbau- und Netzwerkarbeit. Es wurde kein vergleichender
FPS-Benchmark gegen die PWA durchgeführt. iOS- und Boox-Geräte sind nicht geprüft.

## Vorheriger Prüfstand: 14. Oktober 2026

## Produktionsverbindung, Build 2

Die APK `artifacts/akribos-0.1.0-akribos-de-debug.apk` verwendet fest `https://akribos.de`,
Versionscode 2. Sie wurde am 14. Oktober 2026 erfolgreich auf dem Pixel 9 Pro als Update
installiert; Paketmanager und Signatur bestätigen die Aktualisierung. Für diesen Build
werden weder Testserver noch USB-Weiterleitung verwendet. Das App-Protokoll ist auf
akribos.de live und wurde nach der Bereitstellung mit der nativen Dart-Clientkennung geprüft.

SHA-256: `f24db48083fb64995f9d64e924ba7f120ff7b09d67f2f9263b6c3c6a348069e8`.

## Backend-Veröffentlichung

Die öffentliche API wurde mit [Akribos PR #325](https://github.com/akribos-biblestudy/akribos/pull/325)
als Commit `fb50ceaf5aaeae8b8f680551fa9f374cc0764340` zusammengeführt. Im
[PR-Lauf](https://github.com/akribos-biblestudy/akribos/actions/runs/38636472690)
sind Lint, Typprüfung, sämtliche Unit-/End-to-End-Tests und der Containerbuild erfolgreich.
Die letzte gezielte lokale Prüfung umfasst 40 Adaptertests und den anonymen API-E2E-Test;
ein vollständiger lokaler Testlauf wurde auf ausdrücklichen Wunsch nicht wiederholt.
Der [Produktionslauf](https://github.com/akribos-biblestudy/akribos/actions/runs/38638016098)
war vollständig erfolgreich: 1.272 Unit-Tests und 305 End-to-End-Tests bestanden,
Produktionsimage veröffentlicht und Coolify per POST erfolgreich angestoßen.

Die anschließende schreibfreie HTTPS-Prüfung gegen `https://akribos.de` bestätigte:

- `/healthz`: HTTP 200 und `status: ok`.
- `/api/app/bootstrap`: HTTP 200, Protokoll 1, öffentliche Ressourcen und `user: null`,
  ohne Authorization-Header, API-Schlüssel oder Session-Cookie.
- `/api/app/page?path=/Joh3,16`: native Readerdaten einschließlich strukturierter
  Textsegmente von Johannes 3,16.
- `/api/documents`: anonym HTTP 401; `/admin/resources` im App-Adapter HTTP 404.
- Fremde Browser-Origin: HTTP 403; erfolgreiche App-Antworten `private, no-store`.

Ein kurzzeitiges HTTP 502 während des Containerwechsels war nach Abschluss verschwunden.
Die Live-Prüfung bestätigt Server und öffentliches App-Protokoll. Der Produktionsbuild
wurde auf dem Pixel installiert; die Bedienung dieses Builds gegen die Live-Instanz
wurde anschließend nicht erneut am Gerät beobachtet.

## Frühere lokale Prüfungen

| Prüfung | Ergebnis |
| --- | --- |
| Flutter 3.47.0 / Dart 3.13.0, finale Abhängigkeiten | Lockfile unverändert auflösbar |
| `flutter analyze` im endgültigen Repository | Keine Befunde |
| Vollständige Flutter-Suite mit isoliertem HTTP-Testserver | 52 Tests erfolgreich |
| Smartphone-/Tablet-Widgets | 320, 840 und 1280 Pixel; zusätzliche Tests mit 170 % Textskalierung |
| E-Ink | Persistente Einstellung, Kontrast, Dialogkontext und Bildschirmblättern geprüft |
| App-Protokoll im Akribos-Backend | 38 Unit-Tests erfolgreich |
| Produktionsbuild-API-E2E im Backend | 3 Tests erfolgreich |
| Akribos `pnpm check` | Keine Fehler; 14 bereits vorhandene Warnungen |
| Android Debug-/Release-Manifest-Merge | Erfolgreich |
| Android arm64 Debug-APK | Erfolgreich gebaut |
| Pixel 9 Pro über USB | APK installiert, App gestartet und native Readeransicht am Gerät sichtbar |

Der echte Dart-HTTP-Test prüft Anmeldung, Reader, Anlegen und Speichern einer Notiz,
Ablehnung einer veralteten Revision, Erstellen/Befüllen/Löschen einer Sammlung sowie Abmeldung.
Die Backend-E2E-Tests prüfen zusätzlich E-Mail-Code-Anmeldung, private Inhalte, Multipart,
Origins und die Verwaltungsgrenze, auch für angemeldete Administratoren.

Die inzwischen ersetzte Pixel-Testversion `0.1.0+1` verwendete `http://127.0.0.1:4176`, das per
`adb reverse tcp:4176 tcp:4176` zum lokalen Testserver weitergeleitet wurde. Die frühere APK
liegt unter `artifacts/akribos-0.1.0-pixel-local-debug.apk` (nicht versioniert). Der lokale
Server ist beendet; diese Variante wird nicht mehr für den Gerätebetrieb verwendet.

Der Testserver verwendet ausschließlich eine separate E2E-Datenbank. Zusätzlich zum
minimalen Seed wurde die im Akribos-Repository vorhandene öffentliche Luther 1912 als
`APPDEMO_LUTH1912` importiert: 66 Bücher, 31.171 Verse. Bestehende Testressourcen bleiben
unverändert. Die vollständige Bibel lässt sich über die Ressourcenwahl öffnen.

## Noch offen

Keine vollständige Abnahme von Notizbearbeitung, System-Dateiauswahl und Teilen auf echten
Geräten. Kein iOS-Xcode-Build auf dieser Linux-Maschine, kein iPhone-/iPad- oder Boox-Test.
Die Flutter-GitHub-Workflowdatei wurde angelegt, aber noch nicht auf einem Remote ausgeführt.
Eine eigene Store-Signierung, verifizierte HTTPS-App-Links und Store-Uploads sind nicht erfolgt.
Vollständige lokale Testläufe sind auf Wunsch keine Release-Voraussetzung mehr; gezielte
Prüfungen laufen lokal, umfassende Unit-/E2E-Prüfungen in der bestehenden CI.
