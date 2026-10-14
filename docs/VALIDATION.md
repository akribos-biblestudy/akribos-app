# Prüfstand 14. Oktober 2026

## Lokal bestätigt

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

Die Pixel-Testversion `0.1.0+1` verwendet `http://127.0.0.1:4176`, das per
`adb reverse tcp:4176 tcp:4176` zum lokalen Testserver weitergeleitet wird. Die APK liegt
lokal unter `artifacts/akribos-0.1.0-pixel-local-debug.apk` (nicht versioniert).
Nach einem USB-Neuverbinden muss die Weiterleitung gegebenenfalls erneut gesetzt werden.

Der Testserver verwendet ausschließlich eine separate E2E-Datenbank. Zusätzlich zum
minimalen Seed wurde die im Akribos-Repository vorhandene öffentliche Luther 1912 als
`APPDEMO_LUTH1912` importiert: 66 Bücher, 31.171 Verse. Bestehende Testressourcen bleiben
unverändert. Die vollständige Bibel lässt sich über die Ressourcenwahl öffnen.

## Noch offen

Keine vollständige Abnahme von Notizbearbeitung, System-Dateiauswahl und Teilen auf echten
Geräten. Kein iOS-Xcode-Build auf dieser Linux-Maschine, kein iPhone-/iPad- oder Boox-Test.
Die GitHub-Workflowdatei wurde angelegt, aber noch nicht auf einem Remote ausgeführt.
Release-Signierung, verifizierte HTTPS-App-Links, Store-Uploads und Backend-Deployment sind
nicht erfolgt. Die komplette vorhandene Akribos-Web-E2E-Suite wurde für diesen lokalen
Change nicht erneut ausgeführt; sie ist vor einem späteren Push/PR vorgeschrieben.
