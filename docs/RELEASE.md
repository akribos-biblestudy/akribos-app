# Bauen und auf Geräten prüfen

Der aktuell tatsächlich ausgeführte Prüfstand steht in [VALIDATION.md](VALIDATION.md).
Die automatisierte Store-Verteilung startet für stabile Releases Android und iOS
unabhängig voneinander in ihre internen Testkanäle.
Das Apple-Team slim-it GmbH (`8Y4NL9VW33`) und der Akribos-Eintrag sind seit
26. Oktober 2026 bestätigt; API-Schlüssel, Distribution-Zertifikat und Akribos-Profil
sind vorbereitet. Der TestFlight-Workflow wird automatisch oder manuell gestartet; seinen tatsächlichen
Build-/Upload-Stand belegen die GitHub-Läufe. Einrichtung und offene Schritte: [TESTFLIGHT.md](TESTFLIGHT.md).

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
| Version / Android-Versionscode | `0.2.9` / `12` |
| Architektur | `android-arm64` |
| Laufzeit | Optimierter Flutter-Release-Build mit AOT, ohne Debugger |
| Signatur | Vorhandener lokaler Android-Debugschlüssel; identisch mit Build 2 |
| APK | `artifacts/akribos-0.2.9-akribos-de-release.apk` |

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
(cd artifacts && sha256sum -c akribos-0.2.9-akribos-de-release.apk.sha256)
```

Die APK wird als Update der vorhandenen App installiert; **nicht vorher deinstallieren
oder App-Daten löschen**. Gleiche Anwendungs-ID, derselbe Signer und höherer Versionscode erhalten
die Android-App-Daten beim Update von Build 2. Die Installation erfolgt ausschließlich als Paketupdate:

```sh
adb -s <Geraeteseriennummer> install -r artifacts/akribos-0.2.9-akribos-de-release.apk
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

Die vollständige Schrittfolge und die neuen Android-GitHub-Workflows stehen in
[PLAY-STORE.md](PLAY-STORE.md). Veröffentlichte `vX.Y.Z`-Releases starten den geschützten
Workflow auf `main`; nach dem einmaligen manuellen Erstupload veröffentlicht dieser
ausschließlich nach Google Play Internal Testing. Die vorhandene Store-Einrichtung,
das geschützte GitHub-Environment und die Prüfung des tatsächlichen Upload-Ergebnisses
sind dort dokumentiert.

Parallel startet das Release den TestFlight-Workflow. Er überprüft nach dem Upload,
ob Apple den Build der internen Gruppe `Betatester` zugeordnet und für Tests
freigegeben hat. Die bestätigte Export-Einstufung wird nur bei passendem attestierten
Quellumfang gesetzt; Kryptografieänderungen erfordern erneute Prüfung. `VALID` allein
bedeutet noch keine Verteilung an Tester. Details und der tatsächliche
Laufstatus stehen in [TESTFLIGHT.md](TESTFLIGHT.md).

Die direkte APK verwendet produktiven Server und optimierten Release-Code, ist jedoch
weiter mit dem bisherigen lokalen Debugschlüssel signiert. Google Play verwendet die
separat eingerichtete Upload-Signatur und die Secrets im Environment `android-play-internal`.
Der reguläre Release-Ablauf erzeugt keine neue Signieridentität. Eine andere Signatur
erlaubt kein gewöhnliches Update der bereits lokal
installierten App. Schlüssel und `key.properties` gehören nicht ins Repository.
Versions-/Buildnummern können für spätere Veröffentlichungen über `--build-name` und
`--build-number` gesetzt werden; dieses Skript hält den Pixel-Build `0.2.9+12` fest.

## iOS – Signierung und TestFlight vorbereiten

Das Apple-Team ist bestätigt, Signierdateien und die App-ID-Fähigkeit Associated
Domains sind vorbereitet. Signierter Build, serverseitige Domainzuordnung, Geräteabnahme
und Verteilung stehen noch aus; siehe [TESTFLIGHT.md](TESTFLIGHT.md) und [TODO.md](TODO.md).

Ein unsignierter Entwicklungsbuild ist auf macOS möglich:

```sh
flutter pub get --enforce-lockfile
flutter build ios --debug --no-codesign
```

Für echte Geräte und TestFlight in Xcode das tatsächliche Apple-Team und ein passendes
Provisioning-Profil für `de.akribos.app` hinterlegen. Keychain-Entitlements sind bereits für
Debug/Profile/Release gesetzt. Die aktuelle CI prüft Android sowie einen unsignierten
iOS-Simulatorbuild mit nativen Policytests; der manuelle iOS-Workflow steht in [TESTFLIGHT.md](TESTFLIGHT.md). Linux
kann die Apple-Geräte- und Veröffentlichungsschritte nicht verifizieren.

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
konfigurierten Origins werden übernommen. Android-App-Links sind mit `autoVerify` ausschließlich
für `akribos.de` eingerichtet, für HTTP und HTTPS sowie alle Pfade, ohne `www` oder Wildcard.
HTTP-Links werden nur für denselben Host auf dem Standardport intern zu HTTPS aufgewertet.
`/.well-known/assetlinks.json` ist im Server vorbereitet. Die Zuordnung muss
Paketname `de.akribos.app`, den tatsächlichen Zertifikatfingerprint und den HTTPS-Host verbinden.
Konfiguration allein ist keine bestätigte Live-Funktion: Die Domain-Datei muss veröffentlicht
und vom Betriebssystem auf dem Gerät erfolgreich verifiziert werden. Der bestätigte Stand
gehört nach [VALIDATION.md](VALIDATION.md).

Für iOS ist die Team-ID `8Y4NL9VW33` bestätigt. Das Entitlement
`applinks:akribos.de` ist vorbereitet; eine passende `apple-app-site-association` muss
mit dieser echten Team-ID eingerichtet und zusammen mit der Signierung auf einem Gerät geprüft werden.
Diese Zuordnung und iOS-Veröffentlichung sind noch offen. E-Mail-Code-Anmeldung
funktioniert unabhängig von der automatischen HTTPS-Linkzuordnung.

## Geräteabnahme

| Gerät/Situation | Prüfung |
| --- | --- |
| Android-Telefon | Start, Anmeldung/Neustart, Zurück, lange Texte, Tastatur, Dateiauswahl, Teilen, Rücksetzlinks; Suche im aktuellen Werk und Notizen-Einstieg |
| iPhone, spätere Freigabe | Keychain-Sitzung, Login-Code, Tastatur/Safe Areas, System-Share, Link-Rückkehr |
| Android-Tablet; iPad später | Flache Tabfolge aller lokalen Werke, Querformat und Fensterwechsel ohne Umordnung; sämtliche Werke und Lesestellen bleiben erreichbar |
| Boox/E-Ink | Kontrast, Ghosting, fortlaufendes Scrollen, Touch-Reaktion, Lesbarkeit von Markierungen |
| Barrierefreiheit | Große Systemschrift, Screenreader, Kontrast, Bedienung der Dialoge |
| Schlechte Verbindung | Sichtbare Fehler, Erhalt von Dokumententwürfen, erneutes Speichern, keine stillen Konfliktüberschreibungen |
| Mehrere Geräte/Konten | Lokale Tabs, Stellen und Suchen bleiben beim Neustart erhalten und voneinander getrennt; App-Navigation verändert keine Browser-Arbeitsbereiche; Dokumentrevisionen und Rechtewiderruf |

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

## Versionsanzeige und Updatehinweise

Die App liest Version/Build aus dem installierten Android-Paket bzw. iOS-Bundle. Ein über
GitHub Releases gesetzter Buildname/-code erscheint damit ohne zusätzliche Codepflege in
Einstellungen und Über Akribos. Das Updateangebot stammt vom jeweiligen Store, nicht von
GitHub. Es funktioniert erst in einem Build, der diese Funktion enthält.

Android benötigt eine von Google Play installierte und für das verwendete Konto berechtigte
App; direkte APKs melden keine verfügbare Store-Prüfung. Zur Geräteabnahme einen solchen
Build installieren und danach einen höheren Build für dasselbe Testkonto bereitstellen.
iOS benötigt eine echte öffentliche Listung im Storefront des Apple-Kontos. Bekannte
Entwicklungs-/Simulatorbuilds und Sandbox-Receipts bieten keine öffentliche Updateprüfung.
Nach erfolgter Apple-Einrichtung auch eine echte Store-Installation prüfen. Eine fehlende
Listung oder fehlende Berechtigung darf nicht als „aktuell“ erscheinen.

Die normale CI baut Android und einen unsignierten iOS-Simulatorstand und führt native
Policytests auf beiden Plattformen aus. Sie erzeugt keine Store-Veröffentlichung; Signierung,
Geräteabnahme und ein ausdrücklich veröffentlichtes GitHub Release bleiben getrennte Schritte.
