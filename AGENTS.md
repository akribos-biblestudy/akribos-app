# Akribos Flutter App

Android/iOS smartphones and tablets only, Flutter 3.47 / Dart 3.13, German UI.
Normal-user features only: no administration, resource import or admin help.
E-Ink mode must work without a proprietary device SDK. Keep contrast and reduced
animations; reading uses continuous scrolling without screen-page controls.
Run formatting, `flutter analyze`,
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
16px side margins, no expensive backdrop blur, and explicit E-Ink behavior. E-Ink
navigation uses opaque black 2px boundaries: a frame around the bottom bar and separators
below the app header and resource navigation; keep these independent of shadows or gray fills. Reader tabs
are browsable as visual cards and by swipe. Sources are in docs/MOBILE-DESIGN.md.
Preserve loaded screen/scroll state on ordinary section switches, but invalidate all private
branches immediately at authentication boundaries, even if bootstrap fails. Delayed hidden
redirects must resume on the next visit; explicit Reader links must reload even if their URL is identical. Flush document and reader guards before navigation. Reader positions, searches and filters are saved to the device-local account-scoped snapshot.
Do not infer performance from debug builds. Direct device APKs use AOT release and must match
the already installed certificate; never regenerate the signing key for an update.

Defer horizontal swipe activation and its linked-position/storage work until the
PageView settles; navigation guards must flush an interrupted gesture's visible choice.
Reuse chapter slivers and VerseText presentation across selection/save-only updates.
Invalidate presentation for replacement chapter data, reading preferences and inherited
styles. Chapter reloads replace segment lists; cached actions must resolve current
callbacks rather than retain an earlier tab's handlers. Performance regressions must
exercise long Fließtext paragraphs as well as versewise rows, without equating widget
test timing to release-device frame rates.

ReaderRichText inherits native RenderParagraph layout, painting and semantic leaves.
Its semantics hierarchy is grouped recursively into at most 32 siblings, avoiding
quadratic spatial sorting of long linked paragraphs. Pure viewport clipping updates
must reuse native leaves, their parentage and sort keys, updating only changed hidden
flags. Reassembling native leaves recreates sort keys and dirties every word; detaching
and regrouping also forces full retransmission to Android. Invalidate the cached leaf
configuration for layout, semantic metadata and recognizer callback changes; unsupported
inline content must fall back to native assembly. Preserve native labels, actions,
node IDs, clipping and paragraph-local rectangles; do not disable accessibility or
replace word actions with a single paragraph label. Regression tests must enable
semantics and cover fast flings, reflow and disabling/re-enabling semantics. FrameTiming
build/raster values alone miss semantic work after compositing; verify fast release-device
gestures and post-release scrolling with native thread traces and practical feedback.

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

On every phone/tablet width, keep Reader resources in one flat tab sequence. An optional
tablet notes companion follows the visible Bible chapter when the available window width
and system text scaling allow two usable columns. Settings choose visibility and side;
the companion is not a tab/workspace and its scrolling never changes Bible/group positions.
Use the existing owner-only `/api/documents?kind=note&passage=…` endpoint without a resource
filter so notes match across translations. Only chapter changes reload, never each verse;
failed or pending chapter requests hide old summaries, and late responses cannot replace the
current chapter. Guests see sign-in instead of requesting private notes. Opening/creating
notes flushes Reader positions and uses the existing guarded WebView document editor;
returning refreshes summaries. The encrypted local snapshot stores only companion enabled/side
preferences outside the shared URL; ignore old commentary resourceId without changing tabs.
Tab cards support long-press drag with edge autoscroll and screen-reader move actions.
Reordering normalizes imported multi-tile URL state to one local tile, preserving every tab's
ID/content, group, search and selected identity; resize alone never rearranges tabs. Store tabs,
positions, groups and searches locally per origin and account (guests separate), encrypted,
with serial writes. A different phone/tablet has its own independent tabs. Never import,
activate or publish named browser workspaces. Send x-akribos-reader-mode: local; Reader
actions are explicitly detached and carry no named-workspace selection/content versions.
Do not call workspace follow/view APIs or expose workspace-management UI. Respect current
server resource permissions when restoring local tabs. Offline works require an
explicit server-side per-work license and Reader grant; store packages encrypted
and isolated by origin and account. On reconnection recheck grants and remove
revoked packages; an offline device cannot discover revocation until it reconnects.
Fail closed at authentication boundaries and bind offline startup to the last
confirmed session. Offline writes stay unavailable; saved reading positions and
display preferences remain account-scoped. See docs/API.md for the package contract.
The tab overview ends with an empty plus card; adding it opens the resource chooser without
creating a persistent empty tab; dropping a tab there moves it to the end. Mehr > Einstellungen offers Textdarstellung with Versweise
and Fließtext, available to guests too; never put it in the tab overview. Appearance belongs only to Settings;
signed-in settings reuse /account actions for reading font, default Bible and highlight colors.
Refresh the retained Reader after font/style edits, preserving its flushed local position.
Account remains reachable via the person icon and contains profile, password, sign-out and
a clear deletion-request entry. The latter opens the public operator resource
`/datenschutz#konto-loeschen` without account identifiers or credentials in the URL;
it requests deletion rather than deleting or signing out, and launch failures stay visible.
Operator links use an explicit browser on Android, never a generic URL/Custom Tab
intent that the verified Akribos App Link could resolve back to this app. The public
browser receives no native session. Keep the complete URL including fragments;
information-screen titles compare the parsed path only. Browser failures must be
visible for both the deletion entry and the operator-information button.
Do not expose API-key management or a duplicate account destination in More. Fließtext uses
justified paragraphs, Versweise stays start-aligned. Settings use the attached ReaderController
to flush positions and change the retained reader, including when it is offstage. Store
versePerLine in the existing encrypted local snapshot (missing means false; explicit saved
choices remain unchanged), never in shared
Reader URLs or server workspaces. Flow paragraphs keep source headings/line breaks and
per-verse word positions, actions and scroll anchors. Use actual RenderParagraph glyph boxes
for continuous marker strokes and in-paragraph verse alignment; include spaces, preserve
partial word boundaries and retain opaque, pixel-aligned monochrome underlines without
antialiasing in E-Ink. Scripture section/chapter
headings scale with the reading font (1.2/1.4), including accessibility scaling.
Commentary and lexicon article bodies, original forms and search excerpts use the same
reading scale; navigation labels retain their UI sizes. Flow verse numbers use a
non-breaking space before the first word, keeping source word positions unchanged.
Source notes before the first scripture word describe the verse and display at its end.
Combine them with final-word/end notes into one superscript marker and dialog; retain source
markers/numbers and all bodies. Ordinary word notes stay attached without inserted spaces.
This is display-only: stored source segments, tagged positions and highlight word indices never
change. Automatic Strong-assignment warnings keep their original word binding and visibility.
Note markers remain native text spans joined to the preceding word by a word joiner;
WidgetSpan can orphan them after punctuation in justified text. Count the joiner plus the
actual UTF-16 marker length in glyph offsets. Foreground paint raises the visible glyphs
without changing native shaping, line breaking, selection or accessible tap actions;
include their raised bounds in hit testing. Shape the cached paint overlay with the
complete native paragraph context and layout parameters, not isolated marker strings:
mixed RTL/LTR text can split a marker into multiple visual runs. Keep all marker text
at the reading scale and dispose the cached TextPainter with its owning state.
The verse menu has four fixed actions: Markieren, Sammlungen, Notiz and Teilen.
Use single-line icon/text buttons; measure actual label widths including system text scaling
before choosing columns. Keep at least 48px touch targets and all main actions visible at
normal phone/tablet portrait and landscape sizes. Copying is available through the native
share sheet on Android and iOS; preserve the verse/reference/URL text and iPad popover origin.
Offer whole-verse marking only; there is no word/partial-marking creation entry or handler.
Existing partial highlights retain rendering and source-bound deletion without data migration.
In E-Ink flow text, the next verse begins on a new line after a visible highlight label;
consecutive highlights without a visible end label continue normally.
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

Installed version/build come from PackageManager/Bundle through `de.akribos.app/updates`,
never from a separately maintained UI constant. Settings and About share the same update
controller. Android checks Play account/installation eligibility with AppUpdateManager;
iOS checks Apple's public lookup for the exact bundle and actual StoreKit storefront,
comparing numeric marketing versions and the minimum OS version. Do not invent an Apple
listing ID or use GitHub releases as Store availability. Known direct Android installations,
iOS development/simulator builds and sandbox receipts report unsupported checks; absent iOS
receipts remain unknown. Store requests use separate unauthenticated transport, never AppApi,
cookies, account identifiers or arbitrary response URLs. Auto-check at start/resume, throttle
successful checks for 12 hours and failed/unavailable checks for 15 minutes. Dismiss an offered
version for 24 hours on this device; newer versions remain visible. Manual checks show current,
unavailable and failed distinctly. Before a voluntary external Store launch, flush active
navigation guards and the retained Reader; failed saves block launching. Dispose cancels
outstanding check deadlines. No forced update, background installation or push permission.
CI includes Android policy tests and an unsigned iOS simulator build plus native XCTest;
that does not establish Store/device acceptance or authorize publication.

Android store automation is separate from the direct Pixel APK. `release.yml` has no
store secrets and dispatches `android-play.yml` explicitly on `main`; the verified
`android-play-internal` Environment permits only that branch, never tags. Do not move
signing secrets to repository scope. Gate the published tag, exact current main commit
and latest successful push CI again before signing and committing the Play edit.
The initial `wait-for-ci` check waits up to 45 minutes for that exact main push CI,
so publishing a release immediately after merging does not fail just because CI is
still running. Revalidate main/tag/release identity on every poll; finished failed
checks and API errors must fail immediately. Later gates remain strict, without waiting.
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
