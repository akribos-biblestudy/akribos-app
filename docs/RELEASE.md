# Bauen und auf Geräten prüfen

Der aktuell tatsächlich ausgeführte Prüfstand steht in [VALIDATION.md](VALIDATION.md).

## Android für akribos.de

Der normale Gerätebuild verwendet direkt `https://akribos.de`. Anmeldung und private
Funktionen laufen über das gewöhnliche Akribos-Konto; es muss kein API-Schlüssel erstellt
oder eingetragen werden. Nach der Installation benötigt die App nur eine Internetverbindung.
USB, ADB und ein lokaler Testserver sind für den Betrieb nicht erforderlich.

Voraussetzungen: Flutter 3.47.0 / Dart 3.13.0, Android SDK und JDK 17 oder eine passende
Android-Studio-JBR. Aus dem Repository:

```sh
./scripts/build-android-production.sh
```

Die Prüfsumme wird aus dem Artefaktverzeichnis geprüft:

```sh
(cd artifacts && sha256sum -c akribos-0.1.0-akribos-de-debug.apk.sha256)
```

Das Skript akzeptiert keine Parameter und legt diese Werte ausdrücklich fest:

| Einstellung | Wert |
| --- | --- |
| Server | `https://akribos.de` |
| Anwendung | `de.akribos.app` |
| Version / Android-Versionscode | `0.1.0` / `2` |
| Architektur | `android-arm64` |
| Build und Signatur | Debug-Build, automatische Android-Debug-Signatur |
| APK | `artifacts/akribos-0.1.0-akribos-de-debug.apk` |

Es lädt die festgeschriebenen Abhängigkeiten mit `--enforce-lockfile`, baut die APK und
schreibt eine SHA-256-Prüfsumme daneben. Es installiert nichts und verändert keinen Server.
Die gleiche Buildkonfiguration ist reproduzierbar; identische APK-Bytes auf anderen Rechnern
sind wegen lokaler Debug-Zertifikate und Werkzeug-Metadaten nicht zugesagt.

Die APK kann auf dem Pixel direkt als Datei geöffnet und installiert werden. Für Updates
muss die Android-Signatur zur vorhandenen Installation passen. Auf demselben Buildrechner
bleibt die automatische Debug-Signatur normalerweise erhalten. Das Buildskript benötigt
keine privaten Store-Schlüssel und keine Anmeldung bei Google Play.

Der App-Server muss das App-Protokoll v1 anbieten; die Bereitstellung wird unabhängig vom
APK-Build geprüft. Ein erfolgreicher APK-Build belegt noch keine Live-Server- oder Geräteabnahme.

## Store-Verteilung

Die direkte APK verwendet den produktiven Server, bleibt aber ein Debug-Build. Für Google Play
müssen eine eigene Upload-Signatur, sichere CI-Secrets und die tatsächliche Play-Console-Anwendung
eingerichtet werden. Release-Signierung ist bewusst nicht mit einem Debugschlüssel vorkonfiguriert.
Schlüssel und `key.properties` gehören nicht ins Repository. Für spätere Veröffentlichungen
können Versions-/Buildnummern über `--build-name` und `--build-number` gesetzt werden; das obige
Skript hält den konkreten Pixel-Build `0.1.0+2` fest.

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
