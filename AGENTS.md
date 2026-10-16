# Akribos Flutter App

Android/iOS smartphones and tablets only, Flutter 3.47 / Dart 3.13, German UI.
Normal-user features only: no administration, resource import or admin help.
E-Ink mode must work without a proprietary device SDK. Run formatting, `flutter analyze`,
targeted regression tests and an Android build when relevant. Full local test suites
are not a release gate; leave comprehensive testing to CI as requested by the user.
The server repository is `../akribos`; the first-party protocol is documented in
`docs/API.md`. Keep that contract and the feature matrix up to date.

Use native Flutter controls and available window width, including OS split-screen,
landscape and large accessibility text. Reader text uses the local OFL fonts.
The user explicitly chose the existing Akribos web editor in a system WebView for
document editing. This exception is scoped to the document editor; other screens stay native.

The session cookie belongs in encrypted platform storage. Never bundle API keys,
passwords, certificates or live account fixtures. Account-dependent drafts must be
scoped by server, account and document; they must never appear for another user.
Reader resources use the Reader authorization channel. Public API keys do not grant
Reader privileges. Every mutation must preserve the server's owner/role checks,
document revisions and the relevant server action contracts. Native Reader tabs use the
explicit local mode below instead of publishing saved-workspace versions. Never retry a failed
write silently or overwrite a conflicting document. Flush before navigation.

Use explicit route/action contracts. New Web actions are not automatically native
API actions. Imports need preview/confirm; exports are explicit native share/save.
Exclude admin-only actions from both navigation and the first-party protocol.

No deployment, store publication, signing-identity setup or remote push is implied
by editing the local app. Distinguish local checks from device acceptance.

The direct Pixel APK is built by `scripts/build-android-production.sh`: fixed HTTPS
origin `https://akribos.de`, ARM64, version `0.2.9+12`, optimized AOT release with the existing local debug signing identity. Keep it
independent of local test-server defines and do not install/deploy from the script.
Ordinary app use requires no API key, USB or ADB. The ignored artifact and its SHA-256
file are written to `artifacts/`; store signing remains a separate explicit task.

Keep the PWA palette and compact reader chrome; the floating bottom navigation has
16px side margins, no expensive backdrop blur, and explicit E-Ink behavior. Reader tabs
are browsable as visual cards and by swipe. Sources are in docs/MOBILE-DESIGN.md.
Preserve loaded screen/scroll state on ordinary section switches, but invalidate all private
branches immediately at authentication boundaries, even if bootstrap fails. Delayed hidden
redirects must resume on the next visit; explicit Reader links must reload even if their URL is identical. Flush document and reader guards before navigation. Reader positions, searches and filters are saved to the device-local account-scoped snapshot.
Do not infer performance from debug builds. Direct device APKs use AOT release and must match
the already installed certificate; never regenerate the signing key for an update.

Word-triggered lexicon lookup is a temporary draggable bottom sheet using the read-only
Strong API. Keep the source Bible mounted with its scroll position and workspace untouched;
Back and dismiss return to it. Explicit lexicon resources still work as normal tabs. Carry
source resource, reference, word and wordPosition into lookups. Tab groups use the web
palette plus visible letters; E-Ink must retain labels without depending on color.
Do not render the full account tag catalogue in note lists. Keep tag filters on demand and
tag editing available; large tag collections must not create a wall of chips by default.

PersistCookieJar 4.0.9 does not load a stored host cookie map before saveFromResponse.
initializeReader must await loadForRequest(origin) before writing reader preference cookies;
otherwise every cold start overwrites the persisted session. Keep the secure-storage namespace,
key format and encryption options stable across app updates. Test with fresh persistent jars,
not only an in-memory CookieJar. Install updates with adb install -r; never uninstall/clear data.
Credential autofill must be explicit per field. Keep the login identifier and password mounted
in the same group, cancel on abandonment, and save credentials only after server-confirmed
success. Ordinary text fields must not be offered as usernames or passwords.

On every phone/tablet width, render Reader resources as one flat tab sequence. Store tabs,
positions, groups and searches locally per origin and account (guests separate), encrypted,
with serial writes. A different phone/tablet has its own independent tabs. Never import,
activate or publish named browser workspaces. Send x-akribos-reader-mode: local; Reader
actions are explicitly detached and carry no named-workspace selection/content versions.
Do not call workspace follow/view APIs or expose workspace-management UI. Respect current
server resource permissions when restoring local tabs; never cache private Bible text.
The tab overview ends with an empty plus card; adding it opens the resource chooser without
creating a persistent empty tab. Mehr > Einstellungen offers Textdarstellung with Versweise
and Fließtext, available to guests too; never put it in the tab overview. Appearance belongs only to Settings;
signed-in settings reuse /account actions for reading font, default Bible and highlight colors.
Refresh the retained Reader after font/style edits, preserving its flushed local position.
Account remains reachable via the person icon and contains profile, password, sign-out and
a clear deletion-request entry. The latter opens the public operator resource
`/datenschutz#konto-loeschen` without account identifiers or credentials in the URL;
it requests deletion rather than deleting or signing out, and launch failures stay visible.
Do not expose API-key management or a duplicate account destination in More. Fließtext uses
justified paragraphs, Versweise stays start-aligned. Settings use the attached ReaderController
to flush positions and change the retained reader, including when it is offstage. Store
versePerLine in the existing encrypted local snapshot (missing means true), never in shared
Reader URLs or server workspaces. Flow paragraphs keep source headings/line breaks and
per-verse word positions, actions and scroll anchors. Use actual RenderParagraph glyph boxes
for continuous marker strokes and in-paragraph verse alignment; include spaces, preserve
partial word boundaries and retain monochrome underlines in E-Ink. Scripture section/chapter
headings scale with the reading font (1.2/1.4), including accessibility scaling.
The verse menu has four fixed actions: Markieren, Sammlungen, Notiz and Teilen.
Use single-line icon/text buttons; measure actual label widths including system text scaling
before choosing columns. Keep at least 48px touch targets and all main actions visible at
normal phone/tablet portrait and landscape sizes. Copying is available through the native
share sheet on Android and iOS; preserve the verse/reference/URL text and iPad popover origin.
Offer whole-verse marking only; there is no word/partial-marking creation entry or handler.
Existing partial highlights retain rendering and source-bound deletion without data migration.
Keep arbitrary highlight/list catalogues in separate choice pages; system Back returns to
the overview. Preserve the remaining action codes and ordinary Strong-word lookups. Large
accessibility text may scroll instead of shrinking text, touch targets or clipping controls.
The floating Notes destination opens /notes?kind=note after flushing guards, with passage set
to the visible Reader chapter by default. The library's Aktuelles Kapitel switch can disable
this; persist that preference per origin/account. Use the existing server passage filter across
translations, never only filter a loaded page. Explicit manual passage filters remain possible.
The tab overview has no separate Notes button. Offer
Notes/Preparations switching in that library; no duplicate Preparations destination in More. Import, template management and preparation
column editing are excluded from mobile UI; moving documents between existing steps remains.
Help currently shows a local placeholder, never the web help catalogue. After the app is
finished, write separate Android/iOS phone/tablet instructions as a later task (docs/TODO.md).
The Search destination uses exactly the visible Reader resource, names it, and reruns the
existing query when that resource changes. It must never silently search other translations.
Android app links require the matching public signer association on akribos.de. iOS release
and domain association wait for the user's Apple organization enrollment; never invent IDs.

Android store automation is separate from the direct Pixel APK. `release.yml` has no
store secrets and dispatches `android-play.yml` explicitly on `main`; the verified
`android-play-internal` Environment permits only that branch, never tags. Do not move
signing secrets to repository scope. Gate the published tag, exact current main commit
and latest successful push CI again before signing and committing the Play edit.
Store version codes exceed all current Play artifacts/tracks, the configured historical
floor and permanent `play-build-android-N` reservation tags; never delete/reuse a
reservation after failure. Bootstrap builds only an AAB for the mandatory first manual
Play upload. Automatic uploads target `internal` only. Keep pinned Actions/dependency
hashes, artifact checksums and actual upload/readback status. Setup is documented in
`docs/PLAY-STORE.md`; the existing Pixel signing identity and script stay unchanged.

## Legacy standalone source/reader widgets

The following notes describe the retained standalone native widgets, not the active
WebView document editor described below. The source widget edits canonical Markdown
directly in a native TextField. Never
introduce a Delta/AST-to-Markdown save conversion. Opening, selection and Read/Edit
switches must preserve original source bytes and produce no PATCH. Keep the source
TextField mounted across modes: its internal UndoHistory owns the undo stack. Exclude
its focus/semantics while reading. Read mode cannot edit title or mutate metadata.
Keep DocumentDraft revisions, serialized saves, encrypted account/origin/document
drafts and navigation guards; only content changes update drafts.

MarkdownDocumentReader renders a complete document through the native HtmlContent
renderer, never by splitting on blank lines. Use server bodyHtml only when the source
matches the current draft; otherwise render the current source locally without writes
or network preview calls. Local GFM rendering is a preview, not a second persistence
format. Preserve genuine code blocks, loose/nested lists, lists containing quotes,
tables, footnotes and allowed inline HTML. The scoped FootnoteDefSyntax override puts
backlinks in a paragraph to avoid markdown 7.3.1's covariant-list crash; regression-test
rich footnote bodies. Footnote references open a native sheet and close back to the same reading position;
other same-document anchors remain local. External media must
never be fetched implicitly; continue using the private authenticated image factory.

Source mode intentionally shows Markdown syntax; typed prefixes are not rewritten.
Formatting is contextual, not a permanent wrapped toolbar. Insertion helpers edit only
the selected source span or lines and respect active IME composition. Keep the mode
selector at the left and the document menu at the right, with no separate plus button.
Extra insertions and details remain in that menu. Lists in reading mode use native HTML layout and first-line baselines. The opt-in
marker factory uses the scaled reading font because upstream HtmlListMarker omits
TextScaler; marker position still belongs to native HtmlListItem layout. Preserve edit/reading scroll positions independently across toggles.

## Active document editor: shared web component

The active document editor embeds the authenticated HTTPS `/app/editor/[id]` page.
Use the same Web DocumentEditor, custom tables/footnotes/highlight schema and Markdown
converters. Opening, selection and unmodified Read/Edit switches preserve original
Markdown and produce no PATCH. The web editor owns text saves. Native metadata and
attachment actions reserve/flush its queue, return the resulting revision, then unlock.
Keep the editor instance and undo history across reading/editing modes.

The native session bridge sets the app session in the native cookie store with
HttpOnly, Secure and path=/ before loading the exact origin. Never pass session values
through JavaScript, URLs, logs or an ordinary first-request header. Authentication
boundaries clear the web session and destroy private views. Trust bridge messages only
for the expected document, account and page instance; expose only versioned editor
commands. No arbitrary URL/native request proxy. External navigation flushes first.

Encrypted drafts retain the existing origin/account/document key and original revision.
Snapshots come from the real editor. Stale restored drafts must not acquire a newer
revision automatically. Wait for flush acknowledgements and local draft writes before
navigation. Errors, conflicts and timeouts preserve the editor and draft. Page-load
failure is visible and must never replace document content with an empty value.

The native header owns Bearbeiten/Lesen and the menu at the far right. The embedded
editor supplies contextual selection formatting and Markdown input rules. Reading
is non-editable, including title and metadata. No duplicate web navigation, workspaces,
two-row toolbar or plus button. Device checks cover keyboard/selection/back gestures,
dark/light/E-Ink, lists, tables, footnotes, undo and conflicts. iOS device acceptance
remains separate from Linux checks. The retained native source/reader widgets are
not a second writer for an active web document.
