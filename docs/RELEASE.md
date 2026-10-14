# Bauen und auf Geräten prüfen

Der aktuell tatsächlich ausgeführte Prüfstand steht in [VALIDATION.md](VALIDATION.md).

## Android

```sh
flutter pub get --enforce-lockfile
flutter build apk --debug
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

Die Debug-APK ist für lokale Tests signiert. Release-Signierung ist bewusst nicht mit einem
Debugschlüssel vorkonfiguriert. Für Verteilung über Google Play müssen ein eigener Upload-
Schlüssel, sichere CI-Secrets und die tatsächliche Play-Console-Anwendung eingerichtet werden.
Schlüssel und `key.properties` gehören nicht ins Repository. Versions-/Buildnummern können ohne
Quellcodeänderung über `--build-name` und `--build-number` gesetzt werden.

Der Server benötigt das App-Protokoll v1. Für einen lokalen Testserver über USB:

```sh
adb reverse tcp:4176 tcp:4176
flutter build apk --debug --target-platform android-arm64 \
  --dart-define=AKRIBOS_SERVER=http://127.0.0.1:4176
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

Diese lokale Variante verliert die Serververbindung, wenn USB-Weiterleitung oder Testserver
beendet werden. Sie ist nicht mit einer öffentlichen Serverbereitstellung gleichzusetzen.

## iOS

Auf macOS:

```sh
flutter pub get --enforce-lockfile
flutter build ios --debug --no-codesign
```

Für echte Geräte und TestFlight in Xcode das tatsächliche Apple-Team und ein passendes
Provisioning-Profil für `de.akribos.app` hinterlegen. Keychain-Entitlements sind bereits für
Debug/Profile/Release gesetzt. Die CI erstellt einen unsignierten Build; sie lädt nichts zu
App Store Connect hoch. Linux kann diese Schritte nicht verifizieren.

## App-Links

`akribos://open?path=%2FJoh3%2C16` öffnet eine konkrete Stelle. Nur lokale Pfade bzw. URLs des
konfigurierten Origins werden übernommen. Gewöhnliche HTTPS-Links öffnen sich erst nach
korrekter Domainzuordnung automatisch in der App. Dafür sind die echten Android-Zertifikats-
Fingerprints und die Apple-Team-ID in `assetlinks.json` bzw. `apple-app-site-association` nötig.
E-Mail-Code-Anmeldung funktioniert ohne diese automatische Linkzuordnung.

## Geräteabnahme

| Gerät/Situation | Prüfung |
| --- | --- |
| Android-Telefon | Start, Anmeldung/Neustart, Zurück, lange Texte, Tastatur, Dateiauswahl, Teilen, Rücksetzlinks |
| iPhone | Keychain-Sitzung, Login-Code, Tastatur/Safe Areas, System-Share, Link-Rückkehr |
| Android-Tablet/iPad | Mehrere Kacheln, Trenner, Querformat, Split View, Tab-Wechsel ohne Positionsverlust |
| Boox/E-Ink | Kontrast, Ghosting, Bildschirmblättern, Touch-Reaktion, Lesbarkeit von Markierungen |
| Barrierefreiheit | Große Systemschrift, Screenreader, Kontrast, Bedienung der Dialoge |
| Schlechte Verbindung | Sichtbare Fehler, Erhalt von Dokumententwürfen, erneutes Speichern, keine stillen Konfliktüberschreibungen |
| Mehrere Geräte | Arbeitsbereiche unabhängig öffnen, Lesepositionen folgen, Revisionkonflikte und Rechtewiderruf |

Automatisierte Tests decken Protokoll-/Cookiegrenzen, Gerätegrößen und zentrale Arbeitsabläufe
ab. Sie ersetzen weder die komplette Geräteabnahme noch die Freigabe durch Apple/Google.

## Reproduzierbare Ansichten

Die PNG-Dateien unter `docs/screenshots/` stammen aus dem Flutter-Widget-Test mit anonymen
Server-Seed-Daten (Johannes 3 enthält dort absichtlich nur zwei Testverse). Sie dokumentieren
die native Oberfläche, keinen vollständigen Bibelbestand. Optional unter Linux mit
`/usr/share/fonts/noto/NotoSans-Regular.ttf`:

```sh
flutter test test/app_shell_test.dart --dart-define=AKRIBOS_SCREENSHOTS=true
```
