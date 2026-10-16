# Embedded editor bridge fixture

`web_editor_protocol.json` was emitted by the actual backend
`src/lib/app/editor-bridge.ts` unit harness, not by the Flutter
protocol peer. It contains synthetic document/account identifiers and text only.

Scenarios cover initialization, lock/flush/pause/resume, a locked reading-mode
change, failed saving and metadata revision handoff. The native replay replaces
only transport request IDs and the randomly generated per-page `instanceId`.
Document source and response shapes are consumed unchanged. The backend bridge
unit tests remain the executable authority for state transitions.
