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
Do not add a WebView as a substitute for a missing feature.

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
origin `https://akribos.de`, ARM64, version `0.2.7+10`, optimized AOT release with the existing local debug signing identity. Keep it
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
The floating Notes destination always opens /notes?kind=note after flushing guards; offer
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

The native document editor uses FlutterQuill 11.6 with an Akribos Markdown adapter.
Markdown remains authoritative; never replace it with generic HTML/Delta conversion.
Opening, selection and Read/Edit switches must preserve the original source and produce
no PATCH. Unchanged source blocks, tables, footnotes and unsupported structures survive
edits elsewhere. Formatting is contextual, not a permanently wrapped toolbar. Keep one
controller across Read/Edit to retain undo and position; Read mode cannot edit the title
or mutate metadata. Keep existing DocumentDraft revisions, serialized saves, encrypted
account/origin/document drafts and navigation guards. Only content changes update drafts.
External images/media are not automatically fetched or added by clipboard operations.
HTML fragment links must stay in the current document; other internal links retain fragments.

Markdown list blocks must be delimited with the Markdown parser, not at every blank
line: the web editor emits loose nested lists with four-space indentation. Preserve
list hierarchy, continuation paragraphs, real code blocks and original source on
read-only loads. List markers use the same scaled first-line geometry as reading text.
The document header has mode selection at the left and its options menu at the right;
no separate plus button. Additional insertion actions and details remain in that menu.
Markdown typing shortcuts must work through native software-keyboard input as well as
hardware keys. They apply only to typed block prefixes followed by a space, never
loads/recovery, paste, IME composition or Read mode; Undo must restore the literal input.
