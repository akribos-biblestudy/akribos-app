# Umfang der nativen Nutzeroberfläche

Stand: 15. Oktober 2026. Nur Android und iOS, Smartphones und Tablets. Alle Einträge
beziehen sich auf normale Nutzer und auf deren aktuelle serverseitige Leserechte.

| Bereich | Native Umsetzung |
| --- | --- |
| Lesen | Stellenwahl, Bibeln, Kommentare, Lexika, Parallelstellen, strukturierte Verse, Fußnoten, Strong-Wörter und Quellenangaben |
| Ansichten | Acht Layouts, bis zu vier Kacheln, Ressourcen-Tabs, Verschieben/Sortieren, Trennergrößen, A–E-Kopplung, unabhängige Tabs |
| Arbeitsbereiche | Erstellen aus aktueller Ansicht, Öffnen, Umbenennen, Löschen, versionsgeschütztes Speichern und Folgen veröffentlichter Lesepositionen |
| Telefon/Tablet | Floating-Hauptnavigation, visuelle Tabkarten und Wischwechsel, mehrere Kacheln bei breitem Fenster; Hoch-/Querformat und verfügbare Fensterbreite |
| E-Ink | Kontrastreiche helle Darstellung, reduzierte Animationen, direktes Blättern in Bildschirmabschnitten, erkennbare Markierungen ohne Farberkennung |
| Suche | Wort-/Phrasensuche, Vorschläge, Buchfilter, Seiten, Suche innerhalb eines Ressourcen-Tabs |
| Wortstudium | Strong-Artikel, Quellwort/Position, Morphologie, Übersetzungsformen, Häufigkeiten und Fundstellen |
| Markierungen | Ganze Verse, Versbereiche und Wörter; Entfernen, Übersichten, eigene Stilnamen und Hexfarben |
| Notizen | Bibliothek, Filter, Tags, Stellen, Papierkorb/Wiederherstellung, verknüpfte Sammlungen und Rückverweise |
| Editor | Markdown mit Werkzeugleiste und nativer Vorschau, revisionstreues Autosave, Konfliktvergleich, Entwurfswiederherstellung, Bibelzitate und Anhänge |
| Dokumentdateien | Persönliche Importe mit Vorschau/Bestätigung, serverseitige Exportformate über den nativen Teilen-Dialog |
| Ausarbeitungen | Board, Spalten, Sortieren/Verschieben, Vorlagen, Metadaten, Durchführungen; Wechsel zwischen Notiz und Ausarbeitung |
| Sammlungen | Anlegen/Umbenennen/Löschen, Stellen hinzufügen/entfernen, Freigabelinks, Mitglieder/Einladungen, Verlassen, Kommentare/Antworten/Reaktionen |
| Öffentlich Geteiltes | Öffentliche Sammlungen und veröffentlichte Notizen lesen, Links teilen/öffnen; Links erweitern keine Leserechte |
| Konto | E-Mail-Code, Passwort, Bestätigungs-/Rücksetzlinks, Profil, Standardbibel, Schriftgröße, Darstellung, persönliche API-Schlüssel und Abmelden |
| Hilfe | Themen, Suche, Artikel, echte Serverabbildungen mit Vergrößerung; Adminhilfe ist ausgeschlossen |

## Unterschiede zur Weboberfläche

Die Bedienung wird an das Gerät angepasst. Der Dokumenteditor verwendet Markdown
mit Werkzeugleiste und Vorschau, nicht den WYSIWYG-Editor des Browsers. Kommentare
werden in die vom bestehenden Server unterstützte Formatierung umgewandelt; vorhandenes
HTML bleibt ohne Bearbeitung erhalten. Die Web-Einführungstour mit Popovern wird nicht
übernommen; die Nutzerhilfe ist in der App erreichbar.

Datenschutz, Impressum und interaktive öffentliche API-Dokumentation öffnen die
aktuellen Seiten des Betreibers im Systembrowser. Verwaltung, Ressourcenimport,
Backupverwaltung, Adminhilfe und nur Administratoren erlaubtes Veröffentlichen von
Notizen sind bewusst nicht Teil dieser App.

Die App benötigt einen Serverkontakt. Lokal gesicherte Dokumententwürfe ermöglichen
Wiederherstellung, aber keinen vollständigen Offlinebetrieb. Kommentar-/Vorlagenformulare
halten fehlerhafte Übertragungen innerhalb des offenen Dialogs vor; sie sind keine
allgemeine dauerhafte Offline-Warteschlange.

E-Ink-Unterstützung verwendet normale Android-/Flutter-Schnittstellen. Es wird kein
Boox-SDK eingebunden, und kein gerätespezifischer Refresh-Modus erzwungen. Ob Kontrast,
Blättern und Touch auf einem bestimmten Boox-Modell angenehm sind, muss am Gerät geprüft werden.
