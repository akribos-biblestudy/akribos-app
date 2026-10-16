# Android über Google Play veröffentlichen

Stand: 16. Oktober 2026. Dieses Repository veröffentlicht zunächst ausschließlich
Android nach **Google Play Internal Testing**. iOS folgt erst nach Abschluss der
Apple-Organisationsregistrierung und Einrichtung der tatsächlichen Signierung.

| Workflow | Auslöser | Ergebnis |
| --- | --- | --- |
| `Flutter CI` (`ci.yml`) | Pull Request, Push auf `main`, manuell | Formatprüfung, Analyse, Flutter-Tests, Tests der Release-Sperren und Debug-APK als Prüfarbeitsstand |
| `Android Play Internal Testing` (`android-play.yml`) | Manuell auf `main`, mit `bootstrap_version` | Signiertes erstes AAB als GitHub-Artefakt; **kein Store-Upload** |
| `Dispatch Android Play Release` (`release.yml`) | Veröffentlichtes GitHub-Release `vX.Y.Z`, kein Vorabrelease | Startet den Store-Workflow ausdrücklich auf `main`, ohne Store-Secrets |
| `Android Play Internal Testing` | Aufruf des Dispatchers mit `release_tag` | Signiertes AAB, Upload ausschließlich im internen Testkanal; anschließende Kontrolle des Kanalstands |

Eine APK aus der normalen CI ist kein Store-Release. Die bestehende direkte
Pixel-APK aus `scripts/build-android-production.sh` verwendet weiter ihren bisherigen
Schlüssel; dieser Weg und seine Version `0.2.9+12` bleiben getrennt.

## 1. GitHub vorbereiten

Das private Repository liegt unter
[akribos-biblestudy/akribos-app](https://github.com/akribos-biblestudy/akribos-app).
Die Dateien müssen auf `main` veröffentlicht sein, bevor Actions ausgeführt werden
können. Danach unter **Actions → Flutter CI** einen erfolgreichen Lauf des aktuellen
`main`-Commits abwarten.

Das Environment `android-play-internal` ist bereits eingerichtet und seine API-
Konfiguration geprüft: exakt eine erlaubte Deployment-Regel, Branch `main`, keine
Tags. Am 16. Oktober 2026 sind alle fünf Secrets aus Abschnitt 4 im Environment
`android-play-internal` hinterlegt und ihre Namen/Zuordnung verifiziert. Die Erstellung
des eigenen Uploadschlüssels und die Ablage in GitHub wurden vom Nutzer ausdrücklich
freigegeben. Die Variablen `PLAY_BOOTSTRAP_ALLOWED=false` und
`PLAY_VERSION_CODE_FLOOR=12` sind gesetzt; `ANDROID_UPLOAD_CERT_SHA256` enthält den
unten dokumentierten öffentlichen Fingerabdruck.

Unter **Settings → Environments** diese Bindung bei Änderungen erneut kontrollieren.
Sie ist eine Voraussetzung, keine optionale Empfehlung. Secrets nicht ersatzweise
auf Repository-Ebene hinterlegen.

`main` und Release-Tags zusätzlich gegen unkontrollierte Änderungen schützen;
Änderungen an `.github/` und `scripts/play_release.py` mitprüfen. Bei Übertragung in
ein anderes privates Repository zuerst prüfen, ob dessen Tarif die erforderliche
Environment-Branchbindung unterstützt. Allgemeiner Branchschutz ersetzt sie nicht.

Der Release-Dispatcher verarbeitet nur den Tagnamen und checkt keinen Tag-Code aus.
Der signierende Workflow läuft immer mit dem Workflow und Gatecode von `main`;
dort wird das veröffentlichte Tag erneut gegen den aktuellen Commit und CI geprüft.
Ein optionaler Environment-Reviewer verlangt vor jedem Lauf eine manuelle Freigabe.
Ohne Reviewer läuft ein freigegebenes GitHub-Release nach den eingebauten Prüfungen
automatisch. **Actions → General** muss die verwendeten gepinnten Actions zulassen.
Der Storejob benötigt `contents: write`, um Versionsnummern als Tags zu reservieren,
und `actions: read`, um den CI-Status zu prüfen. Er bearbeitet keine Quelltextdateien.
[GitHub erklärt Environment-Regeln und Secret-Zugriff hier.](https://docs.github.com/en/actions/reference/workflows-and-actions/deployments-and-environments)

## 2. Google-Play-Konto und App anlegen

In der [Google Play Console](https://play.google.com/console/) das richtige
Entwicklerkonto registrieren beziehungsweise auswählen und die dort verlangte
Identitäts-/Organisationsprüfung abschließen. Eine App namens **Akribos**, Sprache
Deutsch, Typ **App** und die gewünschte Preisgestaltung anlegen. Der Paketname des
Bundles ist fest **`de.akribos.app`**; keinen abweichenden Paketnamen verwenden.

Die App **Akribos – Bibelstudium** ist angelegt; der Dienstkonto-Zugriff wurde mit
HTTP 200 bestätigt. Am 16. Oktober 2026 wurden alle ursprünglich elf Einrichtungspunkte
gespeichert: neun Erklärungen zu App-Inhalten, Kategorie/Kontakt und Store-Eintrag.
Nach dem ersten Bundle wurde zusätzlich „Werbe-ID: Nein“ gespeichert. Die Console
zeigte anschließend „Alles erledigt“ und zehn abgeschlossene App-Inhaltserklärungen.

Der deutsche Store-Eintrag und Kontakt wurden committed und zurückgelesen; Texte und
Werte sowie die Hashes von 1 Icon, 1 Funktionsgrafik und 4 Screenshots stimmen überein.
Das erste Bundle `0.3.0+13` wurde manuell im internen Test veröffentlicht, siehe
Abschnitt 6. Das normale Prüfkonto `stores@akribos.de` mit dauerhaftem Passwort wurde
in einem isolierten Login geprüft; Zugangsdaten stehen nur in der geschützten Console
und lokal unter `~/.config/akribos/play-review/reviewer-credentials.json`.

Die konkreten Erklärungen, 17 ausgewählten Datenarten, der Vergleich aller 782
Datensicherheits-Antwortfelder sowie offene Betriebs-/Moderationsfragen stehen in
[PLAY-STORE-CONTENT.md](PLAY-STORE-CONTENT.md). Abgeschlossene Formulare sind keine
umfassende Richtlinienfreigabe. Eine spätere öffentliche Veröffentlichung hat
zusätzliche Anforderungen und wird von diesem Workflow nicht ausgelöst. Preis und
Produktionsländer wurden in diesem Auftrag nicht geändert.
[Google beschreibt Konto und Einstieg in die Console.](https://support.google.com/googleplay/android-developer/answer/6112435?hl=de)

Die [Datenschutzerklärung](https://akribos.de/datenschutz) und der sichtbare
[Löschantrag](https://akribos.de/datenschutz#konto-loeschen) decken den nativen Betrieb
ab und sind in der Console gespeichert. Webcommit
`b548a4a649c2dc4c084e02ee280ee854051eb285` wurde über
[Main-CI 38937820390](https://github.com/akribos-biblestudy/akribos/actions/runs/38937820390)
erfolgreich veröffentlicht. Am 16. Oktober 2026 um 17:24 UTC waren Datenschutzseite,
Löschanker und Mailto geprüft; die Seite und `/healthz` lieferten HTTP 200.
Die sieben Tage für Löschantragsbearbeitung sind keine pauschale Backup-Löschfrist.
Die Datensicherheit ist ausgefüllt, obwohl ausschließlich interne Tests laut Google
vom Formular ausgenommen sind. Vor weiteren Tracks den tatsächlichen Betrieb und
neue Funktionen erneut mit den Angaben abgleichen.
[Offizielle Hinweise zur Datensicherheit.](https://support.google.com/googleplay/android-developer/answer/10787469?hl=de)

## 3. Uploadschlüssel und Play App Signing einrichten

Am 16. Oktober 2026 wurde mit ausdrücklicher Freigabe des Nutzers ein **eigener
Uploadschlüssel für den Store** angelegt. Er ist vom Schlüssel der direkten Pixel-APK
getrennt. Der Release-Workflow erzeugt keine neuen Signieridentitäten.

| Öffentliche Eigenschaft | Verifizierter Wert |
| --- | --- |
| Schlüsseltyp | RSA, 4.096 Bit |
| Zertifikatsname | `CN=Akribos Upload` |
| SHA-256 des Uploadzertifikats | `890bc7a97d2ca6f07bc120daacdd827bac7c55f0e626568f88eb92a7afc2f0ba` |
| Lokale sichere Ablage | `~/.config/akribos/play-signing/` |

**Den gesamten lokalen Ordner verschlüsselt und getrennt vom Arbeitsgerät sichern.**
Er enthält den Uploadkeystore und die zugehörigen Angaben/Passwörter. Nur die
Zertifikatskennung darf öffentlich dokumentiert werden; Keystore und Passwörter
gehören nicht in Git, Chats oder Screenshots. Die GitHub-Secrets dienen dem Workflow,
sind aber kein nachträglich auslesbares Backup dieses Ordners.

Geht der Uploadschlüssel verloren, lässt er sich bei Nutzung von Play App Signing
über einen von Google bestätigten Reset ersetzen: neuen Uploadschlüssel anlegen,
öffentliches PEM-Zertifikat exportieren und in der Play Console die Zurücksetzung
anfordern. Anschließend die GitHub-Secrets und den erwarteten Fingerabdruck passend
aktualisieren. Das ist ein gesonderter Wiederherstellungsvorgang, kein Grund, jetzt
den vorhandenen Schlüssel neu zu erzeugen.
[Google beschreibt das Zurücksetzen des Uploadschlüssels.](https://support.google.com/googleplay/android-developer/answer/9842756?hl=de)

**Play App Signing** ist aktiv und wurde nach dem ersten manuellen Bundle-Upload
in der Console bestätigt. Google signiert die ausgelieferten APKs mit dem App-Signaturschlüssel; das AAB wird
vorher mit deinem Uploadschlüssel signiert. Diese Zertifikate haben unterschiedliche
Aufgaben. Aus dem Digital-Asset-Links-JSON der Console wurde der öffentliche
SHA-256-Fingerabdruck des **App-Signaturzertifikats** bestätigt:
`6E:26:73:AB:76:E0:1F:36:C8:C0:EF:A2:2C:15:EC:18:95:13:2E:8E:F7:60:12:3F:86:91:40:CD:E1:DA:0C:09`.
[Google erklärt beide Schlüssel und deren Einrichtung.](https://developer.android.com/studio/publish/app-signing)

Den öffentlichen SHA-256-Fingerabdruck des Uploadzertifikats über Android Studio
oder interaktiv mit folgendem Befehl ermitteln; das Passwort nicht als Argument
angeben:

```sh
keytool -list -v -keystore /sicherer/pfad/akribos-upload.jks -alias akribos-upload
```

**Die aktuelle Pixel-Installation kann durch eine anders signierte Play-App nicht
direkt aktualisiert werden.** Ihre bisherigen APK-Updates funktionieren weiterhin
mit dem bisherigen Schlüssel. Jetzt keine Deinstallation oder Datenlöschung
vornehmen. Den ersten Play-Test möglichst auf einem anderen Testgerät durchführen.
Ein späterer Wechsel des Pixels wird separat geplant: lokale Tabs und ungespeicherte
Entwürfe sind nicht automatisch im Serverkonto gesichert. Die Tabansicht kann vor
einem solchen Wechsel ausdrücklich über „Ansicht teilen“ als Link gesichert werden.

## 4. GitHub-Secrets und Variablen eintragen

Unter **Settings → Environments → android-play-internal** sind die folgenden fünf
Secrets hinterlegt. Am 16. Oktober 2026 wurden ihre Namen und das ausschließlich
für `main` freigegebene Environment geprüft; Werte werden nicht ausgegeben.

| Environment Secret | Inhalt |
| --- | --- |
| `ANDROID_UPLOAD_KEYSTORE_BASE64` | Base64-Inhalt des bestehenden Store-Uploadkeystores |
| `ANDROID_UPLOAD_STORE_PASSWORD` | Passwort des Keystores |
| `ANDROID_UPLOAD_KEY_PASSWORD` | Passwort des privaten Schlüssels |
| `ANDROID_UPLOAD_KEY_ALIAS` | Alias dieses Schlüssels |
| `PLAY_SERVICE_ACCOUNT_JSON` | Vollständiges JSON des bereits berechtigten Dienstkontos; vorhanden, für den ersten Bootstrap noch nicht erforderlich |

| Environment Variable | Anfangswert / Bedeutung |
| --- | --- |
| `ANDROID_UPLOAD_CERT_SHA256` | `890bc7a97d2ca6f07bc120daacdd827bac7c55f0e626568f88eb92a7afc2f0ba` |
| `PLAY_VERSION_CODE_FLOOR` | `12` bei der neuen Akribos-App; bei bestehender Play-Historie mindestens die höchste jemals verwendete Versionsnummer |
| `PLAY_BOOTSTRAP_ALLOWED` | Nur für Schritt 5 auf `true`, anschließend auf `false` setzen |

Base64 ist lediglich eine Kodierung und kein Schutz. Keystore, JSON und Passwörter
gehören ausschließlich in die Secret-Verwaltung, nie in Git, Screenshots, Chat oder
Workflow-Parameter. Beispielsweise lässt sich der Keystore mit der GitHub CLI direkt
als Secret übertragen, ohne seinen Inhalt im Terminal auszugeben:

```sh
base64 -w 0 /sicherer/pfad/akribos-upload.jks |
  gh secret set ANDROID_UPLOAD_KEYSTORE_BASE64 \
    --repo akribos-biblestudy/akribos-app --env android-play-internal
```

Der Befehl zeigt die Linux-Variante von `base64`. Auf anderen Systemen deren lokale
Optionen verwenden. Secret-Passwörter interaktiv in GitHub eintragen.

## 5. Erstes Bundle bauen

Nach grünem **Push-CI-Lauf** für den aktuellen `main`-Commit unter **Actions → Android
Play Internal Testing → Run workflow** den Branch `main` wählen. Für diesen Lauf
`PLAY_BOOTSTRAP_ALLOWED` vorübergehend auf `true` setzen, beispielsweise
`bootstrap_version: 0.3.0` eingeben und `release_tag` leer lassen. Nur für eine App verwenden,
deren erstes Bundle noch manuell hochzuladen ist. Der Bootstrap fragt die noch nicht verfügbare Play-App
nicht per API ab; der bestätigte Mindeststand kommt aus Schritt 4.

Der Lauf reserviert eine neue Versionsnummer, baut für `https://akribos.de`, signiert
das AAB mit dem Uploadschlüssel und prüft Signatur, Paketname, Version und
Nicht-Debug-Build. Unter **Artifacts** das Paket `akribos-play-VERSION-NUMMER`
herunterladen. Es enthält `.aab`, `SHA256SUMS` und `release.json` mit
`storeUploaded: false`. Ein AAB wird nicht direkt auf das Pixel installiert.
Die Bootstrap-Freigabe nach Abschluss des Laufs wieder auf `false` setzen, auch bei einem
Fehler; der anschließende manuelle Upload benötigt diese Variable nicht.

### Verifiziertes erstes Bundle

Der [Bootstrap-Lauf 38919965671](https://github.com/akribos-biblestudy/akribos-app/actions/runs/38919965671)
ist erfolgreich abgeschlossen. Das heruntergeladene Artefakt wurde zusätzlich lokal gegen
`SHA256SUMS` und `release.json` geprüft:

| Merkmal | Bestätigter Wert |
| --- | --- |
| Quellcommit | `34af18d5760905efdfa21ccfb239c9e4b5a6cbeb` |
| Paket / Version / Build | `de.akribos.app` / `0.3.0` / `13` |
| GitHub-Artefakt | `akribos-play-0.3.0-13`, ID `12054404581` |
| Lokale Datei, Git-ignoriert | `artifacts/play-0.3.0-13/akribos-0.3.0-13.aab` |
| AAB-SHA-256 | `c896fe3eac29c696d3b5fd4a29947728e0ad7406abf3d420b0e1ea4cb96ab621` |
| Uploadzertifikat, SHA-256 | `890bc7a97d2ca6f07bc120daacdd827bac7c55f0e626568f88eb92a7afc2f0ba` |
| Ergebnis im Manifest | `storeUploaded: false` |
| Bootstrap-Freigabe | Nach Abschluss auf `false` gesetzt und zurückgelesen |

Die CI hat Paket, Version und Nicht-Debug-Build geprüft. Auch lokal bestätigt `jarsigner`
die Signatur; der Strict-Rückgabewert `4` beruht auf dem erwarteten selbstsignierten
Uploadzertifikat und seiner fehlenden öffentlichen Vertrauenskette. Der Bootstrap-Lauf
selbst lädt nicht hoch: `storeUploaded: false` im damaligen Artefakt bleibt richtig.
Der spätere manuelle Upload und interne Release sind separat in Abschnitt 6 bestätigt;
eine Play-Geräteinstallation wird damit nicht behauptet. Der nach diesem Quellcommit
ergänzte native Einstieg zum Löschantrag fehlt in `0.3.0+13`; er gehört zum nachfolgenden
Release auf `e7210efe8f06f01433b69a396f3cd34160b6b743` (Abschnitt 8).

## 6. Einmalig manuell nach Internal Testing hochladen

### Bestätigter erster interner Release

Das oben geprüfte Bundle **0.3.0+13** mit SHA-256
`c896fe3eac29c696d3b5fd4a29947728e0ad7406abf3d420b0e1ea4cb96ab621` wurde am
16. Oktober 2026 manuell in der Console hochgeladen. Der interne Release wurde als
**`completed` und verfügbar** bestätigt. Damit sind erster Upload, Play-App-Signing-
Einrichtung und interner Release erfolgt; das ist keine öffentliche Veröffentlichung.

Die bestehende Testerliste **Beta-Tester** mit **einem Eintrag** ist eingerichtet.
Der bestätigte Beitrittslink lautet:
[Am internen Akribos-Test teilnehmen](https://play.google.com/apps/internaltest/4701209263936680498).
Tester müssen mit einem freigegebenen Google-Konto beitreten. Verfügbarkeit im
internen Track belegt keine bereits erfolgte Installation oder Funktionsabnahme auf
einem Gerät. Der Signaturkonflikt mit der bisherigen direkten Pixel-APK bleibt bestehen.

### Ablauf bei einer neuen App

In der Play Console unter **Testen und veröffentlichen → Testen → Interner Test**
einen Release erstellen, das AAB aus Schritt 5 hochladen, Play App Signing
abschließen, Hinweise prüfen und den internen Release freigeben. Der vorbereitete
Ablauf sieht den ersten Bundle-Upload und die Signiereinrichtung ausdrücklich in der
Console vor. Der bereits bestätigte API-Zugriff auf einen noch leeren Entwurf ersetzt
weder diesen Upload noch erforderliche rechtliche Einwilligungen.
[Google erläutert den Ablauf der Publishing API.](https://developers.google.com/android-publisher/edits)

Unter **Tester** die gewünschten Google-Konten beziehungsweise eine Google-Gruppe
eintragen und den dort angezeigten Testbeitrittslink teilen. Jeder Tester muss mit
dem freigegebenen Google-Konto beitreten und über Google Play installieren. Der
interne Test unterstützt bis zu 100 Tester; die Verfügbarkeit kann nach der
Freigabe etwas dauern.
[Anleitung zu internen Tests.](https://support.google.com/googleplay/android-developer/answer/9845334?hl=de)

Die Bootstrap-Freigabe bleibt nach Schritt 5 auf `false`. Unter **App-Integrität / App-Signierung**
den SHA-256-Wert des **App-Signaturzertifikats** kontrollieren. Der für Akribos
bestätigte Wert steht in Abschnitt 3. Seine zusätzliche Zuordnung in
`../akribos/static/.well-known/assetlinks.json` wird über
[Web-PR #329](https://github.com/akribos-biblestudy/akribos/pull/329) nachgeführt;
der separate Webrelease muss inklusive öffentlicher JSON-Antwort geprüft werden.
Den bisherigen Pixel-Fingerprint erhalten; der Upload-Fingerprint ersetzt hier
nicht den App-Signatur-Fingerprint.
[Android App Links prüfen die Signatur der installierten App.](https://developer.android.com/training/app-links/configure-assetlinks)

## 7. Google-Play-API freigeben

Das vorhandene Dienstkonto hat die vom Nutzer in der Play Console erteilten
Akribos-Rechte; der API-Zugriff wurde mit HTTP 200 bestätigt. Es muss dafür kein
weiteres Dienstkonto angelegt werden. Das zugehörige JSON ist als Environment Secret
`PLAY_SERVICE_ACCOUNT_JSON` vorhanden. Die erfolgreichen Entwurfsabfragen und der
bestätigte Store-Listing-Commit ersetzen keine Prüfung des späteren Bundle-Uploads und
Release-Commits.

Für eine spätere Neueinrichtung die **Google Play Android Developer API** im passenden
Google-Cloud-Projekt aktivieren und dem vorgesehenen Dienstkonto in der Play Console
folgende Rechte gezielt für Akribos geben:

- App-Informationen ansehen (schreibgeschützt)
- App-Präsenz im Play Store verwalten (`CAN_MANAGE_PUBLIC_LISTING`)
- App-Entwürfe bearbeiten und löschen (`CAN_MANAGE_DRAFT_APPS`)
- Apps in Test-Tracks veröffentlichen (`CAN_MANAGE_TRACK_APKS`)

Bei der neuen Akribos-App funktionierten Listing-PUT und Bilderupload zunächst, die
Validierung eines geänderten Eintrags scheiterte jedoch mit HTTP 403. Nachdem der Nutzer
zusätzlich das App-Entwurfsrecht erteilt hatte, lieferte dieselbe Validierung HTTP 200;
der Listing-Commit und das anschließende Rücklesen waren erfolgreich. Das Entwurfsrecht
ist deshalb Teil dieser bestätigten Einrichtung. Es erlaubt allein keine Release-Einführung.
[Google erklärt die getrennten App-Rechte](https://support.google.com/googleplay/android-developer/answer/9844686?hl=de),
[API-Zuordnung der Rechte](https://developers.google.com/android-publisher/api-ref/rest/v3/grants).

Für diesen Workflow sind Produktions-Veröffentlichung und Finanzverwaltung nicht
vorgesehen; die aktuellen Berechtigungsbezeichnungen in der Console prüfen.

Bei erforderlichem Austausch einen neuen Dienstkonto-JSON-Schlüssel sicher ablegen
und `PLAY_SERVICE_ACCOUNT_JSON` im GitHub-Environment aktualisieren. Falls eure
Organisationsrichtlinie JSON-Schlüssel sperrt, ist zunächst eine bewusst eingerichtete
föderierte Authentifizierung erforderlich; diese Richtlinie nicht umgehen. Der
vorbereitete Workflow verwendet Dienstkonto-JSON, keine OAuth-Zugangsdaten eines
privaten Nutzerkontos.
[Offizielle Einrichtung von API und Dienstkonto.](https://developers.google.com/android-publisher/getting_started)

## 8. Weitere Versionen automatisch veröffentlichen

### Erster automatischer Releaseauftrag

Am 16. Oktober 2026 wurde
[GitHub-Release `v0.3.1`](https://github.com/akribos-biblestudy/akribos-app/releases/tag/v0.3.1)
auf exakt `e7210efe8f06f01433b69a396f3cd34160b6b743` veröffentlicht. Der
[Dispatcher 38939683333](https://github.com/akribos-biblestudy/akribos-app/actions/runs/38939683333)
war erfolgreich und startete
[Storelauf 38939695470](https://github.com/akribos-biblestudy/akribos-app/actions/runs/38939695470)
auf `main`. Der neue Quellstand enthält den nativen Einstieg zum Löschantrag.

Diese Angaben belegen den veröffentlichten Releaseauftrag und seinen Start. Für das
Ergebnis des automatischen Uploads sind der verlinkte Storelauf, dessen `release.json`
mit `storeUploaded`/`internalTrackVerified` und das Rücklesen des echten Play-Tracks
maßgeblich. Der oben unabhängig bestätigte manuelle Release `0.3.0+13` darf weder als
Nachweis noch als Gegenbeweis für den automatischen Folgelauf verwendet werden.

### Ablauf weiterer Releases

1. Änderungen auf `main` bringen und **Flutter CI** für exakt diesen Commit grün
   abwarten. Ein manueller CI-Lauf ersetzt den geforderten Push-CI-Lauf nicht.
2. In GitHub **Releases → Draft a new release** einen neuen Tag, etwa `v0.3.1`, auf
   genau diesem `main`-Commit auswählen. Release-Notizen ergänzen. **Set as a
   pre-release** ausgeschaltet lassen; der Track bleibt trotzdem ausschließlich intern.
3. **Publish release** ausführen. Während dieses Laufs `main` und den Tag unverändert
   lassen. Falls ein Environment-Reviewer eingerichtet wurde, den konkreten Lauf dort
   freigeben.
4. Der Workflow übernimmt `0.3.1` als sichtbare Version, reserviert die Buildnummer,
   signiert das Bundle, veröffentlicht es im Track `internal` und liest den Kanal
   danach zurück. `release.json` enthält erst nach akzeptiertem Commit
   `storeUploaded: true` und nach bestätigtem Rücklesen `internalTrackVerified: true`.
5. Den Release in der Play Console und auf einem angemeldeten Testgerät kontrollieren.
   Store-Verarbeitung, Prüfungen und Geräteannahme bleiben zusätzlich zur erfolgreichen
   API-Antwort relevant.

`pubspec.yaml` braucht dafür keine Versionsänderung: Flutter erhält `--build-name`
und `--build-number` aus dem Workflow. Die neue Nummer ist größer als alle aktuellen
Play-Bundles, APKs und Trackversionen, der konfigurierte Mindeststand und alle
GitHub-Reservierungen `play-build-android-N`. Reservierungen auch nach einem
fehlgeschlagenen Lauf **nicht löschen oder wiederverwenden**. Bei früheren manuell
hochgeladenen, inzwischen entfernten Versionen den Mindeststand entsprechend erhöhen.
[Flutter-Buildversionen](https://docs.flutter.dev/deployment/android),
[Android-Versionsregeln](https://developer.android.com/studio/publish/versioning).

Nur ein Store-Lauf verarbeitet gleichzeitig dieses Paket. Keine parallelen
manuellen Play-Uploads oder Console-Änderungen währenddessen ausführen: Google
verwirft dadurch laufende Edits. Wenn zwischen Reservierung und Upload eine andere
Version auftaucht, stoppt der Workflow; er überschreibt keinen fremden Release.
Ein erneuter Lauf reserviert eine neue Nummer. Für eine gezielte Wiederholung kann
der Store-Workflow auf `main` mit dem bereits veröffentlichten `release_tag` und
leerem `bootstrap_version` gestartet werden; dieselben Prüfungen bleiben aktiv. GitHub kann ältere wartende Läufe
durch einen neueren ersetzen; nötige Releases danach bewusst erneut starten.

Bei Fehlern vor dem Upload zuerst Konfiguration und CI prüfen. Bei einem Fehler
nach dem Commit `release.json` und den echten Play-Kanal prüfen: `storeUploaded:true`
mit `internalTrackVerified:false` bedeutet, dass Google den Commit bereits angenommen
hat, aber die anschließende Bestätigung fehlgeschlagen ist. Nicht blind nochmals
hochladen. Es gibt keinen automatischen Wechsel auf Produktion, kein Umgehen der
Google-Prüfung und kein automatisches Hinzufügen von Testern.

Für eine spätere öffentliche Veröffentlichung die dann gültigen Console-Anforderungen
separat erfüllen. Insbesondere gelten für bestimmte neuere persönliche
Entwicklerkonten zusätzliche geschlossene Tests; Internal Testing ersetzt sie nicht.
[Google erläutert diese zusätzlichen Voraussetzungen.](https://support.google.com/googleplay/android-developer/answer/14151465?hl=de)

## Lokal überprüfbar

Ohne Secrets und Netzwerk:

```sh
python3 -m unittest discover -s scripts/tests -v
python3 -m py_compile scripts/play_release.py
```

Die Unit-Tests simulieren API-Antworten und prüfen Versionsreservierung, Commit-/CI-
Sperren, Hashprüfung und die Begrenzung auf den internen Track. Sie belegen keinen
realen Google-Play-Upload. Actions, bundletool und alle Python-Abhängigkeiten sind
auf konkrete Versionen beziehungsweise Prüfsummen festgelegt. Die realen Nachweise
sind getrennt oben dokumentiert: Storeeinrichtung, signierter Bootstrap `0.3.0+13`,
manueller Upload und abgeschlossener interner Release sowie der gestartete automatische
Releaseauftrag `v0.3.1`. Die lokalen Unit-Tests ersetzen diese Nachweise nicht.
Der Weg bleibt: `vX.Y.Z`-GitHub-Release → geprüfter Workflow auf `main`
→ ausschließlich `internal`; es erfolgt keine öffentliche Veröffentlichung.
