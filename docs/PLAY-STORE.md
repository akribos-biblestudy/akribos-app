# Android über Google Play veröffentlichen

Stand: 15. Oktober 2026. Dieses Repository veröffentlicht zunächst ausschließlich
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
Schlüssel; dieser Weg und seine Version `0.2.7+10` bleiben getrennt.

## 1. GitHub vorbereiten

Das private Repository liegt unter
[akribos-biblestudy/akribos-app](https://github.com/akribos-biblestudy/akribos-app).
Die Dateien müssen auf `main` veröffentlicht sein, bevor Actions ausgeführt werden
können. Danach unter **Actions → Flutter CI** einen erfolgreichen Lauf des aktuellen
`main`-Commits abwarten.

Das Environment `android-play-internal` ist bereits eingerichtet und seine API-
Konfiguration geprüft: exakt eine erlaubte Deployment-Regel, Branch `main`, keine
Tags; Store-Secrets sind noch nicht hinterlegt. Die Variablen
`PLAY_BOOTSTRAP_ALLOWED=false` und `PLAY_VERSION_CODE_FLOOR=10` sind bereits gesetzt.
Unter **Settings → Environments**
diesen Zustand vor dem Eintragen der Secrets kontrollieren. Diese Branchbindung
ist eine Voraussetzung, keine optionale Empfehlung. Ohne sie keine Store-Secrets
hinterlegen und nicht ersatzweise Repository-Secrets verwenden.

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

Die aktuell von der Console verlangten Angaben ausfüllen: Kontakt, Store-Eintrag,
Grafiken, App-Zugriff für Prüfer, Altersfreigabe, Zielgruppe und App-Inhalte. Nur
freigegebene Bilder ohne private Notizen, Kontodaten oder Zugangscodes verwenden.
Eine spätere öffentliche Veröffentlichung hat zusätzliche Anforderungen und wird
von diesem Workflow nicht ausgelöst.
[Google beschreibt Konto und Einstieg in die Console.](https://support.google.com/googleplay/android-developer/answer/6112435?hl=de)

Für die Datenschutzerklärung existiert
[akribos.de/datenschutz](https://akribos.de/datenschutz). Vor einem öffentlichen
Storeeintrag muss ihr Inhalt auch den tatsächlichen nativen Betrieb abdecken,
insbesondere Anmeldung, serverseitige Notizen und lokale verschlüsselte Tabs. Die
Datensicherheitsangaben aus den tatsächlichen Datenflüssen ableiten, einschließlich
Serverzugriffen und Bibliotheken; nicht pauschal „keine Daten“ auswählen. Ausschließlich
interne Tests sind laut Google vom Datensicherheitsformular ausgenommen. Vor einem
Wechsel zu anderen Tracks sind die entsprechenden Angaben nachzuholen.
[Offizielle Hinweise zur Datensicherheit.](https://support.google.com/googleplay/android-developer/answer/10787469?hl=de)

## 3. Uploadschlüssel und Play App Signing einrichten

Einen **eigenen Uploadschlüssel für den Store** außerhalb des Repositorys anlegen,
zum Beispiel über Android Studios **Generate Signed Bundle / APK → Create new**.
Diesen Schritt führt der Kontoinhaber bewusst aus; weder Workflow noch dieses
Repository erzeugen Schlüssel. Keystore, Alias, Store-Passwort und Schlüsselpasswort
in der eigenen sicheren Ablage sichern. Den vorhandenen Debugschlüssel nicht verwenden.

Bei der ersten Veröffentlichung **Play App Signing** einrichten. Google signiert
die ausgelieferten APKs mit dem App-Signaturschlüssel; das AAB wird vorher mit deinem
Uploadschlüssel signiert. Diese Zertifikate haben unterschiedliche Aufgaben.
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

Unter **Settings → Environments → android-play-internal** diese Werte anlegen:

| Environment Secret | Inhalt |
| --- | --- |
| `ANDROID_UPLOAD_KEYSTORE_BASE64` | Base64-Inhalt des bestehenden Store-Uploadkeystores |
| `ANDROID_UPLOAD_STORE_PASSWORD` | Passwort des Keystores |
| `ANDROID_UPLOAD_KEY_PASSWORD` | Passwort des privaten Schlüssels |
| `ANDROID_UPLOAD_KEY_ALIAS` | Alias dieses Schlüssels |
| `PLAY_SERVICE_ACCOUNT_JSON` | Vollständiges JSON des Dienstkontos aus Schritt 7; für den ersten Bootstrap noch nicht erforderlich |

| Environment Variable | Anfangswert / Bedeutung |
| --- | --- |
| `ANDROID_UPLOAD_CERT_SHA256` | Öffentlicher SHA-256-Fingerabdruck aus Schritt 3, mit oder ohne Doppelpunkte |
| `PLAY_VERSION_CODE_FLOOR` | `10` bei der neuen Akribos-App; bei bestehender Play-Historie mindestens die höchste jemals verwendete Versionsnummer |
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
Play Internal Testing → Run workflow** den Branch `main` wählen und beispielsweise
`bootstrap_version: 0.3.0` eingeben und `release_tag` leer lassen. Nur für eine App verwenden, deren erstes Bundle
noch manuell hochzuladen ist. Der Bootstrap fragt die noch nicht verfügbare Play-App
nicht per API ab; der bestätigte Mindeststand kommt aus Schritt 4.

Der Lauf reserviert eine neue Versionsnummer, baut für `https://akribos.de`, signiert
das AAB mit dem Uploadschlüssel und prüft Signatur, Paketname, Version und
Nicht-Debug-Build. Unter **Artifacts** das Paket `akribos-play-VERSION-NUMMER`
herunterladen. Es enthält `.aab`, `SHA256SUMS` und `release.json` mit
`storeUploaded: false`. Ein AAB wird nicht direkt auf das Pixel installiert.

## 6. Einmalig manuell nach Internal Testing hochladen

In der Play Console unter **Testen und veröffentlichen → Testen → Interner Test**
einen Release erstellen, das AAB aus Schritt 5 hochladen, Play App Signing
abschließen, Hinweise prüfen und den internen Release freigeben. Dies ist die
notwendige erste manuelle Einrichtung: Die Publishing API kann nur eine bereits
angelegte App mit einem zuvor hochgeladenen Paket bearbeiten; sie erledigt weder
diesen Einstieg noch rechtliche Einwilligungen.
[Google dokumentiert diese Grenze der Publishing API.](https://developers.google.com/android-publisher/edits)

Unter **Tester** die gewünschten Google-Konten beziehungsweise eine Google-Gruppe
eintragen und den dort angezeigten Testbeitrittslink teilen. Jeder Tester muss mit
dem freigegebenen Google-Konto beitreten und über Google Play installieren. Der
interne Test unterstützt bis zu 100 Tester; die Verfügbarkeit kann nach der
Freigabe etwas dauern.
[Anleitung zu internen Tests.](https://support.google.com/googleplay/android-developer/answer/9845334?hl=de)

Danach `PLAY_BOOTSTRAP_ALLOWED=false` setzen. Unter **App-Integrität / App-Signierung**
den SHA-256-Wert des **App-Signaturzertifikats** kopieren. Diesen zusätzlich in
`../akribos/static/.well-known/assetlinks.json` für `de.akribos.app` eintragen und
den Server regulär veröffentlichen, damit auch Play-Installationen Akribos-Links
öffnen. Den bisherigen Pixel-Fingerprint erhalten; der Upload-Fingerprint ersetzt
hier nicht den App-Signatur-Fingerprint.
[Android App Links prüfen die Signatur der installierten App.](https://developer.android.com/training/app-links/configure-assetlinks)

## 7. Google-Play-API freigeben

In einem eigenen Google-Cloud-Projekt die **Google Play Android Developer API**
aktivieren und ein dediziertes Dienstkonto anlegen. Dessen E-Mail-Adresse in der
Play Console unter **Nutzer und Berechtigungen** hinzufügen und Zugriff ausschließlich
auf Akribos erteilen: App-Informationen lesen sowie Releases für Test-Tracks erstellen
und veröffentlichen. Keine Produktions-Veröffentlichung oder Finanzverwaltung
freigeben. Die jeweils aktuellen Bezeichnungen in der Console prüfen.

Einen Dienstkonto-JSON-Schlüssel erstellen, sicher ablegen und als
`PLAY_SERVICE_ACCOUNT_JSON` in das GitHub-Environment übernehmen. Falls eure
Organisationsrichtlinie JSON-Schlüssel sperrt, ist zunächst eine bewusst eingerichtete
föderierte Authentifizierung erforderlich; diese Richtlinie nicht umgehen. Der
vorbereitete Workflow verwendet Dienstkonto-JSON, keine OAuth-Zugangsdaten eines
privaten Nutzerkontos.
[Offizielle Einrichtung von API und Dienstkonto.](https://developers.google.com/android-publisher/getting_started)

## 8. Weitere Versionen automatisch veröffentlichen

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
auf konkrete Versionen beziehungsweise Prüfsummen festgelegt. Storezugang,
Signieridentität und die erste echte Veröffentlichung werden erst nach Einrichtung
mit den eigenen Konten geprüft.
