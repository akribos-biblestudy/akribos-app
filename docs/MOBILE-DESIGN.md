# Mobile Bedienstruktur

Recherche- und Entscheidungsstand: 15. Oktober 2026. Vorbild ist ausdrücklich Logos Mobile
auf iPhone/Android-Telefon und iPad/Android-Tablet. Telegram dient als Vorbild für die
schwebende Hauptnavigation. Es werden keine Logos-/Telegram-Assets, Logos-Produktfakten
oder Logos-Funktionsnamen als eigene Akribos-Funktion übernommen.

## Quellen und Übertragung

| Offizielle Quelle | Belegtes Muster | Entscheidung für Akribos |
| --- | --- | --- |
| [Logos v53, 25.08.2026](https://www.logos.com/grow/release-august-2026/) | Fünf Hauptziele; erneuter Tap auf aktives Read öffnet die Panelübersicht; Study bündelt Ressourcen und Werkzeuge, More Einstellungen. | Lesen als stabiler Ausgangspunkt; zweiter Tap öffnet Ansichten. Häufige Ziele direkt erreichbar, weitere Funktionen unter Mehr. |
| [Logos Mobile Einstieg](https://support.logos.com/hc/en-us/articles/360035659011-Get-Started-with-Logos-Mobile) | Zuletzt gelesene Ressource beim Start; Kontextleiste mit Werktitel, Stelle, Suche und Panelmenü. | Lesen fortsetzen; Werk- und Stellenwahl sowie lokale Aktionen am Ressourcentab; Werksuche im Tabmenü. |
| [Logos Layouts, Abschnitt Mobile](https://support.logos.com/hc/en-us/articles/360016599631-Set-Up-Your-Workspace-with-Layouts) | Tabübersicht mit Plus, Split, zweiter Ressourcenauswahl und Linkgruppen; verschiebbarer Trenner; gespeicherte Layouts; zusätzliche Tablet-Vorlagen. | Vorschaukarten mit echten Werken und Stellen; eine flache Tabfolge auf Telefon und Tablet. Tabs werden ausschließlich lokal pro Gerät gespeichert; Browser-Arbeitsbereiche und Layouteditor werden nicht übernommen. Eine optionale Notizenspalte ergänzt die Bibel auf breiten Fenstern. |
| [Logos Link Sets, Abschnitt Mobile](https://support.logos.com/hc/en-us/articles/360016827711-How-to-Link-Resources-to-Scroll-Together) | Gleich bezeichnete Gruppen navigieren synchron; zusätzlich einseitiges Follow only. | Vorhandene Akribos-Gruppen A–E sichtbar machen. Einseitiges Folgen ohne eigenes fachliches Modell nicht anbieten. |
| [Telegram Android, 09.02.2026](https://telegram.org/blog/crafting-android-design-and-more) | Neue Bottom Bar für direkten Wechsel der Hauptbereiche; abschaltbare Effekte. | Kompakte, schwebende Hauptnavigation mit eindeutigem aktiven Ziel und großen Touchflächen. |
| [Telegram iOS, 03.01.2026](https://telegram.org/blog/new-design-ai-summaries) | Liquid Glass mit Transparenz und Lichtbrechung; Effekte unter Power Saving steuerbar. | Opake Leiste ohne Blur für geringe Renderkosten; E-Ink zusätzlich ohne Bewegungsanimation. |

## Eigenständige Akribos-Regeln

Die Bottom Bar wechselt Hauptbereiche; die Ansichtenübersicht organisiert die geöffneten
Reader-Inhalte. Tabmenüs verändern nur den jeweiligen Ressourcentab. Ressourcenwahl, Kopplung und
Suchkontext müssen sichtbar bleiben. Die App speichert ihre Tabs, Referenzen und Suchen lokal,
getrennt nach Server und Konto. Sie übernimmt keine Browser-Arbeitsbereiche und verändert weder
deren Tabs noch die Tabs eines anderen App-Geräts. Eine Verwaltung benannter Arbeitsbereiche
ist nicht Bestandteil der App.

Smartphones und Tablets zeigen dieselbe flache Folge aller
geöffneten Ressourcen. Wischen und Tabkarten erreichen jedes geöffnete Werk. Ein Fensterwechsel
ordnet die lokalen Tabs nicht um. Die interne Readerstruktur erscheint nicht als zusätzliche
Kachelhierarchie. In den Einstellungen lässt sich eine Notizenspalte für breite
Fenster aktivieren und links oder rechts platzieren. Schmale Fenster behalten einen Lesebereich.
Tabkarten lassen sich durch langes Drücken und Ziehen umordnen. Ein Layouteditor und verschiebbare
Trenner entfallen. Zurück und Hauptnavigation beachten
vorhandene Konflikte und sichern ausstehende Dokument- und Readeränderungen.

Beim Öffnen zeigt die Hauptnavigation „Suche“ das aktuell im Reader gewählte Werk samt Titel.
Nach einem Werkwechsel wird der bisherige Suchbegriff für dieses Werk erneut gesucht; Buchfilter
und Ergebnisseite werden zurückgesetzt. Beim selben Werk bleibt der Suchstand erhalten. Während
des Lesens wird keine Hintergrundsuche ausgeführt; das Werk wird ausschließlich im Reader gewählt. Die
Werksuche im Reader ist über das Tabmenü erreichbar; neben dem Stellenfeld gibt es keinen
zusätzlichen Suchbutton. „Notizen“ startet immer in der reinen Notizbibliothek; Ausarbeitungen
haben dort einen eigenen Wechsel. Import und Vorlagen entfallen, Boardspalten sind nur lesbar;
Dokumente können weiterhin zwischen ihnen verschoben werden.

„Mehr“ enthält weiterhin „Über Akribos“, aber keine Einträge für Datenschutz, Impressum oder
einen manuellen Linkdialog. Die Hilfe ist vorerst ein lokaler Platzhalter. App-spezifische
Anleitungen entstehen nach Fertigstellung, siehe [TODO.md](TODO.md).

Abstände, Safe Areas, begrenzte Maximalbreite der Bottom Bar, Tastaturverhalten und
E-Ink-Darstellung sind Akribos-Entscheidungen. Die Telegram-Beiträge spezifizieren keine
verbindlichen Pixelmaße oder Tastaturregel. Akribos verwendet seine eigene Farbpalette,
Symbole und lokal gebündelten Schriften.

## Wortstudie und Tagdarstellung

Wortklicks öffnen ausschließlich Lexikoninhalte als fast bildschirmhohen Dialog von unten.
Der Griff, eine sichtbare Schließen-Schaltfläche und die System-Zurück-Geste führen zurück
zum unveränderten Bibeltext. Der Dialog nutzt lesende API-Aufrufe statt einen neuen
Ressourcentab anzulegen. Andere Werke behalten die normale Tabnavigation; ein bewusst
geöffnetes Lexikon kann ebenfalls als dauerhafter Ressourcentab bestehen bleiben.

A–E nutzen die Web-Gruppenfarben aus `ReaderTabToolbar.svelte`: A `#b9683f`, B `#55759b`,
C `#60836d`, D `#776b91`, E `#9a6572`. Buchstaben ergänzen die Farben. Die Notizliste zeigt
keine globale Tagwolke; Filter und Tagbearbeitung bleiben gezielt erreichbar.

Langes Drücken wählt einen Vers; weitere Berührungen fügen Verse hinzu oder entfernen sie aus
der Auswahl. Die unterstrichene Auswahl erhält eine vertikale Symbolleiste für Markierung,
Sammlung, Notiz und Teilen. Die Versnummer bietet im Versmenü zusätzlich einen zugänglichen
Einstieg in die Auswahl. Notizen verknüpfen die tatsächlich gewählten Stellen einzeln;
ein Fehler zeigt den bestätigten Teil und lässt die übrigen Stellen ausgewählt.

## Buch- und Kapitelauswahl

Die Buchliste steht links, die Kapitel des ausgewählten Buchs stehen rechts. Beide
Listen scrollen vertikal und unabhängig. Rechts sind alle verfügbaren Kapitel in
einer Liste erreichbar. Beim Öffnen stehen das aktuelle Buch und das aktuelle Kapitel
mittig in ihrem jeweiligen Scrollbereich. Dafür haben die Listen oben und unten
genug Platz, auch für ihre ersten und letzten Einträge. Beim Scrollen bleibt die
Auswahl stehen. Ein Buchwechsel aktualisiert die rechte Liste. Das Antippen eines
Kapitels öffnet die Stelle.

Die Buchliste zeigt volle Namen und acht kanonische Gruppen. Dezente Farbstreifen
und Flächen unterscheiden die Gruppen in Hell und Dunkel. Gruppenüberschriften und
die Umrandung der Auswahl machen dieselben Informationen im E-Ink-Modus sichtbar.
CSV-Bibel war eine visuelle Referenz. Olive Tree beschreibt Kategorienfarben im
Stellenwähler, JW Library dokumentiert acht Buchgruppen. Akribos verwendet dazu
eigene Farben und Listen. [CSV-Bibel](https://www.csv-bibel.de/bibel/1-mose-1) ·
[Olive-Tree-Hilfe](https://help.olivetree.com/hc/en-us/articles/4404188579725-Using-Bibles) ·
[JW-Library-Hilfe](https://www.jw.org/en/online-help/jw-library/apple/faqs/)

Die Direkteingabe bleibt im Online-Reader verfügbar. Der Offline-Reader verwendet
dieselbe Listenansicht mit den heruntergeladenen Kapiteln des ausgewählten Werks.
In sehr schmalen Fenstern mit großer Schrift nutzt die Leiste AT und NT.
Screenreader lesen die ausgeschriebenen Testamentnamen. Die vollen Buchnamen können
umbrechen. Im niedrigen Querformat teilt sich die Direkteingabe die Zeile mit dem
Schließen-Button, damit die ausgewählten Einträge sichtbar bleiben.

| Aufnahme | Prüfpunkt |
| --- | --- |
| [Bisheriges Kapitelraster](screenshots/passage-picker/vorher-kapitelraster.png) | Psalm 118 im vorherigen Bereich 85–126 |
| [Smartphone](screenshots/passage-picker/smartphone-psalm-118.png) | Psalmen und 118 beim Öffnen mittig, Psalm 119 direkt darunter |
| [Tablet, Dunkel](screenshots/passage-picker/tablet-psalm-150-dunkel.png) | Psalm 150 am unteren Listenende mittig |
| [320 dp, 200 % Schrift, E-Ink](screenshots/passage-picker/schmal-eink-grosse-schrift.png) | Umbruch von „2. Thessalonicher“ und sichtbare Auswahlbegrenzungen |
| [640 × 360 dp, 200 % Schrift](screenshots/passage-picker/querformat-grosse-schrift.png) | Im Querformat bleiben Buch und Kapitel mittig und antippbar |

Die Aufnahmen stammen vom Flutter-Widget mit Testnavigation. Widget-Tests vergleichen
die Mittelpunkte der ausgewählten Zeilen mit ihren Scrollbereichen und prüfen
Psalm 1, 118 und 150, lückenhafte Werke, das Querformat mit Tastatur und die Öffnung
direkt nach einem Kapitelwechsel durch Scrollen, online und offline.

## Aktualitätsgrenzen und Bildherkunft

[Logos v54 vom 06.10.2026](https://www.logos.com/grow/release-october-2026/) macht Tabs und
Layouts optional und deaktiviert sie standardmäßig; gespeicherte Stände bleiben erhalten.
Akribos bietet die Tabübersicht direkt an, übernimmt jedoch keine Split- oder Layoutbedienung. Die Logos-Quellen
widersprechen sich bei der Tablet-Maximalzahl: Die Link-Set-Hilfe nennt vier, eine
[offizielle Mitarbeiterankündigung von 2022](https://community.logos.com/forums/topic/194580-feature-new-layout-options-on-tablet/)
sechs sichtbare Inhalte. Daraus wird keine neue Akribos-Sechs-Pane-Anforderung abgeleitet.

Die Logos-Hilfeseiten enthalten die Produktaufnahmen „Mobile Tab View“, „Layouts Tablet“
und die aktuelle Navigation; Telegram zeigt das jeweilige Design in den verlinkten
Release-Beiträgen. Diese externen Bilder sind ausschließlich Referenzquellen und werden
nicht in der App oder im Repository übernommen. Eigene Abbildungen müssen aus der echten
Akribos-Oberfläche stammen; tatsächliche Prüfstände stehen separat in VALIDATION.md.
