# Akribos: Inhalte für Google Play

Stand: 16. Oktober 2026. Grundlage sind der aktuelle lokale App-Code und das zugehörige
Web-Repository, einschließlich der neuen Einstellungen und des kompakten Versmenüs.
Die Texte sind vorbereitet, aber weder hochgeladen noch in der Console bestätigt.
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
| Kategorie | Vorschlag: Bücher & Nachschlagewerke; vom Betreiber bestätigen |
| Enthält Werbung | Vorschlag: Nein. Im untersuchten App-Code, in den Abhängigkeiten und in der isolierten Editorseite keine Werbeeinbindung gefunden |
| App-Zugriff | Einige Funktionen erfordern Anmeldung; Prüfkonto für Notizen, Markierungen, Einstellungen und Sammlungen erforderlich |
| Preis, Länder, Zielalter | **Betreiberentscheidung offen.** Nicht aus technischer Funktionsfähigkeit ableiten |
| Entwickleranzeige / rechtlicher Kontoinhaber | **Mit der tatsächlich verifizierten Play-Identität abgleichen.** Öffentliches Impressum nennt Mirko Hecky |
| Telefonnummer | Nicht im untersuchten öffentlichen Impressum vorhanden; keine Nummer erfunden |

Support-Adresse, Mirko Hecky und die Anschrift Hosleite 13, 95478 Kemnath, Deutschland,
stehen im versionierten Impressum. Der öffentliche Abruf von Impressum und Datenschutzseite
lieferte am 16. Oktober 2026 HTTP 200. Die von Cloudflare im öffentlichen HTML kodierte
E-Mail-Adresse wurde als `info@akribos.de` bestätigt. Diese Angaben ersetzen keine Prüfung
der separaten Play-Konto-/Organisationsdaten.
[Öffentliches Impressum](https://akribos.de/impressum),
[öffentliche Datenschutzerklärung](https://akribos.de/datenschutz).

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
  Hostinganbieter, Cloudflare-Vertrag/Konfiguration, Mail-Aufbewahrung, Datenbank-Backups
  und mögliche GeoIP-Auswertung sind **nicht aus dem App-Code abschließend feststellbar**.
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

Die App kann ein Konto über den E-Mail-Anmeldeablauf anlegen. Ihr Konto-Bildschirm bietet
aktuell Profil, Passwort und Abmelden, aber keinen sichtbaren Löschantrag. Die öffentliche
Datenschutzseite nennt einen formlosen Antrag per E-Mail; der Abschnitt hat keinen eigenen
Linkanker und beschreibt keine konkrete Bearbeitungs-/Backupfrist. Es wurde kein
benutzerseitiger Konto-Löschendpunkt gefunden. „Abmelden“ löscht kein Serverkonto.

Google verlangt bei Kontoerstellung einen gut auffindbaren Weg aus der App und eine externe
Ressource für Löschanträge. Eine deutlich beschriebene Support-E-Mail kann der externe Weg
sein; das ist keine Zusage, dass der heutige allgemeine Datenschutzlink bereits ausreicht.
[Google: Konto-Löschung](https://support.google.com/googleplay/android-developer/answer/13327111?hl=de).

Vor einer entsprechenden Console-Zusage konkret ergänzen und prüfen:

1. Im Konto einen klar benannten Einstieg „Konto und Daten löschen“ bereitstellen, der einen
   Löschantrag ermöglicht oder die dafür vorgesehene Webressource öffnet.
2. Eine öffentliche Seite oder einen prominenten verlinkbaren Abschnitt mit App-/Betreibername,
   Antrag per `info@akribos.de`, Identitätsprüfung sowie Umfang und Fristen veröffentlichen.
3. Tatsächliche Entfernung von Konto, Inhalten, Einladungs-/Mitgliedschaftsbezügen, Anlagen und
   Dienstleisterdaten einschließlich dokumentierter Ausnahmen überprüfen.

Textvorlage für den externen Löschweg, **noch nicht veröffentlicht**:

> Akribos-Konto und zugehörige Daten löschen
>
> Du kannst die Löschung deines Akribos-Kontos und der dazugehörigen persönlichen Daten
> unter info@akribos.de anfordern. Verwende möglichst die E-Mail-Adresse deines Kontos
> und den Betreff „Akribos-Konto löschen“. Wir prüfen die Zuordnung des Antrags, bevor
> wir Kontodaten löschen. Sende uns dafür kein Passwort und keinen Anmeldecode.
>
> [BETREIBER ERGÄNZEN: betroffene Daten, Umgang mit geteilten Beiträgen, Frist für die
> Bearbeitung sowie erforderliche Aufbewahrungs- und Backupausnahmen mit Fristen.]

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
> Konto-E-Mails verarbeitet der dafür eingesetzte Maildienst. [BETREIBER BESTÄTIGEN:
> tatsächliche Hosting-/CDN-/Mailanbieter, Verarbeitungsorte, Vertragsgrundlagen und Fristen.]
> Löschanträge sind an info@akribos.de möglich. [BETREIBER ERGÄNZEN: bestätigter Ablauf,
> Fristen und veröffentlichter Löschlink.] Das Entfernen der App oder ihrer lokalen Daten
> löscht nicht automatisch das serverseitige Akribos-Konto.

## Reviewzugang vorbereiten

Google muss auch angemeldete Bereiche prüfen können.
[Google: App für die Überprüfung vorbereiten](https://support.google.com/googleplay/android-developer/answer/9859455?hl=de).
Ein Google-Dienstkonto mit Play-Rechten ist **kein** Akribos-Prüfkonto. Im Repository wurden
keine Zugangsdaten gesucht oder hinterlegt; ein funktionsfähiger Reviewer-Login ist hier
noch nicht nachgewiesen.

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

- Identität/Entwicklername, Preis, veröffentlichte Länder und Zielalter. Eine Altersfreigabe
  stammt aus dem ausgefüllten IARC-Fragebogen, nicht aus einer Annahme „Bibel = für alle“.
- Zusammenarbeit ist vorhanden: Einladungen, Kommentare, geteilte Sammlungen und
  veröffentlichbare Notizen. Diese Funktionen bei Fragen zu nutzergenerierten Inhalten
  wahrheitsgemäß angeben. Einen dedizierten Melde-/Blockierablauf für Missbrauch habe ich
  im geprüften Client nicht gefunden; Nutzungsregeln und Moderationsweg vor breiter
  Veröffentlichung konkret klären.
- Reale Infrastruktur-/Maildaten, Aufbewahrung, Löschablauf und Reviewer-Konto, wie oben
  getrennt vom verifizierten Code dargestellt.

Keine dieser offenen Angaben wurde für den Betreiber erfunden oder automatisch abgeschickt.
