# Prüfstand 14. Oktober 2026

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
Release-Signierung, verifizierte HTTPS-App-Links und Store-Uploads sind nicht erfolgt.
Vollständige lokale Testläufe sind auf Wunsch keine Release-Voraussetzung mehr; gezielte
Prüfungen laufen lokal, umfassende Unit-/E2E-Prüfungen in der bestehenden CI.
