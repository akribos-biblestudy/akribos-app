# Native App API (Version 1)

Dieses Repository enthält den Flutter-Client für Android und iOS. Die Implementierung
des Protokolls liegt im benachbarten Server-Repository `../akribos`.
Die normale App und `scripts/build-android-production.sh` verwenden direkt
`https://akribos.de` über HTTPS. Auf dem Gerät werden weder ein API-Schlüssel noch eine
Entwicklungsverbindung eingerichtet. Die App verwendet die normalen, widerrufbaren
Akribos-Sitzungen: öffentlich lesen, für persönliche Funktionen per E-Mail-Code oder
Passwort anmelden. Die Kontoverwaltung vorhandener API-Schlüssel ist eine separate
Funktion für externe Integrationen und keine Voraussetzung für die App.
Es gibt keine zusätzliche globale Berechtigung und keine Änderung an `resources.api_enabled`.
Leserechte entsprechen den internen Reader-Endpunkten. USB, ADB oder ein lokaler Server
sind im normalen Betrieb nicht beteiligt.

## Öffentlicher Zugriff auf akribos.de

Die öffentliche Produktionsbasis der App-API ist **`https://akribos.de/api/app`**. In der Flutter-App
wird als Server **`https://akribos.de`** verwendet. Öffentliche Bibeltexte, verfügbare Werke, Suche und
öffentliche Hilfeseiten funktionieren auf Protokollebene ohne Registrierung, Sitzungscookie
oder API-Schlüssel. Die native Hilfe zeigt derzeit einen lokalen Platzhalter und lädt die
Webhilfe nicht. `x-akribos-app: 1` bezeichnet lediglich die Protokollversion und ist kein Geheimnis. Die aktuelle
App setzt zusätzlich `x-akribos-reader-mode: local`, um Readerzustand ausschließlich auf dem
Gerät zu verwalten.

Diese Anfragen benötigen weder `Authorization` noch einen zuvor angelegten Schlüssel:

```sh
curl --fail-with-body --silent --show-error \
  -H 'x-akribos-app: 1' \
  -H 'x-akribos-reader-mode: local' \
  -H 'Origin: https://akribos.de' \
  'https://akribos.de/api/app/bootstrap'

curl --fail-with-body --silent --show-error --get \
  -H 'x-akribos-app: 1' \
  -H 'x-akribos-reader-mode: local' \
  -H 'Origin: https://akribos.de' \
  --data-urlencode 'path=/Joh1' \
  'https://akribos.de/api/app/page'
```

Der Bootstrap liefert `type: "success"`, `data.protocolVersion: 1` und bei Gästen `data.user: null`.
Eine Lesestelle kann zunächst einen kanonischen `redirect`-Umschlag liefern; dessen lokalen
`location`-Wert lädt der Client erneut über `/api/app/page?path=…`.

Persönliche Notizen, Sammlungen und Markierungen benötigen die normale
Kontoanmeldung mit Passwort oder E-Mail-Code und den daraus erzeugten Sitzungscookie. Ohne Sitzung
antworten geschützte App-Seiten mit dem lokalen Anmelde-Redirect; geschützte JSON-Endpunkte wie
`/api/documents` liefern HTTP 401. Weder der Versions-/Origin-Header noch ein mitgesendeter API-Key
erteilt Kontorechte. Private Ressourcen bleiben zusätzlich an die aktuellen Kontofreigaben gebunden.
Die getrennte Schnittstelle `/api/v1` und deren API-Key-/Lizenzregeln bleiben unverändert.

| Endpunkt | Aufgabe |
| --- | --- |
| `GET /api/reader/resources/{resource}/navigation` | Für das aktuelle lesbare Werk tatsächlich vorhandene Bücher und Kapitel; prüft die Reader-Leserechte und liefert `books: [{book, chapters}]` |
| `GET /api/app/offline/resources` und `GET /api/app/offline/resources/{id}` | Lizenzierte und für das aktuelle Konto lesbare Werke abrufen. Version 1 umfasst Bibeln, Kommentare und Parallelstellen. Pakete enthalten keine persönlichen Markierungen oder Notizen; ihre serialisierte UTF-8-JSON-Größe ist auf 128 MiB begrenzt (ältere Server: 32 MiB). |
| `GET /api/app/offline/v2/lexicons` und `GET /api/app/offline/v2/lexicons/{id}` | Separater Version-2-Katalog und Artikelpakete für offline freigegebene Lexika. Ein fehlender oder fehlgeschlagener Katalog bestätigt keine Rechte für gespeicherte Lexika. |
| `GET /api/app/bootstrap` | Layout, sichere Sitzungsidentität, Werke, 66 Bücher, Einstellungen und Nutzernavigation |
| `GET /api/app/page?path=/notes%3Fkind%3Dnote` | Notizbibliothek als JSON laden; der innere Pfad einschließlich Query wird URL-kodiert |
| `POST /api/app/action?path=/notes&action=create` | Eine ausdrücklich freigegebene bestehende Formularaktion ausführen |

Die App prüft beim Wiederverbinden beide Offline-Kataloge getrennt. Ein bereits bestätigter
v1-Entzug entfernt das betreffende Paket auch dann, wenn der anschließende v2-Abruf scheitert.
Sind gespeicherte Lexika nicht prüfbar, bleibt ihr verschlüsseltes Paket erhalten, aber die
Offline-Identität wird nicht freigegeben. Ältere Server ohne v2-Endpunkt funktionieren für
v1-Pakete, solange keine v2-Pakete gespeichert sind. Offline bleiben Aktionen schreibgeschützt;
Lexika bieten lokale Strong- und Textsuche. Ohne Verbindung lässt sich ein späterer Entzug
erst nach dem nächsten erfolgreichen Rechteabgleich erkennen.

Die lokale Lexikonsuche normalisiert Strong-Eingaben einschließlich führender Nullen wie der
Server. Für Textsuche werden häufige lateinische und griechische Akzente sowie kombinierende
Zeichen entfernt; dies ist eine Näherung und bildet PostgreSQLs konfigurierbares `unaccent`
nicht vollständig nach. Die lokale Suche durchsucht zusätzlich Artikeltexte und liefert
Teilworttreffer, während der Online-Lexikonabruf Lemma und Umschrift nach Präfix abgleicht.

Alle Anfragen tragen `x-akribos-app: 1`. Native Clients senden den tatsächlichen Server-Origin,
insbesondere für Multipart, damit SvelteKits bestehender CSRF-Schutz erhalten bleibt. Cookies werden
nach Domain/Pfad/Secure/Expiry behandelt; eine fremde Origin darf nie Sitzungscookies erhalten.
Der Header ist keine Authentifizierung. API-Schlüssel werden nicht in Sitzungskonten umgedeutet.

```json
{ "fields": { "kind": "note", "title": "Meine Notiz", "tagPaths": ["Studium/Johannes"] } }
```

Formularwerte sind Strings oder Stringlisten. Dateiübertragungen verwenden `multipart/form-data`
mit den ursprünglichen Feldnamen. Die Allowlist unterstützt weiterhin bestehende persönliche
Import- und Vorlagenaktionen sowie die Boardspaltenverwaltung; die aktuelle App-Oberfläche
bietet diese Abläufe nicht an. Anhänge und Exporte bleiben mobil verfügbar. Private Importe
prüfen serverseitig die Sitzung vor dem Einlesen des Anfragekörpers; Größenbegrenzungen werden
vor der Formularauswertung geprüft.
Antworten verwenden ein stabiles JSON-Format:

```json
{ "type": "success", "status": 200, "data": {} }
{ "type": "failure", "status": 409, "data": { "error": "conflict" } }
{ "type": "redirect", "status": 303, "location": "/notes/UUID" }
```

Ein Redirect-Umschlag hat HTTP 200; seine ursprüngliche Redirect-Art steht in `status`. Clients
öffnen `location` ausdrücklich und wiederholen niemals den vorigen POST. Fehler behalten den
passenden HTTP-Status. Datumswerte werden als ISO-Zeichenfolgen serialisiert. Erfolgreiche Seiten
enthalten `_path` mit der angefragten kanonischen Route einschließlich Query.

## Gemeinsame Regeln

`src/lib/server/app/routes.ts` ist die geschlossene Liste von Routen und Aktionsnamen. Der Adapter
übernimmt ursprüngliche URL, Parameter, Route und Formularfelder; er erfindet keine zweite Fassung
der Geschäftsregeln. Neue Serveraktionen brauchen eine bewusste Ergänzung des Protokolls und der
nativen Oberfläche, wenn die Aktion zum mobilen Umfang gehört. Die Allowlist allein beschreibt
keine Funktionszusage der App; deren Umfang steht in [FEATURES.md](FEATURES.md). Änderungen an
gelieferten Feldern müssen mit dem Client abgestimmt werden.
Verwaltung, Ressourcenimport und reine Adminaktionen sind ausgeschlossen, auch wenn das
angemeldete Konto Administrator ist. Die Hilfe verwendet die normale Nutzerzielgruppe. Bestehende
Eigentums- und Mitgliedschaftsprüfungen gelten weiterhin, auch für Administratoren.

Der lokale Reader-Modus setzt das gültige App-Protokoll und den zusätzlichen Header
`x-akribos-reader-mode: local` voraus. Der Adapter klont den Request-Kontext mit `localReader`.
Bootstrap und Readerauflösung verwenden nur aktuell lesbare Ressourcen, ohne die aktive
Browser-/Sessionauswahl, gespeicherte Workspaces oder Legacy-Workspacefelder zu übernehmen.
Sie legen keinen Standard-Workspace an und schreiben keine Workspace-/Positionscookies.
Die Antwort enthält keine benannten Arbeitsbereiche und keine aktiven Workspaceversionen.
Sitzung, Rolle, Schrift-/Darstellungspräferenzen und Ressourcenfreigaben bleiben wirksam.

Die App speichert Tabs, Stellen, Suchen und Filter verschlüsselt pro Server und Konto auf dem
Gerät; Gäste haben einen eigenen Stand. Sie ruft weder Workspace-View noch Follow auf. Für
serverseitig berechnete Readeraktionen ist der lokale Modus immer detached, auch bei fehlendem
Clientflag oder mitgesendeten Workspaceversionen. Diese Aktionen liefern den neuen `readerState`
und `path` sowie `saved:false, reason:detached`, ohne Workspace-Datenbankzugriff oder Persistierung.
Die benannten `/workspaces/[id]`-Seiten/-Aktionen liefern in diesem Modus 404; die gemeinsamen
`/api/reader/workspaces`-REST-Handler lehnen lokale Anfragen mit 403 ab. Gästen fehlt weiterhin
die Sitzung (401). Web und ältere Clients ohne Opt-in behalten den bestehenden Workspacevertrag.

Dokumentänderungen benötigen unverändert die positive aktuelle `revision`. Der Client
serialisiert Speichern, erhält Konfliktentwürfe und wartet vor Navigation auf ausstehende
Änderungen. Ein GET konsumiert keinen Anmelde- oder Einladungstoken.

Die Reader-Mehrfachauswahl sendet Markierungs- und Sammlungsaktionen einzeln pro gewähltem
Vers; in einer Übersetzung zusammen gedruckte Versblöcke werden für Sammlungen in ihre
einzelnen Versnummern zerlegt. Eine neue Sammlung liefert beim ersten `addToList` ihre ID, die für die weiteren Verse
verwendet wird. Eine Notiz entsteht über `/notes` `create` mit `readerSidecar=1` und der ersten
Stelle; weitere, auch nicht zusammenhängende Stellen folgen einzeln über `/notes/[id]`
`addPassage` mit der jeweils bestätigten Revision. Bei einem Fehler stoppt die Folge ohne
automatische Wiederholung; bestätigte Stellen und eine bereits angelegte Notiz bleiben erhalten.

Für die Code-Anmeldung wird nur der native Challenge-Cookie umbenannt: `app-email-login`, HttpOnly,
Pfad `/api/app`. Die bestehende Anmeldelogik sieht ihn als `email-login`. Webanmeldung und native
Anmeldung beeinflussen ihre Challenge-Cookies nicht gegenseitig. Der Sitzungscookie bleibt derselbe.

Jede Protokollantwort setzt `private, no-store`, `Vary: Cookie` und `noindex, nofollow`. Es gibt kein
offenes CORS, keinen frei wählbaren Upstream und keine Umgehung der öffentlichen API-Lizenzgrenze.

Die native Textdarstellung unter Mehr → Einstellungen („Versweise“/„Fließtext“ im Blocksatz)
ist eine lokale Einstellung ohne
Serveraktion oder Änderung des geteilten Reader-URL-Vertrags. Fehlendes `versePerLine` in
älteren Geräteständen bedeutet „Fließtext“; ausdrücklich gespeicherte Entscheidungen bleiben erhalten.

Die optionale Tablet-Notizenspalte lädt eigene Notiz-Zusammenfassungen über den vorhandenen
`/api/documents?kind=note&passage=Joh3`-Endpunkt. Der Kapitelbezug ist abschaltbar; eine
Übersetzung wird nicht erzwungen. Aktivierung und Seitenwechsel bleiben im lokalen
`companion`-Snapshot, außerhalb der Reader-URL. Alte Kommentar-Ressourcenpräferenzen werden
ignoriert, ohne gewöhnliche Kommentar-Tabs zu entfernen. Notiz-Scrolls schreiben keine
Bibel-/Tabpositionen. Öffnen verwendet `/notes/[id]`, Anlegen die vorhandene `/notes`-Action
`create` mit `kind=note` und Stellenanker; Bearbeiten bleibt im gemeinsamen WebView-Editor.
Verschieben von Tabs ändert nur deren lokalen URL-Snapshot; es gibt dafür keine Serveraktion.

Die Notizbibliothek sendet den Kapitelbezug als expliziten Bereich, etwa
`/notes?kind=note&passage=Joh3%2C1-999`. Das Kapitel stammt nach dem Reader-Flush aus der
sichtbaren Lesestelle. Die Obergrenze von Vers 999 deckt alle Verszählungen ab und bleibt
auf die Serveranfrage beschränkt. Die Bibliothek filtert übersetzungsübergreifend vor der
Paginierung über Stellenanker und indizierte Textverweise. „Aktuelles Kapitel“ schaltet
den automatischen `passage`-Parameter ab. Manuelle Stellenfilter bleiben verfügbar.

## Bestehende JSON- und Binärschnittstellen

Kapitel, Suche, Strong und Dokument-Autosave verwenden weiterhin `/api/reader/*`, `/api/strong/*`
und `/api/documents/*`. Workspace-Verwaltung/-View/-Follow bleiben für Web und ältere Clients
bestehen, werden von der aktuellen App aber nicht verwendet. Datei-Exporte und Anhänge behalten ihre
bisherigen Adressen. Backupverwaltung und
Ressourcenimport bleiben ausschließlich Funktionen der Webverwaltung.

Beim Öffnen übernimmt die Hauptnavigation „Suche“ das aktuell gewählte Reader-Werk samt Titel.
Nach einem Werkwechsel wird ein vorhandener Begriff erneut gesucht und Buchfilter/Seite werden
zurückgesetzt; beim selben Werk bleibt der Suchstand erhalten. Bibel-, Kommentar- und
Parallelstellensuche verwenden `/api/reader/search?resource=ID&q=…`. Lexika verwenden
`GET /api/reader/lookup?resource=ID&q=…`: eine genaue Strong-Nummer oder eine Lemma-/Umschrift-
Präfixsuche mit bevorzugter exakter Schreibweise liefert einen Lexikoneintrag. Leserechte werden
auch dort für jede Anfrage geprüft. Die lokale Tab-Suche bleibt im Tabmenü.

## Prüfung und Betrieb

`src/lib/server/app/adapter.spec.ts` prüft Allowlist, Origins, Adminschutz, Cookie-Übersetzung,
Antworten und Formulargrenzen. `src/lib/server/app/local-reader.spec.ts` prüft den lokalen Modus
über die echten Adapter-, Layout- und Readerfunktionen mit simulierten Repositories: keine
Workspaceinitialisierung, keine Persistierung und gesperrte Named-Workspace-Endpunkte.
`e2e/app-api.e2e.ts` prüft gegen eine eigene Datenbank echte
Anmeldung, Rollen, private Dokumente, Erstellen, Speichern, Konflikte, Multipart und Abmeldung.
Zusätzlich gelten die vorhandenen Authentifizierungs- und Ressourcenberechtigungstests.

Die Endpunkte wurden am 14. Oktober 2026 auf akribos.de veröffentlicht und ohne
Anmeldung/API-Schlüssel live geprüft; siehe [VALIDATION.md](VALIDATION.md).
Der lokale Reader-Modus muss vor der aktuellen App-Version auf dem Server bereitgestellt sein.
Ältere Server mit Protokoll v1 kennen den neuen Header noch nicht und können weiterhin einen
benannten Standard-Workspace initialisieren. Ein Server ohne App-Protokoll wird mit einem
entsprechenden Fehler gemeldet.
APK-Build und Serverbereitstellung sind getrennte Schritte; das Buildskript führt kein Deployment
und keine Store-Veröffentlichung aus. Die direkt installierbare Android-APK verwendet die
bereits vorhandene lokale Android-Debug-Signatur mit geprüftem Fingerprint. Android-App-Links
werden über Manifest und Domainzuordnung vorbereitet; Veröffentlichung und Geräteverifikation
bleiben getrennte Prüfschritte. Vorerst wird nur Android veröffentlicht. iOS-Signierung und
App-Links folgen nach Bestätigung der laufenden Apple-Organisationsanmeldung, siehe
[RELEASE.md](RELEASE.md). Anmeldung per E-Mail-Code oder Passwort benötigt keine verifizierten
App-Links.


## Eingebetteter Dokumenteditor

`GET /app/editor/[id]` ist eine authentifizierte HTML-Seite desselben Origins für die
System-WebView, kein App-JSON-Endpunkt. Die App überträgt den bestehenden HttpOnly-
Sessioncookie nativ. Dokumentbesitz und Revisionen bleiben serverseitig geprüft.
Der gemeinsame Webeditor speichert über den vorhandenen `/api/documents/[id]`-PATCH.
Die Flutter-Bridge besitzt keine beliebigen HTTP-/JavaScript-Kommandos. Das genaue
versionierte Protokoll steht in `../akribos/docs/native-app-api.md`.

Reader-Workspace-Auflösung, Browser-Tab-Initialisierung, Analytics und Webnavigation
sind für diese Route ausgeschaltet. Theme/Schriftgröße/E-Ink sind reine Anzeigeparameter.
Native Navigation wartet auf Flush und Entwurfssicherung; Metadaten-/Anlagenänderungen
reservieren zuvor die Web-Speicherqueue und geben die neue Revision zurück.
