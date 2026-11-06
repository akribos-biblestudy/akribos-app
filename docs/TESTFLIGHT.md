# TestFlight über GitHub Actions vorbereiten

Stand: 27. Oktober 2026. Apple-Zugang und Signierdateien sind vorbereitet;
der Workflow ist implementiert. Den tatsächlich ausgeführten Upload-Stand
belegt das `release.json`-Artefakt des jeweiligen GitHub-Laufs.

## Erledigte Apple-Einrichtung

- API-Zugriff nach ausdrücklicher Nutzerfreigabe beantragt und sofort genehmigt.
- Team-API-Schlüssel **slim-it GitHub Actions**, Rolle **App Manager**, erstellt
  und einmalig heruntergeladen. Der Nutzer hat den gemeinsamen Schlüssel für
  alle Apps gewünscht; keine Beschränkung auf Akribos möglich.
- **Apple Distribution: slim-it GmbH (8Y4NL9VW33)** erstellt; Zertifikat und
  verschlüsselter privater Schlüssel stimmen überein. Passwortgeschützter
  PKCS#12-Export wurde lokal geöffnet und geprüft. Ablauf: **26. Oktober 2027**.
- **Associated Domains** für `de.akribos.app` nach Nutzerfreigabe aktiviert.
- **Akribos App Store GitHub Actions** als App-Store-Provisioning-Profil erstellt
  und heruntergeladen. Team, exakte App-ID, Distribution-Eigenschaften,
  Associated Domains und das eingebettete Zertifikat wurden geprüft. Die
  CMS-Signatur ist geprüft; keine separate Zertifikatskettenvalidierung.
- Alle sechs Secret-Werte liegen als gleichnamige `.txt`-Dateien unter
  `~/.config/akribos/apple-testflight/2026-10-26/`, ausschließlich für den
  lokalen Benutzer lesbar. Dort enthält `README.md` die genaue Zuordnung und
  Bitwarden-Sicherungsanleitung. Keine Geheimnisse im Repository.
- Der Nutzer hat die sechs Secrets im Environment hinterlegt; `ios-testflight`
  ist auf die Branch `main` beschränkt. Die tatsächliche macOS-/TestFlight-Prüfung
  wird durch den Workflow-Lauf belegt, die Geräteabnahme bleibt separat.
- Die serverseitige AASA-Zuordnung auf akribos.de wurde nicht verändert.

Die folgenden Einrichtungsschritte dokumentieren den Ablauf für spätere
Wiederholungen; API-Schlüssel und Signieridentität jetzt nicht erneut erzeugen.

## Bestehender Stand

- App Store Connect: Akribos, Apple-ID `6827126169`, Bundle-ID `de.akribos.app`.
- Bestätigtes Apple-Team: slim-it GmbH, Team-ID `8Y4NL9VW33`.
- Letztes veröffentlichtes GitHub-Release: `v0.5.1`; die Apple-Version ist `0.5.1`.
- `ci.yml` baut nur einen unsignierten iOS-Simulatorbuild und führt XCTest aus.
- Veröffentlichte stabile Releases starten `ios-testflight.yml` und Android unabhängig
  voneinander auf `main`. Der iOS-Workflow kann zusätzlich manuell gestartet werden.
- **0.5.1 (2)** wurde am 27. Oktober signiert, hochgeladen und von Apple mit
  **VALID / READY_FOR_BETA_TESTING** bestätigt. Interne Tester ordnet der Nutzer
  selbst zu; die Geräteabnahme bleibt offen.

## Bestätigter erster Upload

Release-Quelle: `c5fec790b70afcedc6d75617f746874d43b29d44` (`v0.5.1`).
Apple-Build-ID: `5f12d27b-6b95-40ba-b998-ef559a913deb`. Der Lauf
[40469653975](https://github.com/akribos-biblestudy/akribos-app/actions/runs/40469653975)
hat die IPA erfolgreich erstellt und hochgeladen. Ein Fehler in der zusätzlichen
Testgruppen-Abfrage nach Apples Verarbeitung wurde anschließend korrigiert:
Die Statusabfrage verwendet `include=betaGroups,buildBetaDetail,preReleaseVersion`
am Build, da Apple keinen GET auf dem früher verwendeten Gruppenpfad unterstützt.
Der bestehende Build wird mit dem unten beschriebenen Verifikationsmodus erneut
bestätigt, ohne einen weiteren Build zu reservieren oder hochzuladen.

Buildnummer 1 bleibt nach dem fehlgeschlagenen ersten Signierimport verbraucht.
Der temporäre PKCS#12-Import verwendet einen Apple-kompatiblen Container;
die ursprüngliche verschlüsselte Signierdatei bleibt unverändert. Ein voller
GitHub-Artefaktspeicher ist gesondert ausgewiesen und kein Test-/Uploadfehler.

## Einmalige Apple-Einrichtung

1. In App Store Connect unter **Benutzer und Zugriff → Integrationen → App Store
   Connect API** gegebenenfalls API-Zugriff als Account Holder beantragen.
2. Einen dedizierten Team-API-Schlüssel für die Release-Automation mit Rolle
   **App Manager** anlegen. Key-ID und Issuer-ID notieren und die `.p8`-Datei
   sicher herunterladen. Team-Schlüssel gelten für alle Apps des Kontos,
   also auch RevierFeed; eine Beschränkung auf Akribos ist bei diesem Schlüsseltyp
   nicht möglich. Niemals den Schlüssel in Chat oder Repository ablegen.
3. Für die Signierung ein **Apple Distribution**-Zertifikat samt privatem Schlüssel
   als passwortgeschützte `.p12` und ein **App Store Connect**-Provisioning-Profil
   für `de.akribos.app` bereitstellen. Zertifikat und privater Schlüssel müssen
   zusammenpassen. Ein `.cer` allein reicht nicht.
4. Vor Erstellen des Profils **Associated Domains** für die App-ID aktivieren:
   Das Projekt fordert bereits `applinks:akribos.de`. Die echte Domainzuordnung
   auf dem Server und ihre Geräteprüfung bleiben gesonderte Aufgaben.

Ein eigener Mac ist für den späteren CI-Lauf nicht nötig: GitHub stellt einen
macOS-Runner mit Xcode bereit. CSR/privater Schlüssel für eine neue Signieridentität
können auch unter Linux erzeugt werden; diese Identität muss ausdrücklich
beauftragt und geschützt außerhalb des Repositorys verwahrt werden.

## GitHub-Konfiguration

Ein geschütztes Environment **`ios-testflight`** anlegen, auf `main` beschränken
und dort folgende Secrets hinterlegen. Diese Namen sind für den noch zu
implementierenden Workflow vorgeschlagen, aktuell wird keines davon verwendet.

| Secret | Inhalt |
| --- | --- |
| `ASC_KEY_ID` | Key-ID des Apple-API-Schlüssels |
| `ASC_ISSUER_ID` | Issuer-ID des Apple-Teams |
| `ASC_PRIVATE_KEY` | Vollständiger Inhalt der `.p8`-Datei |
| `IOS_CERTIFICATE_P12_BASE64` | Base64 der `.p12` einschließlich privatem Schlüssel |
| `IOS_CERTIFICATE_PASSWORD` | Passwort der `.p12` |
| `IOS_PROVISIONING_PROFILE_BASE64` | Base64 der `.mobileprovision`-Datei |

Team-ID und Bundle-ID sind keine Geheimnisse. Ein temporäres Keychain-Passwort
soll der Workflow pro Lauf zufällig erzeugen. Die vorhandenen Android-Secrets
und der direkte Pixel-Build bleiben unabhängig.

## Workflow ausführen

Der Workflow [`ios-testflight.yml`](../.github/workflows/ios-testflight.yml) wird
bei einem veröffentlichten stabilen GitHub-Release durch `release.yml` auf `main`
gestartet; Android und iOS werden unabhängig voneinander dispatcht. Er kann auch
manuell auf `main` gestartet werden und veröffentlicht keine öffentliche App-Store-Version.

```sh
gh workflow run ios-testflight.yml --ref main -f release_tag=v0.5.1
```

Ein vorhandener Upload kann rein lesend nachgeprüft werden:

```sh
gh workflow run ios-testflight.yml --ref main -f release_tag=v0.5.1 -f verify_build=2
```

Dieser Modus läuft auf Linux, prüft die permanente Buildnummernreservierung
gegen den Release-Commit und Apples exakte App-/Versionsdaten. Er importiert
keine Signieridentität, baut keine IPA und lädt nichts hoch. Auch hier wird auf
grüne CI des aktuellen Workflow-Commits und der Release-Quelle gewartet.

Der Betreiber bestätigte am 6. November 2026 die Exportfreistellung für die
verwendete HTTPS-, Keychain- und AES-256-GCM-Nutzung, solange diese Einstufung
weiterhin zutrifft. Der automatische Dispatch setzt `encryption_exempt=true`.
Vor jeder Reservierung prüft der Workflow die versionierte
[`ios-encryption-attestation.json`](../scripts/ios-encryption-attestation.json)
gegen den konkreten Release-Quellstand: erfasst sind `pubspec.yaml`, `pubspec.lock`,
alle versionierten Dateien unter `ios/` und Dart-Dateien, die direkt Kryptografie-,
Secure-Storage-, Keychain-, TLS-/SSL-, Security- oder FFI-Bibliotheken importieren,
exportieren oder als Part einbinden. Neue und geänderte erfasste Dateien stoppen
den Lauf, bevor eine Buildnummer reserviert oder ein Upload gestartet wird. Die
Attestierung darf nur nach erneuter Prüfung und Bestätigung aktualisiert werden.

Der Importabgleich ist eine konservative Hilfe, kein vollständiger Nachweis: etwa
indirekte Verwendung über bestehende Wrapper, eigene Implementierungen oder neue
Bibliotheken mit unauffälligem Namen können außerhalb des erfassten Dart-Scopes
liegen. Jede Änderung der Kryptografie oder ihrer Nutzung muss deshalb zusätzlich
im Code-Review auf die Export-Einstufung geprüft werden. Die Build-Kopie erhält
nur nach bestandener Prüfung `ITSAppUsesNonExemptEncryption=false`. Manuelle Läufe
ohne `encryption_exempt=true` lassen die Angabe offen. Ein bereits hochgeladener
Build mit fehlender Export-Einstufung muss in App Store Connect geklärt werden;
nicht blind erneut hochladen.

Der Workflow verwendet Flutter **3.47.0**, Xcode **26.3** auf `macos-15` und
checksum-gepinnte Actions. Python benötigt außer der Standardbibliothek nur
das auf dem Runner vorhandene OpenSSL, keine zusätzlichen PyPI-Abhängigkeiten.

### Quelle und Freigabeprüfungen

Die Release-Werkzeuge kommen ausschließlich vom aktuellen `main`-Commit.
Die App wird separat am exakten Commit des veröffentlichten `vX.Y.Z`-Tags
ausgecheckt. Der Tag darf älter als die Workflow-Implementierung sein, muss
aber ein Vorfahr von `main` sein. Der Tag wird niemals verschoben. Release-ID,
Tag-Commit, aktuelles `main` und die jeweils neueste erfolgreiche Main-Push-CI
für **beide** Commits werden geprüft. Am Einstieg wird höchstens 45 Minuten auf
laufende CI gewartet; abgeschlossene Fehler und API-Fehler brechen sofort ab.
Vor Signierung, Build und Upload gelten erneute strikte Prüfungen ohne Warten.

Alle existierenden Apple-Buildnummern und permanenten Tags nach dem Muster
`testflight-build-ios-N` werden berücksichtigt. Die nächste Nummer wird atomar
als Git-Ref reserviert. Fehlgeschlagene Nummern bleiben verbraucht; Tags dürfen
nicht gelöscht oder wiederverwendet werden. Android-Versioncodes sind unabhängig.

### Signierung, Upload und Nachweis

Zertifikat und Profil werden nur in einem temporären Keychain importiert.
Profiltyp, Team, Bundle-ID, Ablauf, Associated Domains und zum privaten Schlüssel
passendes Zertifikat werden geprüft. Team und manuelle Signierung werden nur in
der ausgecheckten Build-Kopie gesetzt; das Repository enthält keine Identität.
Die exportierte IPA wird nochmals entpackt, auf Signatur, Version, Entitlements
und eingebettetes Profil geprüft. Danach wird ihr SHA-256-Hash festgehalten.

Apples `altool` validiert die IPA vor dem einmaligen Upload. Ein gestarteter
Upload wird im Manifest festgehalten und niemals still wiederholt. Danach wartet
der Workflow bis zu 35 Minuten auf exakt diese Marketingversion und Buildnummer.
`FAILED`/`INVALID` brechen ab; ein Upload ohne abgeschlossene Verarbeitung wird
nicht als bestätigter TestFlight-Build ausgegeben. Nur `VALID` setzt
`processingVerified=true`. Export-Compliance und interner Teststatus werden
separat erfasst; gültige Verarbeitung allein ist keine Geräteabnahme.

Unter `build/testflight/` werden IPA, SHA-256, dSYM-Symbole und `release.json`
als GitHub-Artefakt für 30 Tage aufbewahrt. Bei vollem GitHub-Kontingent ist
die zusätzliche Artefaktablage optional und erzeugt eine ausdrückliche Warnung;
IPA-Hash und tatsächlich bestätigtes Apple-Ergebnis stehen auch im Job-Bericht
und den Logs. Ein fehlendes IPA-Download-Artefakt wird dort ausdrücklich genannt.
Auch das Debug-APK-Artefakt der regulären CI ist optional; Tests und Builds
bleiben verpflichtend. Schlüssel, Passwörter, temporäres Profil
und Keychain werden beim Abschluss entfernt. Der Build wird keiner externen
Prüfung zugeführt. Die bestehende interne Gruppe `Betatester` verteilt Xcode-Builds
automatisch. Nach einem Upload prüft der Workflow für höchstens fünf Minuten die
Zuweisung genau dieser Gruppe und den Status `IN_BETA_TESTING`. Wird sie nicht
bestätigt oder fehlen Exportangaben, meldet er den bereits hochgeladenen Build und
schlägt fehl; vor einem Wiederholungsversuch zunächst TestFlight prüfen, damit kein
zweiter Build unnötig hochgeladen wird. Gruppen und interne Tester werden in App
Store Connect verwaltet; der Workflow fügt keine Gruppen hinzu und verschickt keine
Einladungen.

Ein interner Tester benötigt App-Zugriff als App-Store-Connect-Nutzer und eine
Zuweisung des Builds zu seiner internen Testgruppe. Externe Tester benötigen
zusätzlich die Beta-App-Prüfung. TestFlight-Builds sind maximal 90 Tage testbar.
Eine öffentliche App-Store-Veröffentlichung ist dafür nicht erforderlich.

## Lokale Prüfungen

```sh
python3 -m unittest discover -s scripts/tests -v
go run github.com/rhysd/actionlint/cmd/actionlint@v1.7.11 .github/workflows/ios-testflight.yml
```

Die Tests prüfen insbesondere Release-/CI-Abbrüche, unveränderliche
Buildnummernreservierungen, API-Zielvalidierung/Pagination, Profilgrenzen,
fehlgeschlagene IPA-Validierung und fehlende Wiederholung unsicherer Uploads.
Ein Linux-Test ersetzt keinen signierten macOS-Build oder Apple-Upload.

## Primärquellen

- [Apple: API-Zugriff und Schlüssel](https://developer.apple.com/help/app-store-connect/get-started/app-store-connect-api/)
- [GitHub: Apple-Zertifikat auf macOS-Runnern installieren](https://docs.github.com/en/actions/how-tos/deploy/deploy-to-third-party-platforms/sign-xcode-applications)
- [Flutter: iOS bauen und veröffentlichen](https://docs.flutter.dev/deployment/ios)
- [Apple: TestFlight-Ablauf](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/)
