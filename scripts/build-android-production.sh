#!/usr/bin/env bash
set -euo pipefail

if (( $# != 0 )); then
  printf 'Aufruf: %s (ohne Argumente)\n' "$0" >&2
  exit 2
fi

app_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd -- "$app_root"

# This is the installable Pixel build for the public Akribos service.
# The debug signing identity is managed by Android tooling, not checked in here.
flutter pub get --enforce-lockfile
flutter build apk --no-pub --debug --target-platform android-arm64 \
  --build-name=0.1.0 --build-number=2 \
  --dart-define=AKRIBOS_SERVER=https://akribos.de

mkdir -p artifacts
install -m 644 build/app/outputs/flutter-apk/app-debug.apk \
  artifacts/akribos-0.1.0-akribos-de-debug.apk
(
  cd artifacts
  sha256sum akribos-0.1.0-akribos-de-debug.apk \
    > akribos-0.1.0-akribos-de-debug.apk.sha256
  cat akribos-0.1.0-akribos-de-debug.apk.sha256
)
