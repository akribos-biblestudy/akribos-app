# Akribos Flutter App

Android/iOS smartphones and tablets only, Flutter 3.47 / Dart 3.13, German UI.
Normal-user features only: no administration, resource import or admin help.
E-Ink mode must work without a proprietary device SDK. Run `dart format lib test`,
`flutter analyze`, `flutter test` and an Android build before completion.
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
