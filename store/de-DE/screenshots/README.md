# Android-Aufnahmen für Google Play

Vier echte Aufnahmen der installierten Akribos-App `0.2.9+12` vom **16. Oktober 2026**
(Zeitzone Europe/Berlin), aufgenommen auf einem **Pixel 9 Pro mit Android 17 / SDK 37**.
Quelle: `adb exec-out screencap -p`; Produktionsserver `https://akribos.de`.
Installierte APK: SHA-256 `78b3b812f83cad8ff8913bd3b52151a0c3a888897565100776c84626b999042d`.

Die vier Originale unter `originals/` sind unveränderte, vollständige PNG-Dateien mit
1280 × 2856 Pixeln einschließlich der echten Systemleisten. Die Auswahl wurde vor
Übernahme visuell freigegeben. Sie zeigt öffentlichen Bibeltext und native Bedienelemente,
keine privaten Notizen, Namen, Kontaktdaten oder Zugangsdaten. Für die Suchaufnahme wurde
ausschließlich der allgemeine Suchbegriff „Gnade“ verwendet und anschließend entfernt.
Die ursprüngliche Lesestelle und Darstellung blieben erhalten. Die zusätzliche
Tabübersicht wurde nicht in das Store-Paket übernommen.

## Präsentation und Export

Die Originale überschreiten mit ihrem Seitenverhältnis die Google-Play-Grenze von
höchstens 2:1. Die vier HTML-Seiten unter `pages/` präsentieren deshalb das vollständige
Original auf einer schlichten dunklen Fläche (`#171e18`). Diese Fläche ist eine
HTML/CSS-Präsentationsseite, kein Bestandteil der App-Oberfläche.

Die finalen Store-Dateien liegen unter `../images/phone-screenshots/` und sind
Chromium-Webseitenaufnahmen mit **1620 × 2880 Pixeln (9:16), 8-Bit-RGB ohne Alphakanal**.
Jedes Original liegt unvergrößert und unverkleinert bei **x=170, y=12**, mit exakt
1280 × 2856 Bildpunkten. Es gibt keine Beschneidung, Bitmapretusche, Filter, Transformation,
zusätzlichen Texte, erfundene Bedienelemente oder künstlichen Geräterahmen.

Reproduzieren vom App-Repository aus:

```sh
node store/de-DE/screenshots/export.mjs
```

Das Skript verwendet vorhandenes Playwright aus dem App-Repository oder dem benachbarten
Web-Repository `../akribos`; alternativ kann `PLAYWRIGHT_MODULE` auf die vorhandene
Playwright-Installation zeigen. Es verändert keine Produktabhängigkeiten und benötigt
keine ADB-Verbindung. Browser und Prüfergebnisse stehen in `export-manifest.json`;
Aufnahmeherkunft und Alternativtexte stehen in `captures.json`.

Der Export prüft Original-Hashes, natürliche Bildmaße, exakte CSS-Position, Viewport bei
Geräteskalierung 1, PNG-Maße/Farbtyp, 9:16 und vollständige Deckkraft. Ein anschließender
rein lesender Vergleich aller dekodierten Farbkanäle des eingebetteten Bildbereichs mit
dem Original bestätigt **null Abweichungen** bei allen vier Dateien. Die zur Prüfung
verwendeten Canvas-Flächen erzeugen keine Bilddateien; die Ausgabe stammt ausschließlich
aus Playwrights Browser-Screenshot. Eine technische Prüfung ersetzt keine Veröffentlichung:
Diese Dateien wurden hier nur lokal erzeugt, nicht zu Google Play hochgeladen.

## Dateien, Alternativtexte und SHA-256

Die Dateinummern entsprechen den ursprünglichen Aufnahmen; die ausgelassene Nummer 03
ist beabsichtigt. Alle Alternativtexte sind kürzer als 140 Zeichen.

### 01-reader.png

- Alternativtext: Bibeltext in Akribos mit Kapitelüberschrift, Versnummern und Fließtext in der dunklen Leseansicht.
- Original: `originals/01-reader.png`
- Store-Datei: `../images/phone-screenshots/01-reader.png`
- Original-SHA-256: `ccc1e8f48a757a545f6551f82e9cc3378fad75084a65238d946387f34d68398d`
- Store-SHA-256: `eebf19eb0498b1b5e113d149fa51c863d69c3f29ac3059cc41f42d0f51b72b69`

### 02-verse-menu.png

- Alternativtext: Kompaktes Versmenü in Akribos mit den Aktionen Markieren, Sammlungen, Notiz und Teilen.
- Original: `originals/02-verse-menu.png`
- Store-Datei: `../images/phone-screenshots/02-verse-menu.png`
- Original-SHA-256: `c043b2362b8827e029a9b14369c83b64b99382eda24a304befb2ad4a0b4ec346`
- Store-SHA-256: `a614cc40d427f96108837d23afd0744c442ae87761f5132344ebd47e0de8c94b`

### 04-settings.png

- Alternativtext: Akribos-Einstellungen für Versweise oder Fließtext, Erscheinungsbild, E-Ink-Modus und Leseschriftgröße.
- Original: `originals/04-settings.png`
- Store-Datei: `../images/phone-screenshots/04-settings.png`
- Original-SHA-256: `bb858bb43a56177c57b33076b6ad79225ddda69634c4f1c7fc6d101946b4a17a`
- Store-SHA-256: `f2f887fd154896a48685e14d0085f59118a7a70dc1994db389b725c26025bec8`

### 05-search-grace.png

- Alternativtext: Akribos-Bibelsuche nach Gnade mit Fundstellen in der Schlachter 2000.
- Original: `originals/05-search-grace.png`
- Store-Datei: `../images/phone-screenshots/05-search-grace.png`
- Original-SHA-256: `4e4de7fd61ed11b612d909df7d704a8e7e02ed0a7990a471ceaa41c366736d29`
- Store-SHA-256: `c0be8facd2f2950e4b8c933564b35cc9b35248bebcf0dde5c1c743d7902f9cb7`
