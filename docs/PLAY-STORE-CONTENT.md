# Akribos: Inhalte für Google Play

Stand: 16. Oktober 2026. Grundlage sind der aktuelle lokale App-Code und das zugehörige
Web-Repository, einschließlich der neuen Einstellungen und des kompakten Versmenüs.
Der deutsche Haupt-Store-Eintrag und die Kontaktangaben wurden erfolgreich in Google Play
übernommen. Name, Kurzbeschreibung, vollständige Beschreibung und Kontaktwerte wurden danach
zurückgelesen und verglichen. Auch 1 App-Icon, 1 Funktionsgrafik und 4 Screenshots wurden
übernommen; die zurückgelesenen Bildhashes stimmen mit den hochgeladenen Dateien überein.
Beim anschließenden Rücklesen waren alle Tracks weiterhin leer. Damit ist der Store-Eintrag
bestätigt, noch kein App-Release oder vollständig ausgefüllter App-Inhaltsbereich.
Die Texte setzen voraus, dass genau dieser Funktionsstand im Store-Bundle enthalten ist.

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

## Kontaktdaten und Console-Felder

| Console-Feld | Konkreter Wert / Stand |
| --- | --- |
| Support-E-Mail | `info@akribos.de` |
| Website | `https://akribos.de` |
| Datenschutzerklärung | `https://akribos.de/datenschutz`; vor einem öffentlichen Release inhaltlich um die App ergänzen, siehe Entwurf unten |
| Typ | App |
| Kategorie | Bücher & Nachschlagewerke; fachlich aus dem Reader-/Nachschlagezweck abgeleitet, Console-Speicherung noch nicht bestätigt |
| Enthält Werbung | Nein für den geprüften Funktionsstand; keine Werbeeinbindung im Client, seinen Abhängigkeiten oder der isolierten Editorseite gefunden. Erklärung noch nicht bestätigt |
| App-Zugriff | Einige Funktionen erfordern Anmeldung; Prüfkonto für Notizen, Markierungen, Einstellungen und Sammlungen erforderlich |
| Alterszielgruppe | Vom Betreiber am 16. Oktober 2026 bestätigt: 13–15 Jahre, 16–17 Jahre und 18+; Console-Speicherung noch nicht bestätigt |
| Preis und Länder | **Betreiberentscheidung offen.** Nicht aus technischer Funktionsfähigkeit ableiten |
| Entwickleranzeige / rechtlicher Kontoinhaber | **Mit der tatsächlich verifizierten Play-Identität abgleichen.** Öffentliches Impressum nennt Mirko Hecky |
| Telefonnummer | Nicht im untersuchten öffentlichen Impressum vorhanden; keine Nummer erfunden |

Support-Adresse, Mirko Hecky und die Anschrift Hosleite 13, 95478 Kemnath, Deutschland,
stehen im versionierten Impressum. Der öffentliche Abruf von Impressum und Datenschutzseite
lieferte am 16. Oktober 2026 HTTP 200. Die von Cloudflare im öffentlichen HTML kodierte
E-Mail-Adresse wurde als `info@akribos.de` bestätigt. Diese Angaben ersetzen keine Prüfung
der separaten Play-Konto-/Organisationsdaten.
[Öffentliches Impressum](https://akribos.de/impressum),
[öffentliche Datenschutzerklärung](https://akribos.de/datenschutz).

## Vorbereitete Erklärungen zu App-Inhalten

Die folgenden Werte sind aus dem untersuchten Funktionsstand abgeleitet und noch keine
Bestätigung, dass diese Console-Formulare gespeichert oder von Google geprüft wurden.
Die genaue deutsche Beschriftung kann in der Console abweichen.

| Console-Feld | Vorbereitete Angabe | Beleg und Grenze |
| --- | --- | --- |
| Kategorie | App → Bücher & Nachschlagewerke | Bibelreader, Kommentare und Wörterbücher entsprechen Googles Beispielen für diese Kategorie |
| Anzeigen | Nein | Keine Werbe-SDKs, Banner, Interstitials oder nativen Anzeigen im geprüften Client und Editor gefunden; selbst eingebaute Anzeigen würden ebenfalls zählen |
| Behörden-Apps | Nein, sofern keine bislang nicht genannte behördliche Beauftragung besteht | Impressum und Produkt beschreiben eine private Bibelstudienanwendung; die tatsächliche institutionelle Verbindung ist eine Betreiberangabe |
| Finanzfunktionen | Meine App bietet keine Finanzfunktionen | Keine Bank-, Kredit-, Zahlungs-, Wallet-, Anlage-, Versicherungs- oder Finanzberatungsfunktion gefunden |
| Gesundheit | Meine App bietet keine Gesundheitsfunktionen | Keine Gesundheitsdaten-Anbindung, Diagnose, Behandlung, Fitness-, Meditations- oder medizinische Beratungsfunktion gefunden |

Bibeltexte über Geld, Heilung oder historische Regierungen begründen allein keine entsprechende
App-Funktion. Zusätzliche Kategorien nur wählen, wenn die App diese Funktionen tatsächlich
bereitstellt. Aktuelle offizielle Grundlagen:
[App-Kategorien](https://support.google.com/googleplay/android-developer/answer/9859673?hl=de),
[Anzeigen erklären](https://support.google.com/googleplay/android-developer/answer/9859455?hl=de),
[Behörden-Apps](https://support.google.com/googleplay/android-developer/answer/9514050?hl=de),
[Finanzfunktionen](https://support.google.com/googleplay/android-developer/answer/13849271?hl=de),
[Gesundheitsfunktionen](https://support.google.com/googleplay/android-developer/answer/14738291?hl=de).

## IARC: Inhaltseinstufung und Nutzerinteraktion

Der vollständige IARC-Fragebogen ist nur im Einreichungsportal des jeweiligen Stores verfügbar.
Die Angaben unten sind daher eine belegte Ausfüllhilfe, kein fertig beantworteter Fragebogen.
Den tatsächlichen Wortlaut und seine Erläuterungen verwenden; insbesondere Verweise,
Textbeschreibungen, Bilder und Geräusche nicht gleichsetzen.
[IARC-FAQ](https://www.globalratings.com/faq/),
[Googles Einstufungsverfahren](https://support.google.com/googleplay/android-developer/answer/9859655?hl=de).

| Frage / Themenbereich | Vorbereitete Antwort aus dem Code |
| --- | --- |
| Kontakt für IARC | `info@akribos.de`; Einstufungsnachrichten dort bearbeiten |
| App-Gruppe | Andere App-Typen, falls so angeboten: Hauptzweck Lesen/Nachschlagen, kein Spiel und keine primäre Social-/Dating-App |
| Online nachgeladene Inhalte | Ja: Bibeln, Kommentare, Lexika und persönliche/geteilte Inhalte werden vom Server geladen |
| Nutzerinteraktion / eigene Inhalte anderen zugänglich machen | Ja: Sammlungen mit Einladungen, Kommentaren, Antworten und Reaktionen; freigegebene Leselinks und lesbare veröffentlichte Notizen |
| Standort anderen Nutzern zeigen | Nein: keine entsprechende Funktion gefunden |
| Digitale Käufe, Glücksspiel oder Gewinne als App-Funktion | Nein: keine entsprechende Kauf-, Wett- oder Gewinnfunktion gefunden. Biblische Erwähnungen getrennt bewerten |
| Inhalte/Nutzer in der App melden | Im geprüften Client nicht vorhanden gefunden; keine Zusage, dass ein solcher Weg existiert |
| Andere Nutzer blockieren | Im geprüften Client nicht vorhanden gefunden; das Entfernen von Mitgliedern durch Sammlungseigentümer ersetzt keine allgemeine Blockierfunktion |
| Vollständige Vorabmoderation / Inhaltsfilter | Nicht belegt; keine entsprechende Zusage abgeben |

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

### Bestätigte Alterszielgruppe: ab 13 Jahren

Der Betreiber hat am 16. Oktober 2026 die Altersgruppen **13–15 Jahre, 16–17 Jahre und 18+**
ausdrücklich als Zielgruppe bestätigt. Diese drei Gruppen sind im Console-Formular auszuwählen;
die Speicherung dort ist hier noch nicht bestätigt. Unter 13-Jährige gehören nicht zur
beabsichtigten Zielgruppe. Die Alterszielgruppe bleibt von der automatisch ermittelten
Inhaltsfreigabe getrennt und ersetzt keine Prüfung der IARC- oder UGC-Anforderungen.
[Google zur Zielgruppe und Inhaltsfreigabe](https://support.google.com/googleplay/android-developer/answer/9859655?hl=de).

## Datenflüsse und Datensicherheit

Google bezieht die selbst kontrollierte Editor-WebView in die App-Angaben ein. Reine lokale
Verarbeitung zählt dort nicht als Übertragung. Ausschließlich internes Testen ist vom
Datensicherheitsformular ausgenommen; vor Closed/Open/Production sind die Angaben nötig.
Die folgende Zuordnung ist eine technische Arbeitsfassung aus dem Code, keine bereits
abgegebene Erklärung. [Google: Datensicherheit](https://support.google.com/googleplay/android-developer/answer/10787469?hl=de).

| Tatsächlicher Datenfluss | Console-Zuordnung zur Prüfung | Verwendung / Wahlmöglichkeit |
| --- | --- | --- |
| E-Mail-Adresse bei Registrierung, Anmeldung, Konto und Einladungen | Personenbezogene Daten → E-Mail-Adresse | Kontoverwaltung, App-Funktion, Sicherheit; Anmeldung ist für öffentliches Lesen optional |
| Anzeigename im Profil | Personenbezogene Daten → Name | Kontoverwaltung und sichtbarer Name bei Zusammenarbeit; freiwillige Eingabe |
| Konto-ID und Sitzungszuordnung | Personenbezogene Daten → Nutzer-IDs | Anmeldung, Besitzprüfung, persönliche Inhalte; bei Kontonutzung |
| Notizen, Ausarbeitungen, Titel, Tags, Markierungen, Sammlungen, Kommentare und Reaktionen | App-Aktivität → andere nutzergenerierte Inhalte bzw. andere Aktivitäten | Speichern und Zusammenarbeit; freiwillig angelegte Inhalte, kontogebunden |
| Suchbegriffe gehen an die Akribos-Suche | App-Aktivität → Suchverlauf in der App | Suchfunktion; freiwillige Suche. Nicht pauschal als ausschließlich lokal oder flüchtig deklarieren, solange Infrastruktur-Logs nicht geprüft sind |
| Ausgewählte Anlagen an Ausarbeitungen: Inhalt, Dateiname, Medientyp, Größe | Dateien und Dokumente; je nach tatsächlichem Inhalt zusätzlich Fotos/Videos und Audiodateien | Expliziter System-Dateiauswahldialog; freiwilliger Upload. Backend erlaubt beliebige Dateitypen bis zur Größenbegrenzung, kein Foto-/Audio-Ausschluss |
| Zufälliger `x-reader-browser-tab`-Wert pro App-Client wird übertragen | Geräte- oder andere IDs: technische App-Kennung prüfen | Funktionale Laufzeitkennung, keine Werbe-ID; im lokalen Reader-Modus kein Browser-Workspace. Header-/Proxy-Speicherung beim Betreiber prüfen |
| Verbindungs-IP, Anmelde-Ratelimits, langsame Requests mit Pfad/Dauer/Status | Technische Zugriffsdaten; ggf. Diagnosedaten/weitere Kennungen gemäß tatsächlich aktivem Betrieb | Betrieb und Missbrauchsschutz. Logs, Aufbewahrung und Zugriff beim Hosting/CDN bestätigen |
| Geistliche Notizen können Aussagen über Überzeugungen enthalten | Politische/religiöse Überzeugungen: **Einordnung durch Betreiber offen** | Keine Religions-Profilfelder gefunden. Nicht aus der App-Kategorie allein ableiten; Inhalt und Zweck freiwilliger Studiennotizen einbeziehen |

Für die Übertragung zwischen Store-App und Akribos gilt HTTPS; das Android-Manifest verbietet
Klartextverkehr. Die App verwendet keine Ende-zu-Ende-Verschlüsselung für Servernotizen.
Lokale Sitzungsdaten, Tabs und Entwürfe werden durch den sicheren Plattform-Speicher geschützt.
Das ist keine Aussage über Verschlüsselung oder Aufbewahrungsfristen der Server-Datenbank.

Weitergabe muss von Erfassung unterschieden werden: Der Code übermittelt Konto-E-Mails
serverseitig an Brevo, sofern dieser Mailer konfiguriert ist. Hosting/CDN/Mail-Auftragsverarbeiter
und ausdrücklich ausgelöstes Teilen sind bei der Console-Einordnung gesondert zu prüfen.
Keine pauschale Zusage „keine Datenweitergabe“ abgeben, bevor reale Empfänger und Verträge
bestätigt sind. Eigene Notizen werden nicht automatisch veröffentlicht; ausdrücklich geteilte
Inhalte können andere Nutzer oder Linkempfänger erreichen.

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

## Konto-Löschung: verifizierter Stand

Die App kann ein Konto über den E-Mail-Anmeldeablauf anlegen. Im aktuellen Quellstand
bietet der Konto-Bildschirm zusätzlich zu Profil, Passwort und Abmelden den Abschnitt
„Konto und Daten löschen“ mit „Löschung anfordern“. Der Button öffnet
`/datenschutz#konto-loeschen` am eingestellten Akribos-Server, in Produktion also
`https://akribos.de/datenschutz#konto-loeschen`. Dabei werden keine Konto-ID, Zugangsdaten
oder Sitzung in die URL aufgenommen. Fehler beim Öffnen werden mit der Zieladresse angezeigt.
Der Button startet einen Antrag über die Betreiberseite; er löscht kein Konto und meldet
nicht ab. Es wurde kein benutzerseitiger Konto-Löschendpunkt ergänzt.

Die zugehörige Web-Erweiterung mit diesem Anker und dem konkreten Ablauf ist in Vorbereitung;
ihre Veröffentlichung und der vollständige Weg wurden noch nicht live geprüft.
Der Betreiber hat am 16. Oktober 2026 eine Bearbeitung von Löschanträgen innerhalb von
**sieben Tagen** bestätigt. Das ist keine bestätigte Frist für das Auslaufen aller Backups
oder gesetzlich aufzubewahrender Daten. Der native Einstieg ist noch nicht im bereits
gebauten Bootstrap-Bundle `0.3.0+13` enthalten; dessen Quellcommit ist in
`docs/PLAY-STORE.md` dokumentiert.

Google verlangt bei Kontoerstellung einen gut auffindbaren Weg aus der App und eine externe
Ressource für Löschanträge. Eine deutlich beschriebene Support-E-Mail kann der externe Weg
sein; der vollständige Ablauf muss vor einer entsprechenden Console-Zusage geprüft sein.
[Google: Konto-Löschung](https://support.google.com/googleplay/android-developer/answer/13327111?hl=de).

Noch ergänzen und prüfen:

1. Den vorbereiteten öffentlichen Abschnitt mit App-/Betreibername, Antrag per
   `info@akribos.de`, Identitätsprüfung sowie Umfang und bestätigter Bearbeitungsfrist
   veröffentlichen und den Link aus einem neuen Release-Bundle testen.
2. Tatsächliche Entfernung von Konto, Inhalten, Einladungs-/Mitgliedschaftsbezügen, Anlagen und
   Dienstleisterdaten einschließlich dokumentierter Aufbewahrungs- und Backupausnahmen prüfen.

Textvorlage für den externen Löschweg, **noch nicht veröffentlicht**:

> Akribos-Konto und zugehörige Daten löschen
>
> Du kannst die Löschung deines Akribos-Kontos und der dazugehörigen persönlichen Daten
> unter info@akribos.de anfordern. Verwende möglichst die E-Mail-Adresse deines Kontos
> und den Betreff „Akribos-Konto löschen“. Wir prüfen die Zuordnung des Antrags, bevor
> wir Kontodaten löschen. Wir bearbeiten Löschanträge innerhalb von sieben Tagen.
> Sende uns dafür kein Passwort und keinen Anmeldecode.
>
> [BETREIBER ERGÄNZEN: betroffene Daten, Umgang mit geteilten Beiträgen sowie erforderliche
> Aufbewahrungs- und Backupausnahmen mit Fristen.]

Diese Platzhalter müssen vor Veröffentlichung entfernt und durch den bestätigten Ablauf
ersetzt werden. Keine fiktive Lösch-URL als fertige Console-Angabe eintragen.

## Ergänzung der Datenschutzerklärung: Textentwurf

Die aktuelle Seite beschreibt eine Website und stellt das Passwort als verpflichtend dar.
Für die App fehlen insbesondere die native lokale Speicherung, Entwürfe und der Editor.
Folgender Zusatz ist aus dem Code vorbereitet; der Betreiber muss die markierten Angaben
vor Veröffentlichung ergänzen und mit der bestehenden Erklärung abstimmen:

> Akribos-App für Android
>
> Die App verbindet sich mit akribos.de, um Bibeltexte, Nachschlagewerke und persönliche
> Inhalte zu laden. Bei diesen Verbindungen fallen technische Zugriffsdaten an. Öffentliche
> Texte können ohne Anmeldung gelesen werden. Für persönliche Funktionen verwenden wir
> die E-Mail-Adresse und die Kennung deines Akribos-Kontos. Die Anmeldung kann per
> E-Mail-Link bzw. Code erfolgen; für Konten mit eingerichtetem Passwort ist die
> Passwortanmeldung verfügbar. Passwörter werden auf dem Server als Hash gespeichert.
>
> Notizen, Ausarbeitungen, Markierungen und Sammlungen werden deinem Konto zugeordnet
> auf dem Server gespeichert. Anlagen werden nur nach deiner Dateiauswahl hochgeladen.
> Durch eine von dir veranlasste Freigabe können Inhalte anderen zugänglich werden.
> Die Bearbeitung von Dokumenten erfolgt in einer eingebetteten Seite von akribos.de
> und verwendet dieselbe Anmeldung. Der native Client und die eingebettete Editorseite
> laden kein Analyse- oder Werbeskript.
>
> Die App bewahrt die Sitzung, lokale Tabs und Lesestellen sowie noch nicht übertragene
> Dokumententwürfe im sicheren Speicher des Geräts auf, getrennt nach Server und Konto.
> Anzeigeeinstellungen werden ebenfalls lokal gespeichert. Für das Speichern oder Teilen
> erzeugte Exportdateien liegen vorübergehend im privaten App-Verzeichnis. Beim Teilen
> bestimmst du über das Systemmenü, an welche andere App oder welchen Empfänger die
> ausgewählten Inhalte gehen. Die Verbindung zu akribos.de wird mit HTTPS geschützt.
> Serverseitig gespeicherte Notizen sind dadurch nicht Ende-zu-Ende-verschlüsselt.
>
> Akribos wird bei Hetzner Cloud betrieben; für den Betrieb wird Coolify mit
> Standard-Logging verwendet. Konto-E-Mails verarbeitet der dafür eingesetzte Maildienst.
> [BETREIBER BESTÄTIGEN: tatsächliche CDN-/Mailanbieter, Verarbeitungsorte,
> Vertragsgrundlagen sowie konkrete Log-, Mail- und Backup-Aufbewahrung.]
> Löschanträge sind an info@akribos.de möglich und werden innerhalb von sieben Tagen
> bearbeitet. [BETREIBER ERGÄNZEN: Datenumfang, Aufbewahrungs-/Backupausnahmen und nach
> Veröffentlichung der Web-Erweiterung den geprüften Löschlink.] Das Entfernen der App
> oder ihrer lokalen Daten löscht nicht automatisch das serverseitige Akribos-Konto.

## Reviewzugang vorbereiten

Google muss auch angemeldete Bereiche prüfen können.
[Google: App für die Überprüfung vorbereiten](https://support.google.com/googleplay/android-developer/answer/9859455?hl=de).
Ein Google-Dienstkonto mit Play-Rechten ist **kein** Akribos-Prüfkonto. Der Betreiber hat
`stores@akribos.de` als Adresse für das Prüfkonto vorgesehen. Kontoexistenz und funktionsfähiger
Passwort-Login sind noch nicht nachgewiesen. Im Repository wurden keine Zugangsdaten gesucht
oder hinterlegt.

Ein dediziertes normales Akribos-Konto mit fest eingerichtetem Passwort verwenden;
keine Adminrolle, realen Privatnotizen oder nur kurz gültigen E-Mail-Codes. Es muss die
freizugebenden Funktionen mit synthetischen Beispielen erreichen. Zugangsdaten gehören
nur in das dafür vorgesehene geschützte Console-Feld, nicht in dieses Dokument.

Vorlage für „Any other instructions“ (Englisch, keine Zugangsdaten enthalten):

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

Vor Abgabe mit genau dem Release-Bundle und dem Prüfkonto testen; danach die Aussage
zum Passwortweg nur beibehalten, wenn er tatsächlich ohne externen Code funktioniert.

## Noch vom Betreiber zu bestätigen

- Identität/Entwicklername, Preis und veröffentlichte Länder. Die Zielgruppe ab 13 Jahren ist
  bestätigt; eine Inhaltsfreigabe stammt weiterhin aus dem ausgefüllten IARC-Fragebogen,
  nicht aus einer Annahme „Bibel = für alle“.
- Zusammenarbeit ist vorhanden: Einladungen, Kommentare, geteilte Sammlungen und
  veröffentlichbare Notizen. Diese Funktionen bei Fragen zu nutzergenerierten Inhalten
  wahrheitsgemäß angeben. Einen dedizierten Melde-/Blockierablauf für Missbrauch habe ich
  im geprüften Client nicht gefunden; Nutzungsregeln und Moderationsweg vor breiter
  Veröffentlichung konkret klären.
- Hetzner Cloud, Coolify-Standardlogs und die Bearbeitung von Löschanträgen innerhalb
  von sieben Tagen sind bestätigt. Konkrete Log-/Backup-/Mail-Aufbewahrung, weitere
  Dienstleister und die vollständige Löschung bleiben zu prüfen. Die vorbereitete
  Web-Erweiterung veröffentlichen und den Löschweg mit einem neuen App-Build prüfen.
- Das vorgesehene Reviewer-Konto `stores@akribos.de` einschließlich Passwort-Login und
  Zugriff auf die persönlichen Funktionen testen; bisher ist nur die Adresse festgelegt.

Keine dieser offenen Angaben wurde für den Betreiber erfunden oder automatisch abgeschickt.
