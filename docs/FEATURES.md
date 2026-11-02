# Umfang der nativen Nutzeroberfläche

Stand: 17. Oktober 2026. Zielsysteme sind Android und iOS auf Smartphones und Tablets;
vorerst wird nur Android veröffentlicht. Alle Einträge beziehen sich auf normale Nutzer
und auf deren aktuelle serverseitige Leserechte. Der tatsächliche Prüfstand steht in
[VALIDATION.md](VALIDATION.md).

| Bereich | Native Umsetzung |
| --- | --- |
| Lesen | Stellenwahl über AT-/NT-Buchkürzelraster und verfügbare Kapitel des aktuellen Werks sowie Direkteingabe, Bibeln, Kommentare, Lexika, Parallelstellen, strukturierte Verse, unter Mehr → Einstellungen umschaltbar zwischen Versweise und Fließtext im Blocksatz (Standard), skalierende Kommentar- und Lexikontexte, skalierende Überschriften, Fußnoten, Strong-Wörter und Quellenangaben |
| Tabs | Eine flache Folge aller Ressourcen auf jeder Fensterbreite, visuelle Tabkarten per langem Drücken verschiebbar, zusätzliche Plus-Karte, Hinzufügen/Schließen, A–E-Kopplung mit Web-Farben und Buchstaben, unabhängige Tabs |
| Lokaler Readerstand | Tabs, Lesestellen, Tabgruppen, Suchen und Notizfilter pro Gerät, Server und Konto im sicheren Speicher; eigener Gaststand, Wiederherstellung bei Neustart |
| Offline | Ausdrücklich vom Server für Offline freigegebene Bibeln, Kommentare, Parallelstellen und Lexika können pro Konto verschlüsselt auf dem Gerät gespeichert und ohne Netz gelesen werden. Schreibende Aktionen bleiben online. Ein Widerruf wird bei der nächsten erfolgreichen Rechteprüfung wirksam. |
| Unabhängigkeit | Keine Übernahme oder Änderung von Browser-Arbeitsbereichen, keine Synchronisierung der Tabs zwischen App-Geräten, keine Workspace-Verwaltung |
| Telefon/Tablet | Floating-Hauptnavigation, Wischwechsel zwischen allen Werken, optionale Notizenspalte zum aktuellen Kapitel mit Seitenwechsel in Einstellungen, automatischer Einspaltenrückfall bei wenig Platz, Fensterwechsel ohne Umordnung der lokalen Tabs |
| E-Ink | Kontrastreiche helle Darstellung, reduzierte Animationen, fortlaufendes Scrollen, erkennbare Markierungen ohne Farberkennung |
| Suche | Wort-/Phrasensuche, Vorschläge, Buchfilter und Seiten; beim Öffnen übernimmt die Hauptnavigation das aktuelle Reader-Werk samt Titel und sucht bei geändertem Werk den bisherigen Begriff erneut; lokale Werksuche im Tabmenü |
| Wortstudium | Herunterwischbarer Lexikon-Dialog bei Wortklick, Strong-Artikel, Quellwort/Position, Morphologie, Übersetzungsformen, Häufigkeiten und Fundstellen |
| Markierungen | Neue Ganzversmarkierungen mit durchgehenden, leicht unregelmäßigen Markerstrichen pro Zeile; vorhandene Versbereichs-/Wortmarkierungen bleiben sichtbar und gezielt löschbar; vier einzeilige Versaktionen; Kopieren über den System-Teilen-Dialog, Übersichten, eigene Stilnamen und Farben mit sichtbarer Farbkachel und Textvorschau in den Einstellungen |
| Notizen | Eigener Einstieg `/notes?kind=note`, standardmäßig auf das aktuelle Lesekapitel gefiltert und direkt abschaltbar, interner Wechsel zu Ausarbeitungen, Bibliothek ohne Tagwolke, gezielte Tagfilter, Stellen, Papierkorb/Wiederherstellung, verknüpfte Sammlungen und Rückverweise |
| Editor | Gemeinsamer Akribos-Webeditor in einer System-WebView mit Auswahlformatierung, Tabellen, Fußnoten und schreibgeschütztem Lesemodus, Markdown-Speicherung, revisionstreues Autosave, Konfliktvergleich, Entwurfswiederherstellung, Bibelzitate und Anhänge |
| Dokumentdateien | Serverseitige Exportformate über den nativen Teilen-Dialog; kein mobiler Import |
| Ausarbeitungen | Board mit vorhandenen, nicht bearbeitbaren Spalten; Dokumente zwischen Spalten verschieben, Metadaten und Durchführungen; Wechsel zwischen Notiz und Ausarbeitung |
| Sammlungen | Anlegen/Umbenennen/Löschen, Stellen hinzufügen/entfernen, Freigabelinks, Mitglieder/Einladungen, Verlassen, Kommentare/Antworten/Reaktionen |
| Öffentlich Geteiltes | Öffentliche Sammlungen und veröffentlichte Notizen lesen, Links teilen/öffnen; Links erweitern keine Leserechte |
| Konto | E-Mail-Code, Passwort mit System-Autofill, erhaltene gültige Anmeldung bei App-Updates, Bestätigungs-/Rücksetzlinks, Profil, Passwort und Abmelden über das Personen-Icon |
| Einstellungen | Darstellung, E-Ink, Textdarstellung; nach Anmeldung Leseschrift, Standardbibel und Markierungsfarben; Schrift und Stiländerungen aktualisieren den Reader bei gleicher Lesestelle |
| Mehr | Sammlungen, Einstellungen, Hilfeplatzhalter und Über Akribos mit Open-Source-Lizenzen |
| Version und Updates | Tatsächlich installierte Version/Build in Einstellungen und Über Akribos; automatische sowie manuelle Store-Prüfung, schließbarer Hinweis und freiwilliges Öffnen des Stores nach Speicherung; Google Play und öffentliche App-Store-Listung |
| Hilfe | Lokaler Platzhalter; eigenständige App-Anleitungen folgen nach Fertigstellung, siehe [TODO.md](TODO.md) |

## Unterschiede zur Weboberfläche

Die Bedienung wird an das Gerät angepasst. Der Dokumenteditor nutzt denselben visuellen
Editor und dieselben Markdown-Konverter wie die Webanwendung. Formatierungsaktionen
erscheinen an der Textauswahl. Ein schreibgeschützter Lesemodus eignet sich für Predigtskripte. Kommentare werden in die vom bestehenden Server unterstützte
Formatierung umgewandelt; vorhandenes HTML bleibt ohne Bearbeitung erhalten. Die Webhilfe
und die Web-Einführungstour mit Popovern werden nicht als App-Hilfe übernommen.

Import, Vorlagenverwaltung, Vorlagenwahl und die Bearbeitung von Boardspalten sind nicht
Teil der mobilen Oberfläche. Alte direkte Import-/Vorlagenpfade öffnen die zugehörige
Notiz-/Ausarbeitungsübersicht. Die Hauptnavigation „Notizen“ zeigt ausschließlich Notizen;
Ausarbeitungen sind über den internen Wechsel auf der Notizen-Seite erreichbar.

„Mehr“ enthält keine Einträge für Datenschutz, Impressum oder einen manuellen Linkdialog.
„Über Akribos“ bleibt erreichbar. Systemlinks werden unabhängig davon weiterhin verarbeitet;
die automatische HTTPS-Zuordnung benötigt eine verifizierte Plattform-/Domainkonfiguration,
siehe [RELEASE.md](RELEASE.md). Verwaltung, Ressourcenimport, Backupverwaltung, Adminhilfe
und nur Administratoren erlaubtes Veröffentlichen von Notizen bleiben außerhalb der App.

Die erstmalige Anmeldung, Werkfreigabe und Downloads benötigen einen Serverkontakt.
Gespeicherte Werke sind anschließend offline lesbar; Schreibaktionen und die Synchronisierung
benötigen eine Verbindung. Lokal gesicherte Dokumententwürfe ermöglichen
Wiederherstellung. Kommentarformulare halten
fehlgeschlagene Übertragungen innerhalb des offenen Dialogs vor; sie sind keine allgemeine
dauerhafte Offline-Warteschlange.

E-Ink-Unterstützung verwendet normale Android-/Flutter-Schnittstellen. Es wird kein
Boox-SDK eingebunden, und kein gerätespezifischer Refresh-Modus erzwungen. Ob Kontrast,
Scrollen und Touch auf einem bestimmten Boox-Modell angenehm sind, muss am Gerät geprüft werden.

Die nativen Einstellungen unter „Mehr“ bündeln Darstellung, Textdarstellung und nach Anmeldung
Leseschrift, Standardbibel sowie Markierungsfarben. Konto/Profil/Passwort sind über das Personen-Icon
erreichbar; mobile API-Schlüsselverwaltung und ein weiterer Konto-Eintrag unter „Mehr“ entfallen.
