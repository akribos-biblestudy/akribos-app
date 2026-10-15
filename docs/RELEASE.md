# Bauen und auf Geräten prüfen

Der aktuell tatsächlich ausgeführte Prüfstand steht in [VALIDATION.md](VALIDATION.md).

## Android für akribos.de

Der direkte Gerätebuild verwendet `https://akribos.de`. Anmeldung und private Funktionen
laufen über das gewöhnliche Akribos-Konto, ohne API-Schlüssel. Nach der Installation braucht
die App nur Internet; USB, ADB und ein lokaler Testserver sind nicht erforderlich.

Voraussetzungen: Flutter 3.47.0 / Dart 3.13.0, Android SDK mit aktuellen Build Tools
(`apksigner`, `zipalign` mit `-P 16`, `aapt2`), ein zur lokalen Gradle-Version passendes JDK
und der **bereits vorhandene** `~/.android/debug.keystore` des bisherigen Buildrechners.
Flutter kann ein separat konfiguriertes JDK verwenden; die bereits funktionierende lokale
JDK-Konfiguration beibehalten. Das Skript benötigt Bash und GNU `sha256sum`/`sort`.

```sh
./scripts/build-android-production.sh
```

Das Skript akzeptiert keine Parameter und legt diese Werte fest:

| Einstellung | Wert |
| --- | --- |
| Server | `https://akribos.de` |
| Anwendung | `de.akribos.app` |
| Version / Android-Versionscode | `0.2.2` / `5` |
| Architektur | `android-arm64` |
| Laufzeit | Optimierter Flutter-Release-Build mit AOT, ohne Debugger |
| Signatur | Vorhandener lokaler Android-Debugschlüssel; identisch mit Build 2 |
| APK | `artifacts/akribos-0.2.2-akribos-de-release.apk` |

`--release` ist für aussagekräftige Bedien- und Leistungstests erforderlich. Die lokale
Debug-Signatur beeinflusst den Kompilierungsmodus nicht: Diese APK enthält Release-Code.
Gradle bleibt für Release-Artefakte ohne Signaturkonfiguration. Das Skript lädt die
festgeschriebenen Abhängigkeiten, baut zunächst die unsigned Release-APK, prüft ihr
16-KiB-Zipalignment und korrigiert es bei Bedarf **vor** dem Signieren. Danach signiert
`apksigner` mit dem vorhandenen Schlüssel und prüft Signatur, Alignment, Paketname,
Version, ARM64 und das Fehlen des Debuggable-Flags.

Der öffentliche SHA-256-Zertifikatfingerprint wurde gegen die ausgelieferte Build-2-APK
geprüft und ist im Skript festgehalten:

```text
80a5790ab68d738a770fb82a7c0326efad5929d4d63082383c06dc72c2145ccb
```

Ein fehlender oder abweichender Schlüssel führt zum Abbruch. Das Skript erzeugt keinen
Schlüssel, kopiert keine Schlüsseldatei und richtet keine Store-Signatur ein. Die Standard-
Debug-Keystore-Zugangsdaten sind öffentlich; dieser Schlüssel ist keine Store-Identität.
Das APK, eine SHA-256-Prüfsumme und ein Bericht des öffentlichen Signaturzertifikats liegen
im ignorierten Verzeichnis `artifacts/`. Die abschließende Prüfsumme lässt sich so prüfen:

```sh
(cd artifacts && sha256sum -c akribos-0.2.2-akribos-de-release.apk.sha256)
```

Die APK wird als Update der vorhandenen App installiert; **nicht vorher deinstallieren
oder App-Daten löschen**. Gleiche Anwendungs-ID, derselbe Signer und Versionscode 5 erhalten
die Android-App-Daten beim Update von Build 2. Die Installation erfolgt ausschließlich als Paketupdate:

```sh
adb -s <Geraeteseriennummer> install -r artifacts/akribos-0.2.2-akribos-de-release.apk
```

Kein `adb uninstall`, `pm clear` oder automatischer Fallback durch Löschen von App-Daten.
Bei abweichendem Signer muss der Vorgang abbrechen. Die tatsächliche Geräteabnahme einschließlich
Sitzungserhalt bleibt separat zu prüfen. Das Skript installiert nichts und verändert keinen
Server; ein angeschlossenes Gerät ist zum Bauen nicht nötig. Identische APK-Bytes auf anderen
Rechnern sind wegen Werkzeug-Metadaten nicht zugesagt.

Referenzen: [Flutter Android-Release](https://docs.flutter.dev/deployment/android),
[Android apksigner](https://developer.android.com/tools/apksigner),
[Android zipalign](https://developer.android.com/tools/zipalign).

## Store-Verteilung

Die direkte APK verwendet produktiven Server und optimierten Release-Code, ist jedoch
weiter mit dem bisherigen lokalen Debugschlüssel signiert. Für Google Play sind eine eigene
Upload-Signatur, sichere CI-Secrets und die tatsächliche Play-Console-Anwendung separat
einzurichten. Eine andere Signatur erlaubt kein gewöhnliches Update der bereits lokal
installierten App. Schlüssel und `key.properties` gehören nicht ins Repository.
Versions-/Buildnummern können für spätere Veröffentlichungen über `--build-name` und
`--build-number` gesetzt werden; dieses Skript hält den Pixel-Build `0.2.2+5` fest.

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

## Passwortmanager

Anmeldefelder verwenden explizite Flutter-Autofill-Hints. Der Passwortschritt zeigt E-Mail
und Passwort gemeinsam; Bitwarden unterstützt auf Android keine vollständig auf getrennte
Bildschirme verteilten Loginfelder. Der auf dem Pixel aktivierte Dienst ist Bitwarden.
Ein vorhandener Eintrag für `https://akribos.de` kann zusätzlich die URI
`androidapp://de.akribos.app` erhalten, damit er dieser nativen App zugeordnet wird.
Die App verändert keine Tresoreinträge selbst.

Felderkennung und Eintragszuordnung sind getrennt: Auf iOS erfordert die vollständige
Webpasswort-/Speicherintegration zusätzlich die tatsächliche Associated-Domains-Konfiguration
mit Apple-Team und Domainzuordnung. Diese ist noch nicht eingerichtet. Die Widgettests
prüfen den Flutter-Autofill-Kanal; eine echte Passwortmanager-Abnahme muss am entsperrten
Gerät mit Freigabe des eigenen Tresors erfolgen.

Quellen: [Flutter Autofill](https://api.flutter.dev/flutter/material/TextField/autofillHints.html),
[Bitwarden Android](https://bitwarden.com/help/auto-fill-android/),
[Bitwarden URI-Zuordnung](https://bitwarden.com/help/uri-match-detection/).

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

Die PNG-Dateien unter `docs/screenshots/` stammen aus dem Flutter-Widget-Test mit anonym
abgerufenen öffentlichen Readerdaten von akribos.de (Johannes 3, Akribos Luther und King
James). Sie enthalten keine privaten Kontodaten und sind keine Gerätefotos. Der optionale
Test verwendet ohne externe Daten den kleinen Test-Seed. Unter Linux mit
`/usr/share/fonts/noto/NotoSans-Regular.ttf`:

```sh
flutter test --no-pub test/app_shell_test.dart \
  --plain-name 'capture reproducible seeded Flutter reading views' \
  --dart-define=AKRIBOS_SCREENSHOTS=true
```

Für öffentliche Produktionsdaten können zusätzlich `AKRIBOS_CAPTURE_BOOTSTRAP` und
`AKRIBOS_CAPTURE_READER` auf lokale JSON-Dateien zeigen. Die Dateien enthalten jeweils nur
das `data`-Objekt der anonymen App-API-Antwort, keine Cookies oder Tokens. Die Aufnahme
führt keine Servermutationen aus; schreibende Antworten sind im Widget-Test simuliert.
