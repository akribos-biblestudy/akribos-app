#!/usr/bin/env bash
set -euo pipefail

if (( $# != 0 )); then
  printf 'Aufruf: %s (ohne Argumente)\n' "$0" >&2
  exit 2
fi

fail() {
  printf 'Fehler: %s\n' "$*" >&2
  exit 1
}

app_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd -- "$app_root"

# AOT release for direct Pixel distribution; the existing local debug identity
# keeps updates compatible with build 2. Never create or copy a signing key here.
# Public certificate fingerprint verified against the previously delivered APK.
expected_signer_sha256='80a5790ab68d738a770fb82a7c0326efad5929d4d63082383c06dc72c2145ccb'
android_keystore="$HOME/.android/debug.keystore"
[[ -f "$android_keystore" && -r "$android_keystore" ]] || \
  fail 'Der vorhandene ~/.android/debug.keystore fehlt oder ist nicht lesbar. Keinen neuen Schlüssel erzeugen.'

for required_command in flutter keytool sha256sum sort install; do
  command -v "$required_command" >/dev/null || fail "Werkzeug fehlt: $required_command"
done

keystore_sha256="$(keytool -exportcert -keystore "$android_keystore" \
  -alias androiddebugkey -storepass android | sha256sum)"
keystore_sha256="${keystore_sha256%% *}"
[[ "$keystore_sha256" == "$expected_signer_sha256" ]] || \
  fail 'Der lokale Schlüssel stimmt nicht mit der ausgelieferten Build-2-Signatur überein.'

android_sdk="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
if [[ -z "$android_sdk" && -f android/local.properties ]]; then
  android_sdk="$(sed -n 's/^sdk\.dir=//p' android/local.properties | tail -n 1)"
fi
[[ -d "$android_sdk/build-tools" ]] || \
  fail 'Android SDK nicht gefunden. ANDROID_HOME oder sdk.dir in android/local.properties prüfen.'

# Use the newest installed stable build-tools with all required packaging tools.
android_build_tools=''
while IFS= read -r candidate; do
  candidate_version="${candidate##*/}"
  if [[ "$candidate_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] && \
      [[ -x "$candidate/apksigner" && -x "$candidate/zipalign" && -x "$candidate/aapt2" ]]; then
    android_build_tools="$candidate"
  fi
done < <(printf '%s\n' "$android_sdk"/build-tools/* | LC_ALL=C sort -V)
[[ -n "$android_build_tools" ]] || fail 'Android Build Tools mit apksigner, zipalign und aapt2 fehlen.'

flutter pub get --enforce-lockfile
flutter build apk --no-pub --release --target-platform android-arm64 \
  --build-name=0.2.3 --build-number=6 \
  --dart-define=AKRIBOS_SERVER=https://akribos.de

unsigned_apk='build/app/outputs/flutter-apk/app-release.apk'
[[ -f "$unsigned_apk" ]] || fail "Release-APK fehlt: $unsigned_apk"

mkdir -p artifacts
packaging_directory="$(mktemp -d "$app_root/artifacts/.android-release.XXXXXX")"
trap 'rm -rf -- "$packaging_directory"' EXIT
aligned_apk="$packaging_directory/aligned.apk"
signed_apk="$packaging_directory/signed.apk"

# AGP normally aligns the APK already. Repair alignment only before signing.
if "$android_build_tools/zipalign" -c -P 16 4 "$unsigned_apk"; then
  cp -- "$unsigned_apk" "$aligned_apk"
else
  "$android_build_tools/zipalign" -P 16 -f 4 "$unsigned_apk" "$aligned_apk"
fi

# These are Android's public default debug-key credentials, not store credentials.
"$android_build_tools/apksigner" sign --ks "$android_keystore" \
  --ks-key-alias androiddebugkey --ks-pass pass:android --key-pass pass:android \
  --v4-signing-enabled false --out "$signed_apk" "$aligned_apk"
"$android_build_tools/zipalign" -c -P 16 4 "$signed_apk"
"$android_build_tools/apksigner" verify --print-certs "$signed_apk" \
  > "$packaging_directory/signer.txt"
signed_sha256="$(sed -n 's/^.*certificate SHA-256 digest: //p' \
  "$packaging_directory/signer.txt" | LC_ALL=C sort -u)"
[[ "$signed_sha256" == "$expected_signer_sha256" ]] || \
  fail 'Die signierte APK besitzt nicht die erwartete Build-2-Signatur.'

apk_metadata="$("$android_build_tools/aapt2" dump badging "$signed_apk")"
[[ "$apk_metadata" == *"package: name='de.akribos.app' versionCode='6' versionName='0.2.3'"* ]] || \
  fail 'Paketname oder Version der APK entspricht nicht de.akribos.app / 0.2.3+6.'
[[ "$apk_metadata" != *'application-debuggable'* ]] || \
  fail 'Die erzeugte APK ist unerwartet debuggable.'
[[ "$apk_metadata" == *"native-code: 'arm64-v8a'"* ]] || \
  fail 'Die erzeugte APK hat nicht die erwartete ARM64-Architektur.'

artifact_name='akribos-0.2.3-akribos-de-release.apk'
install -m 644 "$signed_apk" "artifacts/$artifact_name"
install -m 644 "$packaging_directory/signer.txt" "artifacts/$artifact_name.signer.txt"
(
  cd artifacts
  sha256sum "$artifact_name" > "$artifact_name.sha256"
  cat "$artifact_name.sha256"
)
printf 'AOT-Release 0.2.3+6 für https://akribos.de fertig; Signatur entspricht Build 2.\n'
printf 'APK: %s/artifacts/%s\n' "$app_root" "$artifact_name"
