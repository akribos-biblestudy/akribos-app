#!/usr/bin/env python3
"""Akribos Android Internal Testing: guarded releases, reservations, signing, upload."""
import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time
from urllib.error import HTTPError
from urllib.parse import quote
from urllib.request import Request, urlopen
import xml.etree.ElementTree as ET

PACKAGE = "de.akribos.app"
ORIGIN = "https://akribos.de"
PREFIX = "play-build-android-"
MAX_CODE = 2_100_000_000
ARTIFACTS = Path("build/play-store")
MANIFEST = ARTIFACTS / "release.json"
API = "https://androidpublisher.googleapis.com/androidpublisher/v3/applications/" + PACKAGE


class ReleaseError(Exception):
    pass


def require(condition, message):
    if not condition:
        raise ReleaseError(message)


def secret(name):
    value = os.environ.get(name, "").strip()
    require(value, f"Missing configuration: {name}")
    return value


def version(value):
    require(re.fullmatch(r"(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)", value),
            "Version must be X.Y.Z without prefixes or build metadata.")
    return value


def code(value):
    require(re.fullmatch(r"[1-9]\d*", str(value)), "Invalid Android version code.")
    number = int(value)
    require(number <= MAX_CODE, "Android version code limit reached.")
    return number


def gh(method, path, body=None, *, allow_empty=False):
    request = Request("https://api.github.com/repos/" + secret("GITHUB_REPOSITORY") + path,
                      method=method, data=None if body is None else json.dumps(body).encode(),
                      headers={"Authorization": "Bearer " + secret("GH_TOKEN"),
                               "Accept": "application/vnd.github+json",
                               "Content-Type": "application/json",
                               "X-GitHub-Api-Version": "2026-03-10"})
    try:
        with urlopen(request, timeout=45) as response:
            content = response.read()
            if not content:
                require(allow_empty, "GitHub API returned an empty response.")
                return None
            return json.loads(content)
    except HTTPError as error:
        # Never print raw provider responses, request headers or credentials.
        raise ReleaseError(f"GitHub API {method} failed (HTTP {error.code}).") from None


def commit_for_tag(tag):
    obj = gh("GET", "/git/ref/tags/" + quote(tag, safe=""))["object"]
    for _ in range(5):
        if obj["type"] == "commit":
            return obj["sha"]
        require(obj["type"] == "tag", "Release tag does not point to a commit.")
        obj = gh("GET", "/git/tags/" + obj["sha"])["object"]
    raise ReleaseError("Release tag nesting is too deep.")


def release_identity():
    sha = secret("GITHUB_SHA")
    require(subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip() == sha,
            "Checkout differs from the event commit.")
    main = gh("GET", "/git/ref/heads/main")["object"]["sha"]
    require(main == sha, "main advanced or this is not current main; release its checked commit.")
    require(os.environ.get("GITHUB_EVENT_NAME") == "workflow_dispatch"
            and os.environ.get("GITHUB_REF") == "refs/heads/main",
            "The protected store workflow must run from main.")
    tag = os.environ.get("RELEASE_TAG", "").strip()
    bootstrap = os.environ.get("BOOTSTRAP_VERSION", "").strip()
    require(bool(tag) != bool(bootstrap), "Choose exactly one published release tag or bootstrap version.")
    release_id = None
    if tag:
        require(tag.startswith("v"), "Use a published vX.Y.Z release.")
        name = version(tag[1:])
        published = gh("GET", "/releases/tags/" + quote(tag, safe=""))
        require(not published.get("draft") and not published.get("prerelease")
                and published.get("published_at"),
                "Release must remain published, non-draft and non-prerelease.")
        require(commit_for_tag(tag) == sha, "Release tag moved or does not match current main.")
        release_id = published["id"]
        mode = "publish"
    else:
        require(os.environ.get("PLAY_BOOTSTRAP_ALLOWED") == "true",
                "Bootstrap is disabled. Enable only for the first manual Play bundle.")
        name = version(bootstrap)
        mode, tag = "bootstrap", None
    return {"mode": mode, "version": name, "commit": sha, "tag": tag,
            "package": PACKAGE, "origin": ORIGIN, "track": "internal", "releaseId": release_id}


def latest_ci_run(sha):
    runs = gh("GET", "/actions/workflows/ci.yml/runs?branch=main&event=push&head_sha="
              + sha + "&per_page=100").get("workflow_runs", [])
    matching = [r for r in runs if r.get("head_sha") == sha and r.get("event") == "push"
                and r.get("head_branch") == "main"]
    return max(matching, key=lambda r: r["id"]) if matching else None


def gate():
    result = release_identity()
    latest = latest_ci_run(result["commit"])
    require(latest is not None, "No push CI exists for this exact main commit; wait for Flutter CI.")
    require(latest.get("status") == "completed" and latest.get("conclusion") == "success",
            "Latest Flutter CI for this exact main commit has not succeeded.")
    return result


def wait_for_ci(timeout_seconds=45 * 60, poll_seconds=30):
    """Wait only at workflow entry; all later publication gates stay immediate."""
    require(timeout_seconds > 0 and poll_seconds > 0, "CI wait intervals must be positive.")
    deadline = time.monotonic() + timeout_seconds
    initial = None
    while True:
        # Recheck checkout, main, tag and published release before every CI poll.
        current = release_identity()
        if initial is None:
            initial = current
        require(current == initial, "Release identity changed while waiting for Flutter CI.")
        latest = latest_ci_run(current["commit"])
        if latest is not None:
            status = latest.get("status")
            if status == "completed":
                require(latest.get("conclusion") == "success",
                        "Latest Flutter CI for this exact main commit finished without success.")
                print("Flutter CI succeeded for the exact release commit.")
                return current
            require(status in {"requested", "waiting", "pending", "queued", "in_progress"},
                    "Latest Flutter CI has an unexpected status; inspect its run before retrying.")
        remaining = deadline - time.monotonic()
        require(remaining > 0,
                "Timed out waiting for Flutter CI for this exact main commit; inspect its run and retry the release workflow.")
        print("Waiting for Flutter CI for the exact release commit.", flush=True)
        time.sleep(min(poll_seconds, remaining))


class Play:
    def __init__(self):
        from google.oauth2 import service_account
        from google.auth.transport.requests import AuthorizedSession
        try:
            info = json.loads(secret("PLAY_SERVICE_ACCOUNT_JSON"))
            require(info.get("type") == "service_account", "Expected service-account JSON.")
            # Credentials must never redirect an OAuth assertion to a foreign token endpoint.
            require(info.get("token_uri") == "https://oauth2.googleapis.com/token",
                    "Unexpected Google OAuth token endpoint.")
            credentials = service_account.Credentials.from_service_account_info(
                info, scopes=["https://www.googleapis.com/auth/androidpublisher"])
            self.session = AuthorizedSession(credentials)
        except ReleaseError:
            raise
        except Exception:
            raise ReleaseError("Invalid Google Play service-account configuration.") from None

    def request(self, method, path, *, body=None, bundle=None):
        url = API + path
        kwargs = {"json": body} if bundle is None else {
            "data": bundle, "headers": {"Content-Type": "application/octet-stream"}}
        if bundle is not None:
            url = url.replace("/androidpublisher/v3/", "/upload/androidpublisher/v3/") + "?uploadType=media"
        try:
            response = self.session.request(method, url, timeout=240, allow_redirects=False, **kwargs)
        except Exception:
            raise ReleaseError("Google Play request failed; check connectivity and service-account access.") from None
        require(200 <= response.status_code < 300,
                f"Google Play {method} failed (HTTP {response.status_code}); check API access, first manual upload and Play Console.")
        return response.json() if response.content else {}

    def new_edit(self):
        return self.request("POST", "/edits", body={})["id"]

    def discard(self, edit):
        self.request("DELETE", "/edits/" + edit)

    def versions(self, edit):
        base = "/edits/" + edit
        numbers = []
        for resource in ["bundles", "apks"]:
            numbers.extend(code(item["versionCode"]) for item in
                           self.request("GET", base + "/" + resource).get(resource, []))
        for track in self.request("GET", base + "/tracks").get("tracks", []):
            for release in track.get("releases", []):
                numbers.extend(code(value) for value in release.get("versionCodes", []))
        return numbers


def store_maximum(play):
    edit = play.new_edit()
    try:
        numbers = play.versions(edit)
        require(numbers, "No Play version exists. Complete the first manual Internal Testing upload.")
        return max(numbers)
    finally:
        play.discard(edit)


def reserve(minimum, sha):
    for _ in range(8):
        refs = gh("GET", "/git/matching-refs/tags/" + PREFIX)
        numbers = [int(match[1]) for ref in refs
                   if (match := re.fullmatch(r"refs/tags/" + PREFIX + r"(\d+)", ref["ref"]))]
        number = code(max([minimum, *numbers]) + 1)
        try:
            gh("POST", "/git/refs", {"ref": "refs/tags/" + PREFIX + str(number), "sha": sha})
            return number
        except ReleaseError:
            # Only a real collision is retriable. Permission/policy errors stay failures.
            gh("GET", "/git/ref/tags/" + PREFIX + str(number))
    raise ReleaseError("Could not reserve a unique Android build number.")


def write_manifest(data):
    ARTIFACTS.mkdir(parents=True, exist_ok=True)
    MANIFEST.write_text(json.dumps(data, indent=2) + "\n")


def plan():
    result = gate()
    minimum = max(12, code(secret("PLAY_VERSION_CODE_FLOOR")))
    if result["mode"] == "publish":
        minimum = max(minimum, store_maximum(Play()))
    result.update(build=reserve(minimum, result["commit"]), storeUploaded=False,
                  internalTrackVerified=False)
    write_manifest(result)
    with open(secret("GITHUB_OUTPUT"), "a") as output:
        for key in ["version", "build", "mode", "commit"]:
            output.write(f"{key}={result[key]}\n")
    print(f"Reserved Android {result['version']}+{result['build']} ({result['mode']}).")


def checked_plan():
    result = json.loads(MANIFEST.read_text())
    current = gate()
    require(all(result.get(key) == value for key, value in current.items()),
            "Release identity changed after reservation.")
    code(result["build"])
    require(gh("GET", "/git/ref/tags/" + PREFIX + str(result["build"]))["object"]["sha"]
            == result["commit"], "Build reservation does not match this commit.")
    return result


def command(arguments, *, accepted=(0,)):
    process = subprocess.run(arguments, capture_output=True)
    require(process.returncode in accepted, f"{Path(arguments[0]).name} failed; signing/build inputs were not printed.")
    return process.stdout


def sign():
    result = checked_plan()
    temporary = Path(secret("RUNNER_TEMP")) / "akribos-upload.jks"
    try:
        raw = base64.b64decode(secret("ANDROID_UPLOAD_KEYSTORE_BASE64"), validate=True)
    except ValueError:
        raise ReleaseError("Upload keystore is not valid base64.") from None
    with temporary.open("wb") as output:
        os.chmod(temporary, 0o600)
        output.write(raw)
    alias = secret("ANDROID_UPLOAD_KEY_ALIAS")
    secret("ANDROID_UPLOAD_STORE_PASSWORD")
    secret("ANDROID_UPLOAD_KEY_PASSWORD")
    cert = command(["keytool", "-exportcert", "-keystore", str(temporary), "-alias", alias,
                    "-storepass:env", "ANDROID_UPLOAD_STORE_PASSWORD"])
    fingerprint = hashlib.sha256(cert).hexdigest()
    expected = secret("ANDROID_UPLOAD_CERT_SHA256").replace(":", "").lower()
    require(re.fullmatch(r"[a-f0-9]{64}", expected) and fingerprint == expected,
            "Upload certificate differs from the configured fingerprint.")
    from cryptography import x509
    from cryptography.x509.oid import NameOID
    certificate = x509.load_der_x509_certificate(cert)
    require(not any(name.value == "Android Debug" for name in certificate.subject.get_attributes_for_oid(NameOID.COMMON_NAME)),
            "A debug signing key cannot be used for Google Play.")
    bundle = ARTIFACTS / f"akribos-{result['version']}-{result['build']}.aab"
    command(["jarsigner", "-keystore", str(temporary), "-storepass:env", "ANDROID_UPLOAD_STORE_PASSWORD",
             "-keypass:env", "ANDROID_UPLOAD_KEY_PASSWORD", "-signedjar", str(bundle),
             "build/app/outputs/bundle/release/app-release.aab", alias])
    # Self-signed upload certificates cause strict exit bit 4; unsigned entries/tampering must fail.
    command(["jarsigner", "-verify", "-strict", str(bundle)], accepted=(0, 4))
    from datetime import datetime, timezone
    require(certificate.not_valid_before_utc <= datetime.now(timezone.utc) < certificate.not_valid_after_utc,
            "Upload certificate is not currently valid.")
    manifest = ET.fromstring(command(["java", "-jar", secret("BUNDLETOOL_JAR"), "dump", "manifest", "--bundle=" + str(bundle)]))
    android = "{http://schemas.android.com/apk/res/android}"
    require(manifest.get("package") == PACKAGE and manifest.get(android + "versionCode") == str(result["build"])
            and manifest.get(android + "versionName") == result["version"], "AAB package/version does not match reservation.")
    application = manifest.find("application")
    require(application is not None and application.get(android + "debuggable", "false") == "false",
            "AAB must be a non-debuggable release.")
    digest = hashlib.sha256(bundle.read_bytes()).hexdigest()
    result.update(file=bundle.name, sha256=digest, uploadCertificateSha256=fingerprint)
    write_manifest(result)
    (ARTIFACTS / "SHA256SUMS").write_text(f"{digest}  {bundle.name}\n")
    print(f"Verified {bundle.name}, SHA-256 {digest}.")


def publish():
    result = checked_plan()
    require(result["mode"] == "publish", "Bootstrap never uploads to Play.")
    bundle = ARTIFACTS / result["file"]
    require(bundle.parent == ARTIFACTS and bundle.suffix == ".aab"
            and hashlib.sha256(bundle.read_bytes()).hexdigest() == result["sha256"], "Verified AAB changed.")
    play = Play()
    edit, committed = play.new_edit(), False
    try:
        require(result["build"] > max(play.versions(edit), default=0),
                "Play advanced since reservation; rerun for a new version code.")
        with bundle.open("rb") as stream:
            uploaded = play.request("POST", "/edits/" + edit + "/bundles", bundle=stream)
        require(code(uploaded["versionCode"]) == result["build"]
                and uploaded.get("sha256", "").lower() == result["sha256"],
                "Google Play received a different bundle/version.")
        play.request("PUT", "/edits/" + edit + "/tracks/internal", body={
            "track": "internal", "releases": [{"name": f"{result['version']} ({result['build']})",
                "versionCodes": [str(result["build"])], "status": "completed"}]})
        play.request("POST", "/edits/" + edit + ":validate", body={})
        # Final gate also catches main/tag changes while uploading. No forced review bypass.
        checked_plan()
        play.request("POST", "/edits/" + edit + ":commit", body={})
        committed = True
        result["storeUploaded"] = True
        write_manifest(result)
    finally:
        if not committed:
            play.discard(edit)
    verification = play.new_edit()
    try:
        track = play.request("GET", "/edits/" + verification + "/tracks/internal")
        require(any(str(result["build"]) in item.get("versionCodes", [])
                    and item.get("status") == "completed" for item in track.get("releases", [])),
                "Commit accepted, but Internal Testing readback is not yet confirmed; inspect Play Console before retrying.")
        result["internalTrackVerified"] = True
        write_manifest(result)
    finally:
        play.discard(verification)
    print("Google Play Internal Testing commit and version readback confirmed.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["gate", "wait-for-ci", "plan", "sign", "publish"])
    args = parser.parse_args()
    try:
        {"gate": gate, "wait-for-ci": wait_for_ci, "plan": plan, "sign": sign, "publish": publish}[args.action]()
    except ReleaseError as error:
        print(f"Release stopped: {error}", file=sys.stderr)
        return 1
    except Exception as error:
        # Avoid credential-bearing provider errors or subprocess arguments in CI logs.
        print(f"Release stopped ({type(error).__name__}); inspect configuration, CI and Play Console.", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
