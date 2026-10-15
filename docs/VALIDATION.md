# Prüfstand 15. Oktober 2026

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
