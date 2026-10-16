# Akribos: Inhalte für Google Play

Stand: 16. Oktober 2026. Die ursprünglich elf Einrichtungspunkte der App sind in der
Play Console gespeichert: neun Erklärungen zu App-Inhalten, Kategorie/Kontakt und
Store-Eintrag. Nach dem ersten Bundle kam die Erklärung zur Werbe-ID hinzu; sie ist
mit **Nein** gespeichert. Die Console zeigte anschließend **„Alles erledigt“** und
zehn abgeschlossene Erklärungen. Das dokumentiert den Console-Stand, keine umfassende
Google-Freigabe oder Bestätigung aller Betriebs- und Moderationsanforderungen.

Der deutsche Haupt-Store-Eintrag, Kontaktangaben, 1 App-Icon, 1 Funktionsgrafik und
4 Screenshots wurden committed und zurückgelesen. Alle Texte/Kontaktwerte und die
Bildhashes stimmten überein. Das Bootstrap-Bundle **0.3.0+13** wurde anschließend
manuell hochgeladen und im internen Test als `completed`/verfügbar bestätigt.
Der am selben Tag gestartete automatische Releaseauftrag **0.3.1** ist separat in
[PLAY-STORE.md](PLAY-STORE.md) mit den zugehörigen Workflow-Referenzen dokumentiert. Es wurde keine
öffentliche Veröffentlichung vorgenommen und kein Preis-/Länderumfang für Produktion
geändert. Die Store-Texte müssen weiterhin zum jeweils ausgelieferten Bundle passen.

## Direkt verwendbare Store-Texte

| Feld | Datei | Grenze |
| --- | --- | --- |
| App-Name | [title.txt](../store/de-DE/title.txt) | 30 Zeichen |
| Kurzbeschreibung | [short-description.txt](../store/de-DE/short-description.txt) | 80 Zeichen |
| Vollständige Beschreibung | [full-description.txt](../store/de-DE/full-description.txt) | 4.000 Zeichen |
| Änderungen des ersten internen Tests | [release-notes.txt](../store/de-DE/release-notes.txt) | 500 Unicode-Zeichen |

Sprache: `de-DE`. Paketname: `de.akribos.app`. Die Beschreibung verspricht weder
Offline-Bibelpakete noch eine verfügbare iOS-App oder Zugang zu jedem Werk.
Die Release Notes enthalten keine feste Versionsnummer; die kommt aus dem Release-Build.
[Google erläutert die Release Notes und ihre Zeichengrenze.](https://support.google.com/googleplay/android-developer/answer/9859348?hl=de)

## Gespeicherte Console-Angaben

| Console-Feld | Gespeicherter Wert / bestätigter Stand |
| --- | --- |
| Support-E-Mail / Website | `info@akribos.de` / `https://akribos.de`; committed und zurückgelesen |
| Typ / Kategorie | App / Bücher & Nachschlagewerke |
| Datenschutzerklärung | `https://akribos.de/datenschutz`; native App und Löschantrag sind veröffentlicht, siehe Live-Nachweis unten |
| App-Zugriff / Anmeldedaten | Einige Funktionen erfordern Anmeldung; dediziertes normales Prüfkonto mit dauerhaftem Passwort, siehe Reviewzugang |
| Anzeigen | Nein; keine Werbeeinbindung im geprüften Client, seinen Abhängigkeiten oder der isolierten Editorseite |
| Werbe-ID | Nein; nach dem ersten Bundle zusätzlich gespeichert, keine Werbe-ID-Berechtigung im geprüften Release-Manifest |
| Zielgruppe und Inhalte | Vom Betreiber ausdrücklich bestätigt und gespeichert: 13–15 Jahre, 16–17 Jahre und 18+ |
| Altersfreigaben | Vom Nutzer ausgefüllter IARC-Fragebogen abgeschlossen; Ergebnis unten, Einzelantworten nicht vollständig unabhängig geprüft |
| Datensicherheit | Gespeichert und aus der Console exportiert; alle 782 Antwortfelder stimmen mit dem vorbereiteten Import überein |
| Behörden-Apps | Nein; private Bibelstudienanwendung, keine erklärte behördliche Beauftragung |
| Finanzfunktionen | Meine App bietet keine Finanzfunktionen |
| Gesundheits-Apps | Meine App bietet keine Gesundheitsfunktionen |
| Store-Eintrag | Deutscher Haupt-Store-Eintrag einschließlich Kontakt, Icon, Funktionsgrafik und 4 Screenshots bestätigt |

Preis, Produktionsländer und öffentliche Veröffentlichung waren nicht Teil dieses internen
Releases. Das öffentliche Impressum nennt Mirko Hecky, Hosleite 13, 95478 Kemnath,
Deutschland, und `info@akribos.de`; es ersetzt keine Prüfung der separaten
Play-Konto-/Organisationsdaten. Keine nicht belegte Telefonnummer wurde ergänzt.
[Öffentliches Impressum](https://akribos.de/impressum).

Die Angaben zu Kategorie, Anzeigen, Behörden-, Finanz- und Gesundheitsfunktionen beruhen
auf dem tatsächlichen Reader-/Nachschlagezweck und den geprüften Funktionen. Bibeltexte
über Geld, Heilung oder historische Regierungen begründen allein keine entsprechende
App-Funktion. Neue Funktionen erfordern eine erneute Prüfung der Erklärungen.
[App-Kategorien](https://support.google.com/googleplay/android-developer/answer/9859673?hl=de),
[Anzeigen erklären](https://support.google.com/googleplay/android-developer/answer/9859455?hl=de),
[Behörden-Apps](https://support.google.com/googleplay/android-developer/answer/9514050?hl=de),
[Finanzfunktionen](https://support.google.com/googleplay/android-developer/answer/13849271?hl=de),
[Gesundheitsfunktionen](https://support.google.com/googleplay/android-developer/answer/14738291?hl=de).

## IARC: gespeicherte Einstufung und Prüfgrenzen

Der Nutzer hat den IARC-Fragebogen selbst abgeschlossen. Am 16. Oktober 2026 wurden
in der Console der abgeschlossene Status, Kontakt `info@akribos.de`, die Kategorie
„Alle anderen App-Typen“ und „Online-Inhalte: Ja“ bestätigt. Angezeigte Ergebnisse:

| Region / System | Angezeigte Einstufung |
| --- | --- |
| Deutschland / USK | 0 |
| PEGI | 3 |
| ESRB | Everyone |
| Brasilien | 0 |
| IARC allgemein | 3 |
| Russland | 3 |
| Korea | 3 |

Die einzelnen Antworten wurden nicht vollständig unabhängig geprüft. Diese Tabelle gibt
das gespeicherte Ergebnis wieder; sie bestätigt weder eine vollständige inhaltliche
Prüfung der Bibelquellen noch aller serverseitigen oder nutzergenerierten Inhalte.
Die gewählte Zielgruppe ab 13 Jahren bleibt von diesen Inhaltsfreigaben getrennt.
[IARC-FAQ](https://www.globalratings.com/faq/),
[Googles Einstufungsverfahren](https://support.google.com/googleplay/android-developer/answer/9859655?hl=de).

Für künftige Änderungen sind die tatsächlich verfügbaren Funktionen maßgeblich:
Bibeltexte und Nachschlagewerke werden online geladen; Nutzer können Sammlungen,
Kommentare, Antworten, Reaktionen und freigegebene Notizen anderen zugänglich machen.
Standortfreigabe, digitale Käufe, Glücksspiel und Gewinne wurden nicht gefunden.
Textbeschreibungen, Bilder und Geräusche sind bei den konkreten Fragen zu unterscheiden.
Die folgenden Befunde bleiben trotz abgeschlossenem Fragebogen relevant.

### Bibeltext ist nicht pauschal inhaltsneutral

Die versionierte Quelle `../akribos/data/bibles/GER_LUTH1912.xml` enthält beispielsweise:

| Themenbereich | Konkrete Textstelle |
| --- | --- |
| Gewalt / Enthauptung | 1. Samuel 17,51 |
| Sexuelle Gewalt | 2. Samuel 13,14 |
| Sexualbezogene Beschreibung | Hesekiel 23,20 |
| Alkohol / Rausch und Nacktheit | 1. Mose 9,21 |
| Suizid | Matthäus 27,5 |

Diese Beispiele wurden im Quelltext geprüft; sie sind keine vollständige Inhaltsprüfung aller
aktuell serverseitig angebotenen Werke oder nutzergenerierten Inhalte. Bei Fragen nach
Erwähnungen oder Beschreibungen sind diese Textinhalte zu berücksichtigen. Fragen ausschließlich
nach visuellen oder akustischen Darstellungen müssen gesondert beantwortet werden.
Eine allgemeine Ausnahme für religiöse Texte ist nicht belegt. Stärke, Häufigkeit und Kontext
anhand der konkreten Unterfragen und tatsächlich ausgelieferten Ressourcen bewerten, statt
pauschal „Nein“ oder eine gewünschte Altersfreigabe vorzugeben. Die Einstufung folgt aus den
Antworten; bei einer unpassenden Einstufung besteht der offizielle Prüf-/Einspruchsweg.
[Google zur vollständigen und zutreffenden Einstufung](https://support.google.com/googleplay/android-developer/answer/9859655?hl=de).

### UGC: tatsächliche Funktionen und noch fehlende Schutzwege

Google zählt nutzergenerierte Inhalte (UGC) bereits dann dazu, wenn sie wenigstens einem Teil
anderer Nutzer zugänglich sind. Einladungsbasierte Zusammenarbeit und nicht gelistete Leselinks
schließen UGC daher nicht aus. Die App bietet diese Funktionen tatsächlich; private Notizen
werden dadurch weiterhin nicht automatisch veröffentlicht.
[Google: UGC-Richtlinie](https://support.google.com/googleplay/android-developer/answer/9876937?hl=de).

In `lib/features/collections/collections_screen.dart` sind Kommentare, Antworten, Reaktionen,
Einladungen und freigebbare Leselinks vorhanden. Eigentümer können Kommentare und Mitglieder
entfernen. `lib/features/documents/documents_screen.dart` zeigt veröffentlichte Notizen an.
Ein klarer Melde-/Blockierablauf für alle betroffenen Nutzer sowie eine verpflichtende
Zustimmung zu UGC-Nutzungsregeln wurden im geprüften Client nicht gefunden. Eine vollständige
Inhaltsmoderation wurde ebenfalls nicht nachgewiesen.

Google verlangt angemessene laufende Moderation, Regeln und je nach Interaktionsform
Melde-/Blockierfunktionen innerhalb der App. Das sind offene Produkt-/Betriebsanforderungen,
keine fehlenden Kreuze, die sich durch pauschale Nein-Antworten erledigen lassen.
[Google erläutert Melden, Blockieren und Moderation](https://support.google.com/googleplay/android-developer/answer/12923286?hl=de).

## Datenflüsse und gespeicherte Datensicherheitsangaben

Die Erklärung umfasst den nativen Client und die selbst kontrollierte Editor-WebView.
Übertragungen zum eigenen Server gelten als Erhebung; reine lokale Verarbeitung nicht.
Die gespeicherte Einordnung verwendet Googles Definitionen einschließlich der Ausnahmen
für weisungsgebundene Dienstleister und erwartetes, vom Nutzer veranlasstes Teilen.
[Google: Datensicherheit](https://support.google.com/googleplay/android-developer/answer/10787469?hl=de).

### Verifizierter Import und Rückexport

Die zuerst öffentlich verlinkte Vorlage hatte 763 Zeilen. Für die tatsächliche Einreichung
wurde die aktuelle offizielle Console-Vorlage mit **782 Antwortfeldern** verwendet;
sie enthält auch Kontotypen und die Lösch-URL. Der Import wurde von der Console validiert
und gespeichert. Der anschließende Console-Export wurde nach Frage-ID und Antwort-ID
verglichen: **alle 782 Antworten identisch**, nach Normalisierung von `TRUE`/`true` und
`FALSE`/`false`; nicht nur die ausgewählten Antworten wurden geprüft.

| Lokaler Prüfbeleg, nicht eingecheckt | SHA-256 |
| --- | --- |
| `/tmp/akribos-current-data-safety.csv` (Import) | `bee575d0dad681248db8176c9379eb6692b7983156011a250c26a24e5148594d` |
| `/tmp/akribos-data-safety-console-readback.csv` (Rückexport) | `8cd7064fb161501c48e19c09280b4224402b9de0fe1130b4018f59904e7afa40` |

Die temporären Dateien sind lokale Prüfbelege und kein dauerhaft verfügbares Archiv.
Die folgende Tabelle hält die gewählten Datenarten und ihre Begründungen im Repository fest.
Die technische Herleitung wurde zusätzlich in `/tmp/akribos-data-safety-rationale.txt`
festgehalten; dessen früherer Vorbereitungsstatus wird durch den bestätigten Import ersetzt.

### 17 ausgewählte Datenarten

Für alle folgenden Arten ist **Erhoben** ausgewählt, **Geteilt** nicht ausgewählt und
**nur flüchtig verarbeitet** auf **Nein** gesetzt. „Optional“ bedeutet, dass die
entsprechende Konto-, Eingabe- oder Uploadfunktion freiwillig genutzt werden kann;
öffentliche Texte können ohne Konto gelesen werden. Es ist keine Lösch- oder
Speicherfristen-Zusage. Die Zweckangabe „Analyse“ betrifft die belegte technische
Diagnose und bedeutet hier keine eingebundene Werbe- oder Analytics-Bibliothek.

| Datenart (Console-ID) | Erforderlich? | Gespeicherte Zwecke | Tatsächlicher Datenfluss |
| --- | --- | --- | --- |
| Name (`PSL_NAME`) | Optional | App-Funktion, Kontoverwaltung | Anzeigename im Konto und bei freigegebenen Sammlungen |
| E-Mail-Adresse (`PSL_EMAIL`) | Optional | App-Funktion, Kontoverwaltung, Sicherheit | Konto, Anmeldung, Adressbestätigung und adressbezogene Limits |
| Nutzer-IDs (`PSL_USER_ACCOUNT`) | Optional | App-Funktion, Kontoverwaltung, Sicherheit | Konto-ID, Besitzprüfungen und Nutzerlimits |
| Andere Nachrichten (`PSL_OTHER_MESSAGES`) | Optional | App-Funktion | Kommentare und Antworten in gemeinsamen Sammlungen |
| Fotos (`PSL_PHOTOS`) | Optional | App-Funktion | Ausdrücklich ausgewählte Fotoanlagen |
| Videos (`PSL_VIDEOS`) | Optional | App-Funktion | Ausdrücklich ausgewählte Videoanlagen |
| Sprach-/Tonaufnahmen (`PSL_AUDIO`) | Optional | App-Funktion | Ausdrücklich ausgewählte Aufnahmen als Anlagen |
| Musikdateien (`PSL_MUSIC`) | Optional | App-Funktion | Ausdrücklich ausgewählte Musikdateien als Anlagen |
| Andere Audiodateien (`PSL_OTHER_AUDIO`) | Optional | App-Funktion | Ausdrücklich ausgewählte weitere Audioanlagen |
| Dateien und Dokumente (`PSL_FILES_AND_DOCS`) | Optional | App-Funktion | Ausgewählte Dateien/Anlagen einschließlich Dateinamen |
| Kontakte (`PSL_CONTACTS`) | Optional | App-Funktion | E-Mail-Einladungen, Mitgliedschaften und Interaktionsbeziehungen; kein Telefonadressbuchzugriff |
| Suchverlauf in der App (`PSL_IN_APP_SEARCH_HISTORY`) | Optional | App-Funktion | Explizite Suchanfragen an den Server |
| Andere nutzergenerierte Inhalte (`PSL_USER_GENERATED_CONTENT`) | Optional | App-Funktion | Notizen, Ausarbeitungen, Tags und eigene Sammlungen |
| Andere Aktionen (`PSL_OTHER_APP_ACTIVITY`) | Optional | App-Funktion | Markierungen und Kommentarreaktionen |
| App-Interaktionen (`PSL_USER_INTERACTION`) | Ja | App-Funktion, Analyse | Angeforderte Kapitel/Seiten; langsame Requestpfade mit Dauer und Status |
| Diagnosedaten (`PSL_PERFORMANCE_DIAGNOSTICS`) | Ja | Analyse | Serverseitige Slow-Request-Dauer und HTTP-Status |
| Geräte- oder andere IDs (`PSL_DEVICE_ID`) | Ja | App-Funktion, Sicherheit | Laufzeit-UUID `x-reader-browser-tab`, Netzwerk-/Sitzungsidentifikation und IP-basierter Missbrauchsschutz; keine Werbe-ID |

Tabs, Lesepositionen und Suchzustand werden im nativen lokalen Reader gerätelokal
gehalten; die Tabelle behauptet keine dauerhafte serverseitige Lesefortschrittsspeicherung.
Die Dateiauswahl und das Backend erlauben Anlagen beliebiger Dateitypen bis zur
Größenbegrenzung. Deshalb sind die unterstützten Foto-, Video- und Audiokategorien
angegeben, auch ohne Kamera-/Mikrofonzugriff der App.

Nicht ausgewählt wurden Standort, Finanz-/Gesundheitsprofile, Telefon/SMS/Postfach,
Kalender, installierte Apps oder Werbezwecke: dafür wurde im geprüften Client keine
positive Funktionsevidenz gefunden. Ein eigenes Religionsprofil existiert nicht;
freier Notiztext wird als nutzergenerierter Inhalt eingeordnet. Eine etwaige zusätzliche
Erhebung oder Auswertung beim Infrastrukturbetreiber muss gesondert bewertet werden.

### Sicherheits- und Kontoangaben

- Erhebung personenbezogener Daten: **Ja**; Verschlüsselung bei Übertragung: **Ja**.
  Release-Verbindungen verwenden HTTPS, Android verbietet Klartextverkehr. Das ist
  keine Ende-zu-Ende-Verschlüsselung der serverseitigen Notizen.
- Kontotypen: **Nutzer-ID und Passwort** sowie **Nutzer-ID und andere Authentifizierung**
  (E-Mail-Link/Code). Keine OAuth-, kombinierte Mehrfaktor- oder kontofreie Erklärung.
- Kontolösch-URL: `https://akribos.de/datenschutz#konto-loeschen`.
- Die optionale Erklärung zur separaten Datenlöschung ohne Kontolöschung und deren URL
  bleiben leer. Keine automatische Löschung innerhalb einer bestimmten Tagesfrist,
  unabhängige Sicherheitszertifizierung oder Familienprogramm-Zusage eingetragen.
- „Geteilt“ ist nach den oben genannten Google-Ausnahmen nicht ausgewählt. Das bedeutet
  nicht, dass keine Dienstleister beteiligt sind oder ausdrücklich freigegebene Inhalte
  keine Empfänger erreichen. Reale Empfänger, Verträge und Provider-Konfigurationen
  bleiben unabhängig vom erfolgreichen Formularimport zu prüfen.

Prüfung der eingebundenen Technik:

- `pubspec.yaml` enthält Flutter, HTTP-/Cookie-Speicher, sicheren Speicher, Dateiauswahl,
  Teilen, Linköffnung und System-WebView; kein Firebase-, Werbe-, Sentry- oder
  Crashlytics-SDK gefunden. Das allein ersetzt keine Prüfung serverseitiger Dienste.
- Das untersuchte zusammengeführte Release-Manifest enthält `INTERNET` und die app-eigene
  `DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION`. Keine Standort-, Kamera-, Mikrofon-,
  Kontakt-, Werbe-ID- oder weitreichende Medienleseberechtigung gefunden.
- Dateizugriff erfolgt auf ausdrückliche Auswahl; Teilen/Export verwendet das Systemmenü.
  Zwischenexporte liegen im privaten App-Verzeichnis.
- Der native Reader sendet Anfragen an `akribos.de`. Die Editor-WebView lädt
  `/app/editor/[id]`; dort deaktiviert der Webserver Analytics ausdrücklich. Browserseiten,
  die der Nutzer extern öffnet, haben ihre eigenen Hinweise und ggf. Einwilligungen.
- Das Backend besitzt Brevo-Mailversand sowie technische Request-/Ratelimit-Verarbeitung.
  Der Betreiber hat Hetzner Cloud als Hosting und Coolify mit Standard-Logging bestätigt.
  Konkrete Log-Aufbewahrung und Zugriffsrechte, Cloudflare-Vertrag/Konfiguration,
  Mail-Aufbewahrung, Datenbank-Backups und mögliche GeoIP-Auswertung sind damit noch
  **nicht abschließend geprüft**.
- Keine Standortfunktion im App-Code gefunden. Eine vom Infrastrukturbetreiber aktivierte
  IP-Geolokalisierung wäre separat zu bewerten; nicht als geprüft ausgeschlossen ankreuzen.

Quellen im Code: `pubspec.yaml`, `android/app/src/main/AndroidManifest.xml`,
`lib/core/api_client.dart`, `lib/features/reader/reader_local_store.dart`,
`lib/features/documents/document_editor.dart`, `lib/features/documents/document_draft.dart`,
`lib/features/help/help_screen.dart`; im Web-Repository `src/routes/+layout.server.ts`,
`src/hooks.server.ts`, `src/lib/server/mail/index.ts`,
`src/routes/api/documents/[id]/attachments/+server.ts` und
`src/lib/server/repositories/document-attachments.ts`.

## Konto-Löschung und Datenschutzerklärung: veröffentlicht

Der Konto-Bildschirm bietet „Konto und Daten löschen“ mit „Löschung anfordern“.
Der Button öffnet `/datenschutz#konto-loeschen` am eingestellten Akribos-Server, in
Produktion also `https://akribos.de/datenschutz#konto-loeschen`. Keine Konto-ID,
Zugangsdaten oder Sitzung werden in die URL aufgenommen. Öffnungsfehler bleiben
sichtbar. Der Button startet einen Antrag; er löscht kein Konto und meldet nicht ab.
Ein automatischer benutzerseitiger Konto-Löschendpunkt wurde nicht ergänzt.

Die Web-Erweiterung wurde mit
[PR #328](https://github.com/akribos-biblestudy/akribos/pull/328) veröffentlicht:
Commit `b548a4a649c2dc4c084e02ee280ee854051eb285`,
[Main-CI 38937820390](https://github.com/akribos-biblestudy/akribos/actions/runs/38937820390)
erfolgreich einschließlich Image-Publish und Coolify-Trigger. Live-Prüfung am
16. Oktober 2026 um **17:24 UTC**: `/datenschutz` HTTP 200, genau ein
`konto-loeschen`-Anker, sichtbarer Löschabschnitt und Mailto an `info@akribos.de`
mit Betreff „Akribos-Konto löschen“; `/healthz` HTTP 200 mit `{"status":"ok"}`.
[Veröffentlichter Löschweg](https://akribos.de/datenschutz#konto-loeschen).

Die öffentliche Seite erklärt den Antrag mit Identitätsprüfung und ohne Übermittlung
von Passwörtern/Codes. Sein Umfang umfasst Kontodaten, Notizen/Ausarbeitungen, Anlagen,
Markierungen, Sammlungen und Kommentare. Die vom Betreiber bestätigten **sieben Tage**
beziehen sich auf die Antragsbearbeitung, nicht auf eine pauschale Frist für sämtliche
Sicherungs- oder Dienstleisterkopien. Die Durchführung einer vollständigen Löschung
wurde damit nicht getestet oder automatisch nachgewiesen.

Die Datenschutzerklärung deckt nun auch E-Mail-Link/Code und optionales Passwort,
native HTTPS-Zugriffe, öffentliche Texte ohne Anmeldung, Kontoinhalte und ausgewählte
Anlagen, verschlüsselte lokale Sitzung/Tabs/Entwürfe, den eingebetteten Editor ohne
Analytics, Systemteilen und temporäre Exportdateien ab. Abmelden oder Deinstallieren
löscht das Serverkonto nicht. Hosting bei Hetzner Cloud und größenabhängige Rotation
der App-Server-Protokolle sind beschrieben, ohne erfundene Tagesfrist oder Serverland.
Sicherungskopien können bis zur Rotation bestehen; Sonderkopien sind gesondert zu
berücksichtigen. Eine feste Backup-Löschfrist wurde nicht zugesagt.

Der native Einstieg fehlt im älteren Bootstrap-Bundle `0.3.0+13` und ist im Quellstand
`e7210efe8f06f01433b69a396f3cd34160b6b743` für den Folgerelease enthalten.
Build-/Store-Nachweis und die Grenze zur noch ausstehenden Play-Geräteprüfung stehen
in [PLAY-STORE.md](PLAY-STORE.md). Der veröffentlichte Webweg und die
Codeprüfung des nativen Einstiegs ersetzen keinen vollständigen Löschtest einschließlich Anlagen,
Mitgliedschaften, Dienstleisterdaten und Backups.
[Google: Konto-Löschung](https://support.google.com/googleplay/android-developer/answer/13327111?hl=de).

## Reviewzugang: eingerichtet und geprüft

Das dedizierte Konto `stores@akribos.de` wurde als normaler Nutzer mit Rolle `user`
und dauerhaftem Passwort geprüft. Ein isolierter Login war erfolgreich; der Passwortweg
benötigt keinen kurzlebigen E-Mail-Code. Die Zugangsanleitung und Zugangsdaten wurden
in den geschützten Console-Feldern für App-Zugriff gespeichert. Das Google-Dienstkonto
für Store-Uploads ist davon getrennt.

Die lokale geschützte Ablage ist
`~/.config/akribos/play-review/reviewer-credentials.json`. Der Inhalt gehört nicht in
Git, Dokumentation, Chat oder Screenshots und wurde für diese Dokumentationsänderung
nicht gelesen. Das Konto darf keine Adminrechte oder privaten Echtdaten benötigen.
[Google: App für die Überprüfung vorbereiten](https://support.google.com/googleplay/android-developer/answer/9859455?hl=de).

Zugangsanleitung ohne Zugangsdaten:

```text
The public Bible reader can be used without signing in. To review personal notes,
highlights, collections and account settings, tap the person icon at the top right
("Anmelden"). Enter the review account email supplied in the credentials field,
tap "Weiter", then enter its password and sign in. This dedicated account uses
password sign-in; an email verification code is not required.

Use "Lesen" to open the Bible reader. Tap a verse number to open its actions.
"Markieren" opens the available highlight colors. "Notizen" opens personal
notes and preparations. "Mehr" > "Einstellungen" contains text presentation,
reading font, default Bible and highlight colors. "Mehr" > "Sammlungen" opens
verse collections. The service endpoint is https://akribos.de. An internet
connection is required. No API key, USB connection or administrator role is needed.
```

Der erfolgreiche isolierte Login bestätigt den Kontozugang; eine vollständige
Geräteabnahme aller angemeldeten Funktionen mit dem jeweils ausgelieferten
Play-Bundle ist davon getrennt.

## Verbleibende Betriebs- und Produktprüfungen

- Die abgeschlossenen Console-Formulare belegen keine umfassende Richtlinienprüfung.
  Insbesondere bleiben die oben dokumentierten UGC-Melde-/Blockier- und Moderationswege
  sowie die vollständige Prüfung der IARC-Einzelantworten relevant.
- Hetzner Cloud und die sieben Tage für Löschantragsbearbeitung sind bestätigt.
  Tatsächliche CDN-/Mailkonfiguration, Verträge, Verarbeitungsorte, Log-/Mailfristen,
  Zugriffsrechte und mögliche GeoIP-Auswertung sind nicht abschließend geprüft.
- Im Backup-Code sind Aufbewahrungswerte Anzahlen erfolgreicher Sicherungen, keine
  Tagesfristen. Rotation erfolgt erst nach erfolgreicher Sicherung; spezielle
  Vor-Wiederherstellungs-Sicherungen sind ausgenommen. Aktivierung, Live-Konfiguration,
  vorhandene Sonderkopien und der vollständige Löschablauf brauchen eine Betriebsprüfung.
- Ein erster manueller interner Release und der nachfolgende automatische Storelauf
  sind von tatsächlicher Installation und Funktionsprüfung durch einen freigegebenen
  Google-Play-Tester zu unterscheiden. Preis, Produktionsländer und ein öffentlicher
  Rollout bleiben außerhalb dieses Auftrags.
