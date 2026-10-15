# Mobile Bedienstruktur

Recherche- und Entscheidungsstand: 15. Oktober 2026. Vorbild ist ausdrücklich Logos Mobile
auf iPhone/Android-Telefon und iPad/Android-Tablet. Telegram dient als Vorbild für die
schwebende Hauptnavigation. Es werden keine Logos-/Telegram-Assets, Logos-Produktfakten
oder Logos-Funktionsnamen als eigene Akribos-Funktion übernommen.

## Quellen und Übertragung

| Offizielle Quelle | Belegtes Muster | Entscheidung für Akribos |
| --- | --- | --- |
| [Logos v53, 25.08.2026](https://www.logos.com/grow/release-august-2026/) | Fünf Hauptziele; erneuter Tap auf aktives Read öffnet die Panelübersicht; Study bündelt Ressourcen und Werkzeuge, More Einstellungen. | Lesen als stabiler Ausgangspunkt; zweiter Tap öffnet Ansichten. Häufige Ziele direkt erreichbar, weitere Funktionen unter Mehr. |
| [Logos Mobile Einstieg](https://support.logos.com/hc/en-us/articles/360035659011-Get-Started-with-Logos-Mobile) | Zuletzt gelesene Ressource beim Start; Kontextleiste mit Werktitel, Stelle, Suche und Panelmenü. | Lesen fortsetzen; Werk- und Stellenwahl sowie lokale Aktionen direkt am Pane. |
| [Logos Layouts, Abschnitt Mobile](https://support.logos.com/hc/en-us/articles/360016599631-Set-Up-Your-Workspace-with-Layouts) | Tabübersicht mit Plus, Split, zweiter Ressourcenauswahl und Linkgruppen; verschiebbarer Trenner; gespeicherte Layouts; zusätzliche Tablet-Vorlagen. | Vorschaukarten mit echten Werken und Stellen; Pane-Auswahl, Teilen und Schließen; zwei sichtbare Bereiche am Smartphone, vorhandene Layouts bis vier am Tablet. |
| [Logos Link Sets, Abschnitt Mobile](https://support.logos.com/hc/en-us/articles/360016827711-How-to-Link-Resources-to-Scroll-Together) | Gleich bezeichnete Gruppen navigieren synchron; zusätzlich einseitiges Follow only. | Vorhandene Akribos-Gruppen A–E sichtbar machen. Einseitiges Folgen ohne eigenes fachliches Modell nicht anbieten. |
| [Telegram Android, 09.02.2026](https://telegram.org/blog/crafting-android-design-and-more) | Neue Bottom Bar für direkten Wechsel der Hauptbereiche; abschaltbare Effekte. | Kompakte, schwebende Hauptnavigation mit eindeutigem aktiven Ziel und großen Touchflächen. |
| [Telegram iOS, 03.01.2026](https://telegram.org/blog/new-design-ai-summaries) | Liquid Glass mit Transparenz und Lichtbrechung; Effekte unter Power Saving steuerbar. | Opake Leiste ohne Blur für geringe Renderkosten; E-Ink zusätzlich ohne Bewegungsanimation. |

## Eigenständige Akribos-Regeln

Die Bottom Bar wechselt Hauptbereiche; die Ansichtenübersicht organisiert die geöffneten
Reader-Inhalte. Panelmenüs verändern nur das jeweilige Panel. Ressourcenwahl, Kopplung und
Suchkontext müssen sichtbar bleiben. Die bestehenden Arbeitsbereiche, Referenzen und
Versionsprüfungen bleiben die Datenbasis; ein UI-Wechsel darf keine Inhalte schließen oder
fremde Gerätestände überschreiben. Akribos behält seine geräteübergreifenden Arbeitsbereiche,
auch wenn Logos Layouts nur innerhalb derselben Geräteklasse synchronisiert.

Smartphones zeigen je nach Auswahl einen oder zwei echte Lesebereiche. Tablets nutzen die
vorhandenen Anordnungen und verschiebbaren Trenner. Bei schmalem Fenster darf der gewählte
Ausschnitt wechseln, ohne die gespeicherte Anordnung zu verlieren. Vor Eingaben werden
Dokumententwürfe regulär gesichert; Zurück und Hauptnavigation müssen vorhandene Konflikte
und ausstehende Änderungen beachten.

Abstände, Safe Areas, begrenzte Maximalbreite der Bottom Bar, Tastaturverhalten und
E-Ink-Darstellung sind Akribos-Entscheidungen. Die Telegram-Beiträge spezifizieren keine
verbindlichen Pixelmaße oder Tastaturregel. Akribos verwendet seine eigene Farbpalette,
Symbole und lokal gebündelten Schriften.

## Aktualitätsgrenzen und Bildherkunft

[Logos v54 vom 06.10.2026](https://www.logos.com/grow/release-october-2026/) macht Tabs und
Layouts optional und deaktiviert sie standardmäßig; gespeicherte Stände bleiben erhalten.
Akribos bietet den ausdrücklich gewünschten Studienmodus direkt an. Die Logos-Quellen
widersprechen sich bei der Tablet-Maximalzahl: Die Link-Set-Hilfe nennt vier, eine
[offizielle Mitarbeiterankündigung von 2022](https://community.logos.com/forums/topic/194580-feature-new-layout-options-on-tablet/)
sechs sichtbare Inhalte. Daraus wird keine neue Akribos-Sechs-Pane-Anforderung abgeleitet.

Die Logos-Hilfeseiten enthalten die Produktaufnahmen „Mobile Tab View“, „Layouts Tablet“
und die aktuelle Navigation; Telegram zeigt das jeweilige Design in den verlinkten
Release-Beiträgen. Diese externen Bilder sind ausschließlich Referenzquellen und werden
nicht in der App oder im Repository übernommen. Eigene Abbildungen müssen aus der echten
Akribos-Oberfläche stammen; tatsächliche Prüfstände stehen separat in VALIDATION.md.
