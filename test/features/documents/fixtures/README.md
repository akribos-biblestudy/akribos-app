These synthetic fixtures were generated on 2026-10-15 with the sibling Akribos
repository's `src/lib/notes/document-markdown.ts` functions
`documentHtmlToMarkdown(html)` and `documentMarkdownToHtml(markdown)`.
They contain recreated structural examples (a quotation inside a list, five nested
items, genuine code, continuation paragraphs, and rich/repeated/unreferenced
footnotes), not exported user documents. Each JSON entry retains source HTML when
applicable, exact generated Markdown, and canonical rendered HTML.

The native read view parses the complete Markdown document. It never serializes
its display AST back into the draft. Server HTML is preferred only when the host
has verified that its saved Markdown matches the current draft exactly. Offline
GFM footnotes use a display-only workaround for markdown 7.3.1's trailing-list
backlink TypeError and preserve otherwise hidden unreferenced definitions.
Offline preview is not a complete port of Akribos's historical footnote repairs
or Bible-reference normalization; authored Bible links continue to work.

Document list bullets opt into the same scaled RichText factory as their text.
flutter_widget_from_html_core 0.17.4's default HtmlListMarker creates a private
TextPainter without the system TextScaler; otherwise only ordered markers grow
with accessibility text. Geometry tests load the real Akribos font and compare
first-line baselines for wrapped ordered items and nested bullet items at
320/1000px and 100/200% text, including actual nested indentation.
