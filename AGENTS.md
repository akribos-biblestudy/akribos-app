# Akribos Flutter App

Android/iOS smartphones and tablets only, Flutter 3.47 / Dart 3.13, German UI.
Normal-user features only: no administration, resource import or admin help.
E-Ink mode must work without a proprietary device SDK. Run formatting, `flutter analyze`,
targeted regression tests and an Android build when relevant. Full local test suites
are not a release gate; leave comprehensive testing to CI as requested by the user.
The server repository is `../akribos`; the first-party protocol is documented in
`docs/API.md`. Keep that contract and the feature matrix up to date.

Use native Flutter controls and available window width, including split-screen,
landscape and large accessibility text. Reader text uses the local OFL fonts.
Do not add a WebView as a substitute for a missing feature.

The session cookie belongs in encrypted platform storage. Never bundle API keys,
passwords, certificates or live account fixtures. Account-dependent drafts must be
scoped by server, account and document; they must never appear for another user.
Reader resources use the Reader authorization channel. Public API keys do not grant
Reader privileges. Every mutation must preserve the server's owner/role checks,
workspace selection/content versions and document revision. Never retry a failed
write silently or overwrite a conflicting document. Flush before navigation.

Use explicit route/action contracts. New Web actions are not automatically native
API actions. Imports need preview/confirm; exports are explicit native share/save.
Exclude admin-only actions from both navigation and the first-party protocol.

No deployment, store publication, signing-identity setup or remote push is implied
by editing the local app. Distinguish local checks from device acceptance.

The direct Pixel APK is built by `scripts/build-android-production.sh`: fixed HTTPS
origin `https://akribos.de`, ARM64, version `0.2.0+3`, optimized AOT release with the existing local debug signing identity. Keep it
independent of local test-server defines and do not install/deploy from the script.
Ordinary app use requires no API key, USB or ADB. The ignored artifact and its SHA-256
file are written to `artifacts/`; store signing remains a separate explicit task.

Keep the PWA palette and compact reader chrome; the floating bottom navigation has
16px side margins, no expensive backdrop blur, and explicit E-Ink behavior. Reader tabs
are browsable as visual cards and by swipe. Sources are in docs/MOBILE-DESIGN.md.
Preserve loaded screen/scroll state on ordinary section switches, but invalidate all private
branches immediately at authentication boundaries, even if bootstrap fails. Delayed hidden
redirects must resume on the next visit; explicit workspace opening must reload even if its
URL is identical. Flush document and reader guards before navigation. Position-only saves
use resume:true; search/filter changes need the separate normal save with fresh versions.
Do not infer performance from debug builds. Direct device APKs use AOT release and must match
the already installed certificate; never regenerate the signing key for an update.
