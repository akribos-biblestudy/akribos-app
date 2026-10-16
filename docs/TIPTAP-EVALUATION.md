# Tiptap Flutter: begrenzte Kompatibilitätsprüfung

Stand: 15. Oktober 2026. Gegenstand ist das **unveränderte veröffentlichte
`tiptap_flutter 0.3.0`**, nicht ein bereits angepasster Akribos-Editor. Der Nutzer
möchte dieses Paket ausprobieren. Diese Prüfung belegt einzelne Eigenschaften
und nötige Grenzen; sie ersetzt keine Android-/iOS-Abnahme und gibt keine
vollständige Freigabe für bestehende Notizen.

Quellen: [Paket und dokumentierter Umfang](https://pub.dev/packages/tiptap_flutter/versions/0.3.0),
[Flutter-Quellprojekt](https://github.com/blackcoffee2/tiptap-flutter),
[Engine-Quellprojekt](https://github.com/blackcoffee2/tiptap-engine).
Das Paket ist MIT-lizenziert. Es betreibt Tiptap in einem unsichtbaren lokalen
Browserkontext und zeichnet den Editor mit Flutter. Das ist keine WebView-Seite
als sichtbarer Editor; für die Dokumentlogik bleibt trotzdem eine WebView nötig.

## Was tatsächlich ausgeführt wurde

`scripts/tiptap_probe.cjs` lädt ausschließlich das Engine-Bundle aus einem lokal
entpackten Paketarchiv in Playwright Chromium. Alle Browser-Netzwerkanfragen werden
abgebrochen. Es verwendet feste künstliche Texte, keine Konten, Sessions oder
vorhandenen Dokumente. Es sendet dieselben JSON-Kommandos wie die veröffentlichte
Flutter-Bridge und liest HTML sowie Dokument-JSON zurück.

Geprüfte Artefakte:

- Paketarchiv `tiptap_flutter-0.3.0.tar.gz`, SHA-256:
  `9a019864bd4e95414404a729317b12081373f6d884fa0e1df88f24724618e4b4`
- Enthaltenes `assets/engine/tiptap-engine.js`, SHA-256:
  `22e35aa61ffba84cf798ba1c07e949982cefef0f76662d6b2c5f81877851bbe9`
- Ausgeführt mit Node `v26.10.0` und Chromium `151.0.7922.34`.

Voraussetzungen: ein separat entpacktes veröffentlichtes Paket, bestehende
Playwright-Abhängigkeiten und dessen installierter Chromium aus dem benachbarten
Akribos-Backend. Das Script installiert keine NPM-Abhängigkeiten. Aus dem
App-Repository:

```sh
TIPTAP_PACKAGE_DIR=/pfad/zum/entpackten/tiptap_flutter-0.3.0 \
AKRIBOS_BACKEND_DIR=../akribos \
node scripts/tiptap_probe.cjs > /tmp/akribos-tiptap-probe.json
```

Die Ausgabe enthält Versionen, Bundle-Hash, Beobachtungen und synthetische
HTML-/JSON-Ergebnisse. Exit-Code 0 bedeutet, dass die Probe lief; bekannte fehlende
Funktionen stehen als `false` in `observed`. Das Script ist bewusst kein
Produkt-Abnahmetest. Für einen angepassten Fork zeigt
`matchesAuditedPublished030: false` die abweichende Engine an.

| Probe | Tatsächliches Ergebnis mit 0.3.0 |
| --- | --- |
| Liste mit Zitat und Unterliste | Struktur bleibt im Engine-HTML/JSON erhalten. |
| Explizites `toggleBulletList` | Erzeugt eine Liste; StarterKit ergänzt einen abschließenden Absatz. |
| Tabelle | Zeilen/Zellen gehen verloren; Inhalt wird zusammengezogener Absatztext. |
| `<mark>` | Hervorhebung verschwindet; Text bleibt. |
| Akribos-Fußnoten | Referenz wird Ziffer als normaler Text, Definition normale nummerierte Liste; IDs und Zuordnung verschwinden. |
| `insertText('<strong>X</strong>')` | Wird `<p><strong>X</strong></p>`, **kein** wörtlicher Text mit spitzen Klammern. |
| `insertText('-')`, danach Leerzeichen | Bleibt `<p>- </p>`; keine Bullet-InputRule. |
| `insertText('##')`, danach Leerzeichen | Bleibt `<p>## </p>`; keine Heading-InputRule. |
| Initialisierung mit `editable:false`, danach `insertText` | Ändert den Inhalt trotzdem zu `<p>CHANGED Original</p>`. |

Die letzte Beobachtung ist die Grenze zwischen Editierbarkeit und expliziten
Programmierkommandos: Tiptap darf programmgesteuerte Änderungen auch bei einer
nicht editierbaren DOM-Ansicht zulassen. Die native Eingabe darf daraus nicht
ableiten, dass die Engine ihre Mutationen blockiert. Im veröffentlichten
`TiptapEditor` wird der Editierbarkeitszustand nicht als Eingabesperre verwendet.
Ein Lesezustand braucht daher eine eigene Fokus-/IME-/Gesten-/Kommandosperre.

Ebenso ist korrektes Engine-JSON für Listen noch kein Nachweis für korrektes
Flutter-Layout, Cursorbewegung, Auswahl, Android-IME oder iOS-Eingabe. Die Probe
bewertet keine Geräteperformance und führt keinen echten Flutter-Editor aus.

## Unterschied zum Akribos-Webeditor

Der aktuelle Backend-Lockfile löst alle verwendeten Tiptap-Pakete auf **3.29.2**
auf. `src/lib/components/documents/DocumentEditor.svelte` konfiguriert StarterKit
mit Überschriften H1–H6, geprüftem `safeLinkHref`, abgeschaltetem `openOnClick` und
`trailingNode.notAfter: ['footnoteList']`. Hinzu kommen:

| Akribos-Erweiterung | Persistenzrelevanter Vertrag |
| --- | --- |
| `document-tables.ts` | `table → tableRow+`; `tableRow → (tableCell \| tableHeader)+`; Zelle genau ein Absatz; Spaltenausrichtung `left/center/right`; genau eine Headerzeile. Verbundene Zellen/Spaltenbreiten werden nicht persistiert. |
| `document-footnotes.ts` | Inline-Atom `footnoteReference{id,number}`; `footnoteList → footnoteDefinition+`; Definition `paragraph block*`; stabile IDs, wiederholte Verweise, Nummerierung, nicht referenzierte Definitionen. |
| `document-highlight.ts` | Attributfreie `highlight`-Markierung als `<mark>`. |
| `bible-reference-decorations.ts` | Erkennung und Darstellung von Bibelstellen; kein zusätzlicher gespeicherter Inhaltsknoten. |

Das veröffentlichte Flutter-Paket bündelt StarterKit plus Image. Ein zusätzlicher
Flutter-Renderer allein erweitert dieses Engine-Schema nicht. Für echte
Kompatibilität müssten Engine-Schema und native Darstellung/Bearbeitung gemeinsam
angepasst werden. Insbesondere Tabellenzellen und inline Fußnoten benötigen auch
funktionierende Positionen und Auswahl, nicht nur eine sichtbare Vorschau.

## Sichere Konvertierungs- und Speichergrenze

Akribos speichert **Markdown**, kein Tiptap-JSON. Die Webfunktionen
`documentMarkdownToHtml` und `documentHtmlToMarkdown` in
`src/lib/notes/document-markdown.ts` sind daher der relevante gemeinsame Vertrag.
Sie sind browserfähig und können mit einem lokalen Engine-Bundle gebaut werden:
`marked 18.0.11`, `turndown 7.2.4`, `yaml 2.9.0` sowie die referenzierten reinen
Notes-/Bibelmodule; kein Server-/Datenbankzugriff. Turndown braucht DOM-Operationen,
die im Engine-Browser vorhanden sind. Die Custom-Erweiterungen brauchen außerdem
`@tiptap/pm`, DOM-NodeViews sowie aufgelöste `$lib`-Aliase und die Übersetzungen.
Übernommene Akribos-Dateien müssen mit ihrer Herkunft und Lizenz dokumentiert sein.
Die Svelte-Editor-Komponente selbst gehört nicht in das native Bundle.

Für einen Versuch und jede spätere Integration gelten:

1. Original-Markdown separat behalten. Öffnen, Initialisierung, Auswahl und
   Lesen/Bearbeiten dürfen keine Rückkonvertierung und keinen PATCH auslösen.
   Eine reine Titeländerung darf den Titel speichern, muss dabei aber den
   unveränderten Markdown ohne Engine-Rückkonvertierung mitsenden. Nur echte
   Body-Änderungen machen das visuelle Textmodell dirty.
2. Auf Engine-Transaktionen nicht pauschal speichern: Auch Auswahländerungen
   erzeugen Zustandsmeldungen. Initialisierungs-/Recovery-Ereignisse unterdrücken
   und tatsächliche Dokumentänderungen von Selection unterscheiden.
3. Native Texteingabe und reine Text-Paste müssen wörtlichen Text einfügen.
   Das HTML-fähige veröffentlichte `insertText` ist dafür ungeeignet. Optional
   gewünschte InputRules dürfen nur an echten passenden Eingaben ansetzen.
4. Vor Save, Entwurfssicherung und Navigation ausstehende Eingabekommandos
   vollständig abarbeiten; erst dann einen konsistenten Snapshot exportieren.
   Bestehende Revisionsprüfung, Save-Queue, verschlüsselte Entwürfe und
   Kontotrennung bleiben verpflichtend.
5. Vor dem visuellen Editieren ununterstützte Dokumentmerkmale erkennen. Bis
   Schema und Renderer diese beherrschen, den vorhandenen Quelltexteditor
   anbieten; einen verlustbehafteten Import nicht still als neuen Inhalt speichern.
6. Der bestehende HTML-/Markdown-Konverter ist nach echten Bearbeitungen nicht
   bytegleich: Er normalisiert Zeilenenden/Leerzeichen und verliert unter anderem
   Listenstartnummern, Linktitel und beliebiges HTML. Unveränderte Originalquelle
   bleibt durch die Dirty-Grenze erhalten. Keine neue Normalisierung beim Öffnen.
7. Die veröffentlichte Bridge protokolliert Kommandos und Inhalte. Private Texte
   dürfen im Versuch nicht in Konsole oder unbeschränktem Logspeicher landen.
   Lokale Engine-Navigation und Medienzugriffe müssen ebenfalls eingeschränkt
   sein. Diese Prüfung bestätigt keinen bereits gehärteten Fork.

Es wurden für diese Bestandsaufnahme keine Backend-Endpunkte, Schemas oder
Produktionsdaten geändert. Eine vollständige Erweiterungsimplementierung,
Pixel-/iOS-Abnahme und die Entscheidung über den Umfang der Integration bleiben
separate Arbeit.

## Alternative: echter Webeditor in einer dedizierten WebView-Ansicht

Für identische Bearbeitung im Web und in der App ist eine kleine Einbettungsseite
mit der bestehenden `DocumentEditor.svelte` die direktere Option. Dann bleiben
Tiptap-Version, Custom-Schema, echte DOM-Eingabe, Markdownkonverter und Save-Queue
dieselben. Eine WebView wird hier ausdrücklich zum **sichtbaren** Editor; native
Navigation, Reader und übrige App bleiben Flutter. Geräteprüfung für Tastatur,
Auswahl, Scrollen, Darkmode und E-Ink bleibt nötig.

Auf Wunsch umgesetzt mit Version `0.2.9+12`; der aktuelle Vertrag steht in
[ARCHITECTURE.md](ARCHITECTURE.md) und [API.md](API.md). Die folgenden Punkte
beschreiben die dafür gewählte Architektur:

- Dedizierte Route `/app/editor/[id]` mit minimalem owner-geprüftem Load über
  `getDocument(db, locals.user.id, id)`, geprüfter Bibelauswahl und
  `private, no-store`/`noindex`. Die komplette `/notes/[id]`-Seite enthält
  Arbeitsbereichsnavigation und umfangreiche Metadaten; sie sollte nicht bloß
  per CSS versteckt werden. Der vorhandene PATCH-Endpunkt
  `/api/documents/[id]` bleibt mit Session, Eigentümerprüfung und Revision bestehen.
- Ein eigenes SvelteKit-Layout unterhalb der Route allein genügt nicht, da das
  Rootlayout weiterhin beteiligt ist. Den Embedpfad serverseitig vor
  `resolveReaderWorkspaceContext` ausnehmen: Dieser kann einen Standardworkspace
  anlegen. Ebenso `src/hooks.client.ts` ausnehmen; seine globale Initialisierung
  schreibt Reader-Cookies, installiert Fetchheader und Workspace-Wiederaufnahme.
  Im Rootlayout die Mount-/Resume-/Invalidate-/Viewport-Cookie-Logik und die
  Darstellung von SiteHeader, Analytics und globalem Kontextmenü auslassen.
  Gemeinsame CSS-/Fontdefinitionen bleiben nutzbar. Die Erkennung muss für die
  echte Route und ihre Datenabrufe gelten, nicht nur für einen einmaligen Header.
- Die HTTPS-Seite verwendet die normale Session aus dem nativen WebView-
  Cookie-Store. Die bestehende Cookie-Semantik ist `HttpOnly`, `Secure` in
  Produktion, `SameSite=Lax`, Pfad `/`. Ein Cookie-Header nur am ersten
  Seitenaufruf stellt keine funktionierende Sitzung für nachfolgende Fetches
  sicher. Cookie-Synchronisation muss diese Attribute erhalten; keine Übergabe
  per URL oder `document.cookie`. Logout/Kontowechsel muss die WebView ebenfalls
  leeren bzw. verwerfen. App-Header sind keine Authentifizierung.
- Formulare und PATCHs bleiben am echten Server-Origin. Kein `file://`-Wrapper,
  kein `loadHtmlString` mit fremdem Origin und keine allgemeine CORS-/CSRF-Ausnahme.
- `DocumentEditor.flush()` wartet schon auf die serialisierte Save-Queue und auf
  während einer Anfrage weitergetippten Text. Flutter-Zurück, Navbar und externe
  Links brauchen eine enge Request/Antwort-Bridge: erst nach erfolgreichem Flush
  die WebView verlassen. Bei Fehler, Konflikt oder Timeout bleibt sie erhalten.
  `beforeNavigate` schützt Svelte-Navigation, aber nicht das Entfernen eines
  nativen Widgets. `onOpenDocument` und `onOpenBibleReference` können passende
  native Weiterleitungen übernehmen; der Host muss vorher flushen.
- Der bestehende Schalter **Visuell/Markdown ist kein Lesemodus**. Für Lesen
  braucht die Einbettung eine echte nicht bearbeitbare Ansicht bzw. einen
  kontrollierten Zustand der gemeinsamen Komponente einschließlich Titel,
  Werkzeugen und Fokus. Dabei die Editorinstanz samt History erhalten und
  ungespeicherten Text nicht durch veraltetes `bodyHtml` ersetzen.
- Die Webkomponente hat derzeit keine Entwurfsablage wie der native Editor.
  Soll dessen Offline-/Recovery-Vertrag erhalten bleiben, muss eine begrenzte
  Snapshot-Bridge Titel, Markdown und ursprüngliche Revision an den bestehenden
  verschlüsselten, konto-/server-/dokumentgebundenen Speicher übergeben. Keine
  parallele zweite PATCH-Queue im Flutter-Host und kein stilles Hochsetzen einer
  wiederhergestellten Entwurfsrevision.

Diese Alternative vermeidet eine zweite Implementierung von Akribos' Schema und
Konvertern. Sie verlangt dafür gezielte Einbettung, Sessionübernahme und
Lebenszyklusintegration; das direkte Laden der normalen Notizseite erfüllt diese
Grenzen noch nicht.
