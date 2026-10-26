#!/usr/bin/env python3
"""Build an existing published Akribos release and upload it only to TestFlight."""
import argparse
import base64
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import secrets
import shlex
import shutil
import subprocess
import sys
import tempfile
import time
from urllib.error import HTTPError
from urllib.parse import quote, urlencode, urlsplit
from urllib.request import HTTPRedirectHandler, Request, build_opener
import zipfile

import play_release as common
from play_release import ReleaseError, require, secret

TEAM = "8Y4NL9VW33"
APP = "6827126169"
BUNDLE = "de.akribos.app"
PREFIX = "testflight-build-ios-"
API = "https://api.appstoreconnect.apple.com"
SOURCE = Path("release-source")
ARTIFACTS = Path("build/testflight")
MANIFEST = ARTIFACTS / "release.json"


def run(args, **kwargs):
    """Capture credential-bearing command lines/output; never echo them in CI."""
    result = subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE, **kwargs)
    if result.returncode:
        # Report provider error numbers, never raw output that could contain credentials.
        codes = sorted(set(re.findall(r'ITMS-\d+|"code"\s*:\s*-?\d+',
                                      (result.stdout + result.stderr).decode(errors="replace"))))
        raise ReleaseError(f"{Path(args[0]).name} failed (exit {result.returncode}; "
                           f"codes: {', '.join(codes) or 'none'}); inspect signing/build configuration.")
    return result.stdout


def output(values):
    with open(secret("GITHUB_OUTPUT"), "a") as stream:
        for name, value in values.items():
            stream.write(f"{name}={value}\n")


def identity():
    sha = secret("GITHUB_SHA")
    require(re.fullmatch(r"[0-9a-f]{40}", sha), "Invalid workflow commit.")
    require(os.environ.get("GITHUB_REF") == "refs/heads/main"
            and os.environ.get("GITHUB_EVENT_NAME") == "workflow_dispatch",
            "TestFlight must be dispatched from main.")
    require(run(["git", "rev-parse", "HEAD"]).decode().strip() == sha,
            "Release tooling checkout differs from workflow commit.")
    require(common.gh("GET", "/git/ref/heads/main")["object"]["sha"] == sha,
            "main advanced; dispatch the current trusted workflow again.")
    tag = secret("RELEASE_TAG")
    require(tag.startswith("v"), "Expected a published vX.Y.Z release tag.")
    version = common.version(tag[1:])
    release = common.gh("GET", "/releases/tags/" + quote(tag, safe=""))
    require(release.get("published_at") and not release.get("draft")
            and not release.get("prerelease"), "Release is not published and stable.")
    source = common.commit_for_tag(tag)
    require(re.fullmatch(r"[0-9a-f]{40}", source), "Invalid release commit.")
    comparison = common.gh("GET", f"/compare/{source}...{sha}")
    require(comparison.get("status") in {"ahead", "identical"}
            and comparison.get("merge_base_commit", {}).get("sha") == source,
            "Published source is not an ancestor of trusted main.")
    return {"version": version, "tag": tag, "sourceCommit": source,
            "workflowCommit": sha, "releaseId": release["id"], "appId": APP,
            "bundleId": BUNDLE, "teamId": TEAM, "origin": common.ORIGIN}


def gate(wait=False, timeout=45 * 60):
    initial = identity()
    deadline = time.monotonic() + timeout
    while True:
        require(identity() == initial, "Release identity changed during CI verification.")
        pending = False
        for sha in set((initial["workflowCommit"], initial["sourceCommit"])):
            latest = common.latest_ci_run(sha)
            if latest and latest.get("status") == "completed":
                require(latest.get("conclusion") == "success", "Latest exact-commit CI failed.")
            else:
                require(not latest or latest.get("status") in {
                    "requested", "waiting", "pending", "queued", "in_progress"},
                    "Unexpected CI status.")
                pending = True
        if not pending:
            return initial
        require(wait and time.monotonic() < deadline, "Exact source/workflow CI has not succeeded.")
        print("Waiting for source and workflow main-push CI.", flush=True)
        time.sleep(min(30, max(0, deadline - time.monotonic())))


def write_manifest(data):
    ARTIFACTS.mkdir(parents=True, exist_ok=True)
    MANIFEST.write_text(json.dumps(data, indent=2) + "\n")


def checked_plan():
    data = json.loads(MANIFEST.read_text())
    require(all(data.get(key) == value for key, value in gate().items()),
            "Plan no longer matches the published release/current main.")
    require(run(["git", "-C", str(SOURCE), "rev-parse", "HEAD"]).decode().strip()
            == data["sourceCommit"], "App checkout differs from the release tag.")
    return data


def b64url(data):
    return base64.urlsafe_b64encode(data).decode().rstrip("=")


def raw_ec_signature(der):
    # P-256 ECDSA ASN.1 SEQUENCE of two positive INTEGERs -> JWT's fixed R || S.
    require(len(der) >= 8 and der[0] == 48 and der[1] == len(der) - 2, "Invalid ECDSA signature.")
    cursor, parts = 2, []
    for _ in range(2):
        require(cursor + 2 <= len(der) and der[cursor] == 2, "Invalid ECDSA integer.")
        length = der[cursor + 1]
        value = der[cursor + 2:cursor + 2 + length]
        require(value and len(value) == length, "Truncated ECDSA integer.")
        value = value.lstrip(b"\0")
        require(len(value) <= 32, "Unexpected signing key curve; expected P-256.")
        parts.append(value.rjust(32, b"\0"))
        cursor += length + 2
    require(cursor == len(der), "Unexpected ECDSA signature data.")
    return b"".join(parts)


def jwt():
    now = int(time.time())
    key_id = secret("ASC_KEY_ID")
    require(re.fullmatch(r"[A-Z0-9]{10}", key_id), "Invalid Apple API key ID.")
    header = {"alg": "ES256", "kid": key_id, "typ": "JWT"}
    payload = {"iss": secret("ASC_ISSUER_ID"), "iat": now - 10,
               "exp": now + 300, "aud": "appstoreconnect-v1"}
    message = ".".join(b64url(json.dumps(item, separators=(",", ":")).encode())
                       for item in (header, payload))
    with tempfile.TemporaryDirectory() as directory:
        key = Path(directory) / "key.p8"
        key.write_text(secret("ASC_PRIVATE_KEY") + "\n")
        key.chmod(0o600)
        signature = run(["openssl", "dgst", "-sha256", "-sign", str(key)], input=message.encode())
    return message + "." + b64url(raw_ec_signature(signature))


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def apple_url(path):
    url = API + path if path.startswith("/v1/") else path
    parsed = urlsplit(url)
    require(parsed.scheme == "https" and parsed.netloc == "api.appstoreconnect.apple.com"
            and parsed.path.startswith("/v1/") and not parsed.fragment,
            "Refusing an unexpected Apple API/pagination destination.")
    return url


class Apple:
    def request(self, method, path, body=None):
        request = Request(apple_url(path), method=method,
                          data=None if body is None else json.dumps(body).encode(),
                          headers={"Authorization": "Bearer " + jwt(), "Content-Type": "application/json"})
        try:
            with build_opener(NoRedirect()).open(request, timeout=45) as response:
                raw = response.read()
                return json.loads(raw) if raw else {}
        except HTTPError as error:
            raise ReleaseError(f"Apple API {method} failed (HTTP {error.code}).") from None

    def all(self, path):
        items, seen = [], set()
        while path:
            require(path not in seen and len(seen) < 1000, "Unexpected Apple pagination loop/size.")
            seen.add(path)
            response = self.request("GET", path)
            items.extend(response["data"])
            path = response.get("links", {}).get("next")
        return items


def build_number(value):
    require(re.fullmatch(r"[1-9]\d{0,8}", str(value)), "Expected an integer iOS build number.")
    return int(value)


def reserve(minimum, source):
    refs = common.gh("GET", "/git/matching-refs/tags/" + PREFIX)
    previous = [build_number(match[1]) for ref in refs
                if (match := re.fullmatch(r"refs/tags/" + PREFIX + r"(\d+)", ref["ref"]))]
    number = build_number(max([minimum, *previous]) + 1)
    # A collision/error fails closed. Never delete or recycle a reservation.
    common.gh("POST", "/git/refs", {"ref": "refs/tags/" + PREFIX + str(number), "sha": source})
    return number


def plan():
    data = gate()
    api = Apple()
    app = api.request("GET", f"/v1/apps/{APP}")["data"]
    require(app["id"] == APP and app["attributes"]["bundleId"] == BUNDLE,
            "Apple app does not match the intended bundle.")
    builds = api.all("/v1/builds?" + urlencode({"filter[app]": APP, "limit": 200}))
    maximum = max([0, *(build_number(item["attributes"]["version"]) for item in builds)])
    exempt = os.environ.get("ENCRYPTION_EXEMPT", "false")
    require(exempt in {"true", "false"}, "Invalid encryption declaration input.")
    data.update(build=reserve(maximum, data["sourceCommit"]), uploaded=False,
                encryptionExemptDeclaration=exempt == "true",
                processingVerified=False, uploadAttempted=False)
    write_manifest(data)
    output({"version": data["version"], "build": data["build"]})
    print(f"Reserved iOS {data['version']} ({data['build']}).")


def private_dir():
    path = Path(secret("RUNNER_TEMP")) / "akribos-ios-signing"
    path.mkdir(mode=0o700, exist_ok=True)
    return path


def protected_write(path, data):
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(descriptor, "wb") as stream:
        stream.write(data)
    path.chmod(0o600)


def validate_profile(profile, certificate=None):
    entitlements = profile["Entitlements"]
    require(profile["TeamIdentifier"] == [TEAM]
            and entitlements["application-identifier"] == TEAM + "." + BUNDLE
            and entitlements["com.apple.developer.team-identifier"] == TEAM,
            "Provisioning profile belongs to another app/team.")
    require(entitlements.get("get-task-allow") is False
            and entitlements.get("beta-reports-active") is True
            and "ProvisionedDevices" not in profile and not profile.get("ProvisionsAllDevices"),
            "Expected an App Store distribution profile, not development/ad hoc.")
    domains = entitlements.get("com.apple.developer.associated-domains", [])
    require("*" in domains or "applinks:akribos.de" in domains, "Associated Domains missing from profile.")
    require(profile["ExpirationDate"].replace(tzinfo=timezone.utc) > datetime.now(timezone.utc),
            "Provisioning profile has expired.")
    require(re.fullmatch(r"[0-9a-fA-F-]{36}", profile["UUID"]), "Invalid profile UUID.")
    if certificate is not None:
        require(certificate in profile["DeveloperCertificates"], "Signing certificate is absent from profile.")


def prepare_signing():
    data = checked_plan()
    directory = private_dir()
    p12, profile_file = directory / "distribution.p12", directory / "profile.mobileprovision"
    protected_write(p12, base64.b64decode(secret("IOS_CERTIFICATE_P12_BASE64"), validate=True))
    protected_write(profile_file, base64.b64decode(secret("IOS_PROVISIONING_PROFILE_BASE64"), validate=True))
    profile = plistlib.loads(run(["security", "cms", "-D", "-i", str(profile_file)]))
    validate_profile(profile)
    keychain = directory / "signing.keychain-db"
    originals = shlex.split(run(["security", "list-keychains", "-d", "user"]).decode())
    installed = Path.home() / "Library/MobileDevice/Provisioning Profiles" / (profile["UUID"] + ".mobileprovision")
    require(not installed.exists(), "Refusing to replace an existing provisioning profile.")
    # Record cleanup state before creating/importing anything; failures still clean up.
    protected_write(directory / "cleanup.json", json.dumps({"keychain": str(keychain),
                    "originals": originals, "profile": str(installed)}).encode())
    password = secrets.token_urlsafe(32)
    run(["security", "create-keychain", "-p", password, str(keychain)])
    run(["security", "set-keychain-settings", "-lut", "7200", str(keychain)])
    run(["security", "unlock-keychain", "-p", password, str(keychain)])
    run(["security", "import", str(p12), "-P", secret("IOS_CERTIFICATE_PASSWORD"),
         "-k", str(keychain), "-T", "/usr/bin/codesign", "-T", "/usr/bin/security"])
    run(["security", "set-key-partition-list", "-S", "apple-tool:,apple:,codesign:",
         "-s", "-k", password, str(keychain)])
    run(["security", "list-keychains", "-d", "user", "-s", str(keychain), *originals])
    identities = run(["security", "find-identity", "-v", "-p", "codesigning", str(keychain)]).decode()
    certificates = [cert for cert in profile["DeveloperCertificates"]
                    if hashlib.sha1(cert).hexdigest().upper() in identities]
    require(len(certificates) == 1, "No unique usable private-key identity matches the profile.")
    validate_profile(profile, certificates[0])
    installed.parent.mkdir(parents=True, exist_ok=True)
    protected_write(installed, profile_file.read_bytes())
    fingerprint = hashlib.sha1(certificates[0]).hexdigest().upper()
    options = {"method": "app-store-connect", "destination": "export", "teamID": TEAM,
               "signingStyle": "manual", "signingCertificate": fingerprint,
               "provisioningProfiles": {BUNDLE: profile["UUID"]},
               "manageAppVersionAndBuildNumber": False, "uploadSymbols": True}
    protected_write(directory / "ExportOptions.plist", plistlib.dumps(options))
    # Only the Runner release configuration consumes this file; Pods retain their settings.
    config = SOURCE / "ios/Flutter/Release.xcconfig"
    with config.open("a") as stream:
        stream.write(f"\nDEVELOPMENT_TEAM = {TEAM}\nCODE_SIGN_STYLE = Manual\n"
                     f"CODE_SIGN_IDENTITY = {fingerprint}\n"
                     f"PROVISIONING_PROFILE_SPECIFIER = {profile['UUID']}\n")
    if data["encryptionExemptDeclaration"]:
        # Explicit per-dispatch operator declaration; no blanket claim for future releases.
        info_path = SOURCE / "ios/Runner/Info.plist"
        info = plistlib.loads(info_path.read_bytes())
        info["ITSAppUsesNonExemptEncryption"] = False
        info_path.write_bytes(plistlib.dumps(info))
    data.update(profileUuid=profile["UUID"], signingCertificateSha1=fingerprint)
    write_manifest(data)
    p12.unlink()
    print("Distribution identity and App Store profile validated in temporary keychain.")


def build():
    data = checked_plan()
    directory = private_dir()
    # Stream build output (no credentials in this step/environment).
    subprocess.run(["flutter", "build", "ipa", "--release", "--no-pub",
                    "--build-name=" + data["version"], "--build-number=" + str(data["build"]),
                    "--dart-define=AKRIBOS_SERVER=" + common.ORIGIN,
                    "--export-options-plist=" + str((directory / "ExportOptions.plist").resolve())],
                   cwd=SOURCE, check=True)
    ipas = list((SOURCE / "build/ios/ipa").glob("*.ipa"))
    require(len(ipas) == 1, "Expected exactly one exported IPA.")
    ipa = ARTIFACTS / f"akribos-{data['version']}-{data['build']}.ipa"
    shutil.copyfile(ipas[0], ipa)
    with zipfile.ZipFile(ipa) as archive:
        infos = [n for n in archive.namelist() if re.fullmatch(r"Payload/[^/]+\.app/Info.plist", n)]
        require(len(infos) == 1, "Unexpected IPA application layout.")
        info = plistlib.loads(archive.read(infos[0]))
        require(info["CFBundleIdentifier"] == BUNDLE
                and info["CFBundleShortVersionString"] == data["version"]
                and str(info["CFBundleVersion"]) == str(data["build"]),
                "IPA identity/version differs from reserved release.")
    exported = directory / "verified-ipa"
    run(["ditto", "-x", "-k", str(ipa), str(exported)])
    apps = list((exported / "Payload").glob("*.app"))
    require(len(apps) == 1, "Unexpected exported app count.")
    app = apps[0]
    run(["codesign", "--verify", "--deep", "--strict", str(app)])
    entitlements = plistlib.loads(run(["codesign", "-d", "--entitlements", ":-", str(app)]))
    require(entitlements["application-identifier"] == TEAM + "." + BUNDLE
            and not entitlements.get("get-task-allow")
            and "applinks:akribos.de" in entitlements.get("com.apple.developer.associated-domains", []),
            "Signed IPA entitlements differ from production app.")
    embedded = plistlib.loads(run(["security", "cms", "-D", "-i", str(app / "embedded.mobileprovision")]))
    validate_profile(embedded)
    require(embedded["UUID"] == data["profileUuid"], "IPA contains another provisioning profile.")
    shutil.rmtree(exported)
    dsym = SOURCE / "build/ios/archive/Runner.xcarchive/dSYMs"
    if dsym.is_dir():
        shutil.make_archive(str(ARTIFACTS / "dSYMs"), "zip", dsym)
    data.update(ipa=ipa.name, sha256=hashlib.sha256(ipa.read_bytes()).hexdigest())
    write_manifest(data)
    (ARTIFACTS / (ipa.name + ".sha256")).write_text(data["sha256"] + "  " + ipa.name + "\n")
    print("Signed IPA version, entitlements and checksum verified.")


def find_processed_build(api, data, timeout=35 * 60):
    deadline = time.monotonic() + timeout
    path = "/v1/builds?" + urlencode({"filter[app]": APP, "filter[version]": data["build"],
                                    "filter[preReleaseVersion.version]": data["version"],
                                    "filter[preReleaseVersion.platform]": "IOS", "limit": 200})
    while True:
        builds = api.all(path)
        require(len(builds) <= 1, "Ambiguous Apple build identity.")
        if builds:
            item = builds[0]
            state = item["attributes"]["processingState"]
            data.update(appleBuildId=item["id"], appleProcessingState=state)
            write_manifest(data)
            require(state not in {"FAILED", "INVALID"}, "Apple rejected the uploaded build; inspect TestFlight.")
            if state == "VALID":
                require(not item["attributes"].get("expired"), "Apple build is expired.")
                return item
            require(state == "PROCESSING", "Unknown Apple processing state.")
        require(time.monotonic() < deadline,
                "Upload accepted; Apple processing is still pending. Inspect TestFlight before any retry.")
        print("Upload accepted; waiting for this exact Apple build to finish processing.", flush=True)
        time.sleep(min(30, max(0, deadline - time.monotonic())))


def publish():
    data = checked_plan()
    ipa = ARTIFACTS / data["ipa"]
    require(hashlib.sha256(ipa.read_bytes()).hexdigest() == data["sha256"], "IPA changed after verification.")
    require(not data["uploadAttempted"], "Upload already attempted; inspect Apple before retrying.")
    api = Apple()
    existing = api.all("/v1/builds?" + urlencode({"filter[app]": APP, "limit": 200}))
    require(all(build_number(item["attributes"]["version"]) < data["build"] for item in existing),
            "Apple builds advanced since reservation; reserve a new build number.")
    directory = private_dir()
    # altool discovers AuthKey_<ID>.p8 in API_PRIVATE_KEYS_DIR.
    key = directory / ("AuthKey_" + secret("ASC_KEY_ID") + ".p8")
    protected_write(key, (secret("ASC_PRIVATE_KEY") + "\n").encode())
    env = dict(os.environ, API_PRIVATE_KEYS_DIR=str(directory.resolve()))
    args = ["xcrun", "altool", "--type", "ios", "-f", str(ipa),
            "--apiKey", secret("ASC_KEY_ID"), "--apiIssuer", secret("ASC_ISSUER_ID"),
            "--output-format", "json"]
    validation = run([*args, "--validate-app"], env=env)
    require(not json.loads(validation).get("product-errors"), "Apple IPA validation failed.")
    checked_plan()  # No waiting immediately before the irreversible upload.
    data["uploadAttempted"] = True
    write_manifest(data)
    uploaded = run([*args, "--upload-app"], env=env)
    require(not json.loads(uploaded).get("product-errors"), "Apple upload failed; inspect before retrying.")
    data["uploaded"] = True
    write_manifest(data)
    item = find_processed_build(api, data)
    data.update(processingVerified=True,
                usesNonExemptEncryption=item["attributes"].get("usesNonExemptEncryption"))
    detail = api.request("GET", "/v1/builds/" + item["id"] + "/buildBetaDetail")["data"]["attributes"]
    data.update(internalBuildState=detail.get("internalBuildState"),
                externalBuildState=detail.get("externalBuildState"))
    groups = api.all("/v1/builds/" + item["id"] + "/betaGroups?limit=200")
    data["internalGroups"] = [g["attributes"]["name"] for g in groups if g["attributes"].get("isInternalGroup")]
    write_manifest(data)
    print(f"Apple processing VALID. Internal state: {data['internalBuildState']}. "
          "No public release or external beta review was requested.")
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as stream:
            stream.write(f"Akribos **{data['version']} ({data['build']})** uploaded; processing **VALID**.\n\n"
                         f"Internal TestFlight state: **{data['internalBuildState']}**.\n\n"
                         f"[Open TestFlight](https://appstoreconnect.apple.com/apps/{APP}/testflight)\n")


def cleanup():
    directory = Path(secret("RUNNER_TEMP")) / "akribos-ios-signing"
    state = directory / "cleanup.json"
    failures = []
    if state.exists():
        data = json.loads(state.read_text())
        for args in (["security", "list-keychains", "-d", "user", "-s", *data["originals"]],
                     ["security", "delete-keychain", data["keychain"]]):
            if subprocess.run(args, capture_output=True).returncode:
                failures.append(args[1])
        Path(data["profile"]).unlink(missing_ok=True)
    shutil.rmtree(directory, ignore_errors=False) if directory.exists() else None
    require(not failures, "Temporary keychain cleanup failed; hosted runner will be discarded.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["wait-for-ci", "plan", "prepare-signing", "build", "publish", "cleanup"])
    args = parser.parse_args()
    try:
        if args.action == "wait-for-ci":
            data = gate(wait=True)
            output({"source_commit": data["sourceCommit"]})
        else:
            {"plan": plan, "prepare-signing": prepare_signing, "build": build,
             "publish": publish, "cleanup": cleanup}[args.action]()
    except ReleaseError as error:
        print(f"TestFlight stopped: {error}", file=sys.stderr)
        return 1
    except Exception as error:
        print(f"TestFlight stopped ({type(error).__name__}); inspect configuration and Apple status.", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
