# Google-Play-Grafiken · Deutsch

Stand: 16. Oktober 2026. Die PNG-Dateien sind die Upload-Dateien; SVG, Buildskript und
Manifest dienen der Bearbeitung und reproduzierbaren Prüfung. Noch nicht hochgeladen.

| Datei | Format | Verwendung |
| --- | --- | --- |
| `icon.png` | 512 × 512, PNG RGBA, 8 Bit/Kanal, sRGB | Play-Store-Appsymbol |
| `feature-graphic.png` | 1024 × 500, PNG RGB, 8 Bit/Kanal, sRGB, ohne Alphakanal | Feature-Grafik |

## Herkunft und Gestaltung

- Das Appsymbol verwendet ausschließlich das bestehende `assets/brand/icon.png`.
  Transparenter Außenabstand wird entfernt, das Zeichen proportional verkleinert und
  auf einen vollflächigen papierfarbenen Hintergrund gesetzt. Zeichenform und Farbe
  bleiben unverändert. Keine vorgerundeten Ecken und kein äußerer Schatten.
- Die Feature-Grafik verwendet die vorhandene `assets/brand/wordmark.png` ohne
  Farb-/Formänderung. `feature-graphic.svg` enthält eine einfache eigene
  Buchillustration und den redaktionellen Text „Die Bibel. Genau betrachtet.“ sowie
  „Lesen · Vergleichen · Notieren“. Sie stellt keine App-Oberfläche dar.
- Farben stammen aus `lib/theme/akribos_theme.dart`: Papier, Dunkelgrün und die
  vorhandenen Grüntöne. Text verwendet ausschließlich die gebündelte OFL-Schrift
  Akribos Text (`assets/fonts/`, Lizenz `OFL-Akribos-Text.txt`).
- Keine privaten Inhalte, künstlichen Screenshots, externen Bildmotive,
  Bewertungs-/Rankingangaben, Preisversprechen oder Store-Badges.

## Neu exportieren

Voraussetzungen: Python 3 (nur Standardbibliothek), ImageMagick 7, librsvg
(`rsvg-convert`) und Fontconfig (`fc-match`). Keine Netzwerkzugriffe nötig.

```sh
python3 store/de-DE/images/build.py
```

Der Build liest ausschließlich die vorhandenen Markenassets und Schriften, rendert
die SVG-Quelle und prüft PNG-Abmessungen, Farbart und Icon-Dateigröße. Der eigene
temporäre Fontconfig-Pfad verhindert einen unbemerkten Ersatz der Leseschrift.
`build-manifest.json` dokumentiert Quell-/Ergebnis-Hashes und Rendererversionen;
andere Rendererversionen können geringfügig andere Antialiasing-Pixel erzeugen.

## Geprüfte Google-Vorgaben

Am 16. Oktober 2026 anhand der offiziellen Seiten geprüft:

- [Vorschau-Assets](https://support.google.com/googleplay/android-developer/answer/9866151?hl=en):
  Icon 512 × 512 als 32-Bit-PNG, maximal 1024 KB; Feature-Grafik 1024 × 500 als
  24-Bit-PNG ohne Alpha. Die Wortmarke bleibt in der Feature-Grafik zurückhaltend,
  da Google eine prominente Wiederholung des Appsymbols vermeiden empfiehlt.
- [Icon-Gestaltung](https://developer.android.com/distribute/google-play/resources/icon-design-specifications):
  sRGB, volle quadratische Fläche, ohne selbst hinzugefügte äußere Schatten oder
  abgerundete Ecken. Google Play setzt Maskierung und Schatten selbst.

Die lokale Format- und Sichtprüfung ersetzt keine Annahmeprüfung der Play Console.
