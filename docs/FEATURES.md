# Umfang der nativen Nutzeroberfläche

Stand: 15. Oktober 2026. Zielsysteme sind Android und iOS auf Smartphones und Tablets;
vorerst wird nur Android veröffentlicht. Alle Einträge beziehen sich auf normale Nutzer
und auf deren aktuelle serverseitige Leserechte. Der tatsächliche Prüfstand steht in
[VALIDATION.md](VALIDATION.md).

| Bereich | Native Umsetzung |
| --- | --- |
| Lesen | Stellenwahl, Bibeln, Kommentare, Lexika, Parallelstellen, strukturierte Verse, Fußnoten, Strong-Wörter und Quellenangaben |
| Tabs | Eine flache Folge aller Ressourcen auf jeder Fensterbreite, visuelle Tabkarten, Hinzufügen/Schließen, A–E-Kopplung mit Web-Farben und Buchstaben, unabhängige Tabs |
| Lokaler Readerstand | Tabs, Lesestellen, Tabgruppen, Suchen und Notizfilter pro Gerät, Server und Konto im sicheren Speicher; eigener Gaststand, Wiederherstellung bei Neustart |
| Unabhängigkeit | Keine Übernahme oder Änderung von Browser-Arbeitsbereichen, keine Synchronisierung der Tabs zwischen App-Geräten, keine Workspace-Verwaltung |
| Telefon/Tablet | Floating-Hauptnavigation, Wischwechsel zwischen allen Werken, Hoch-/Querformat und Fensterwechsel ohne Umordnung der lokalen Tabs |
| E-Ink | Kontrastreiche helle Darstellung, reduzierte Animationen, direktes Blättern in Bildschirmabschnitten, erkennbare Markierungen ohne Farberkennung |
| Suche | Wort-/Phrasensuche, Vorschläge, Buchfilter und Seiten; beim Öffnen übernimmt die Hauptnavigation das aktuelle Reader-Werk samt Titel und sucht bei geändertem Werk den bisherigen Begriff erneut; lokale Werksuche im Tabmenü |
| Wortstudium | Herunterwischbarer Lexikon-Dialog bei Wortklick, Strong-Artikel, Quellwort/Position, Morphologie, Übersetzungsformen, Häufigkeiten und Fundstellen |
| Markierungen | Ganze Verse, Versbereiche und Wörter; Entfernen, Übersichten, eigene Stilnamen und Farben mit sichtbarer Farbkachel und Textvorschau im Konto |
| Notizen | Eigener Einstieg `/notes?kind=note`, interner Wechsel zu Ausarbeitungen, Bibliothek ohne Tagwolke, gezielte Tagfilter, Stellen, Papierkorb/Wiederherstellung, verknüpfte Sammlungen und Rückverweise |
| Editor | Markdown mit Werkzeugleiste und nativer Vorschau, revisionstreues Autosave, Konfliktvergleich, Entwurfswiederherstellung, Bibelzitate und Anhänge |
| Dokumentdateien | Serverseitige Exportformate über den nativen Teilen-Dialog; kein mobiler Import |
| Ausarbeitungen | Board mit vorhandenen, nicht bearbeitbaren Spalten; Dokumente zwischen Spalten verschieben, Metadaten und Durchführungen; Wechsel zwischen Notiz und Ausarbeitung |
| Sammlungen | Anlegen/Umbenennen/Löschen, Stellen hinzufügen/entfernen, Freigabelinks, Mitglieder/Einladungen, Verlassen, Kommentare/Antworten/Reaktionen |
| Öffentlich Geteiltes | Öffentliche Sammlungen und veröffentlichte Notizen lesen, Links teilen/öffnen; Links erweitern keine Leserechte |
| Konto | E-Mail-Code, Passwort mit System-Autofill, erhaltene gültige Anmeldung bei App-Updates, Bestätigungs-/Rücksetzlinks, Profil, Standardbibel, Schriftgröße, Darstellung, persönliche API-Schlüssel und Abmelden |
| Mehr | Sammlungen, Ausarbeitungen, Konto, E-Ink-Modus, Hilfeplatzhalter und Über Akribos mit Open-Source-Lizenzen |
| Hilfe | Lokaler Platzhalter; eigenständige App-Anleitungen folgen nach Fertigstellung, siehe [TODO.md](TODO.md) |

## Unterschiede zur Weboberfläche

Die Bedienung wird an das Gerät angepasst. Der Dokumenteditor verwendet Markdown
mit Werkzeugleiste und Vorschau. Kommentare werden in die vom bestehenden Server unterstützte
Formatierung umgewandelt; vorhandenes HTML bleibt ohne Bearbeitung erhalten. Die Webhilfe
und die Web-Einführungstour mit Popovern werden nicht als App-Hilfe übernommen.

Import, Vorlagenverwaltung, Vorlagenwahl und die Bearbeitung von Boardspalten sind nicht
Teil der mobilen Oberfläche. Alte direkte Import-/Vorlagenpfade öffnen die zugehörige
Notiz-/Ausarbeitungsübersicht. Die Hauptnavigation „Notizen“ zeigt ausschließlich Notizen;
Ausarbeitungen sind über den internen Wechsel und „Mehr“ erreichbar.

„Mehr“ enthält keine Einträge für Datenschutz, Impressum oder einen manuellen Linkdialog.
„Über Akribos“ bleibt erreichbar. Systemlinks werden unabhängig davon weiterhin verarbeitet;
die automatische HTTPS-Zuordnung benötigt eine verifizierte Plattform-/Domainkonfiguration,
siehe [RELEASE.md](RELEASE.md). Verwaltung, Ressourcenimport, Backupverwaltung, Adminhilfe
und nur Administratoren erlaubtes Veröffentlichen von Notizen bleiben außerhalb der App.

Die App benötigt einen Serverkontakt. Lokal gesicherte Dokumententwürfe ermöglichen
Wiederherstellung, aber keinen vollständigen Offlinebetrieb. Kommentarformulare halten
fehlgeschlagene Übertragungen innerhalb des offenen Dialogs vor; sie sind keine allgemeine
dauerhafte Offline-Warteschlange.

E-Ink-Unterstützung verwendet normale Android-/Flutter-Schnittstellen. Es wird kein
Boox-SDK eingebunden, und kein gerätespezifischer Refresh-Modus erzwungen. Ob Kontrast,
Blättern und Touch auf einem bestimmten Boox-Modell angenehm sind, muss am Gerät geprüft werden.
