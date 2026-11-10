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
INTERNAL_GROUP = "d6ef6dca-99e3-408a-953d-eaf0e6bd688b"  # Betatester
PREFIX = "testflight-build-ios-"
API = "https://api.appstoreconnect.apple.com"
SOURCE = Path("release-source")
ARTIFACTS = Path("build/testflight")
MANIFEST = ARTIFACTS / "release.json"
ENCRYPTION_ATTESTATION = Path("scripts/ios-encryption-attestation.json")
CRYPTO_IMPORT = re.compile(
    r'''(?m)^\s*(?:import|export|part)\s+[rR]?["'][^"']*(?:crypt|encrypt|cipher|secure_storage|keychain|ssl|tls|ffi|security)[^"']*["']''',
    re.IGNORECASE,
)


def run(args, **kwargs):
    """Capture credential-bearing command lines/output; never echo them in CI."""
    result = subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE, **kwargs)
    if result.returncode:
        # Report provider error numbers, never raw output that could contain credentials.
        codes = sorted(set(re.findall(r'ITMS-\d+|"code"\s*:\s*-?\d+',
                                      (result.stdout + result.stderr).decode(errors="replace"))))
        known = [message for message in (
            "MAC verification failed", "Mac verify error", "User interaction is not allowed",
            "The specified item could not be found", "The specified keychain could not be found",
            "A keychain with the same name already exists", "CSSMERR_TP_NOT_TRUSTED",
            "CSSMERR_TP_CERT_EXPIRED", "SecKeychainItemImport", "SecKeychainUnlock",
        ) if message.lower() in (result.stdout + result.stderr).decode(errors="replace").lower()]
        command = Path(args[0]).name
        if command == "security" and len(args) > 1:
            command += " " + args[1]  # Never print paths, passwords or full arguments.
        raise ReleaseError(f"{command} failed (exit {result.returncode}; "
                           f"codes: {', '.join(codes + known) or 'none'}); inspect signing/build configuration.")
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
    retried = None
    while True:
        require(identity() == initial, "Release identity changed during CI verification.")
        pending = False
        # Check the current trusted workflow CI first. A failure there must not
        # trigger a needless rerun of the older source CI.
        for sha in dict.fromkeys((initial["workflowCommit"], initial["sourceCommit"])):
            latest = common.latest_ci_run(sha)
            if latest and latest.get("status") == "completed":
                if latest.get("conclusion") == "success":
                    continue
                is_old_source = sha == initial["sourceCommit"] and sha != initial["workflowCommit"]
                if (wait and is_old_source and latest.get("conclusion") == "cancelled"
                        and retried is None):
                    run_id = latest.get("id")
                    attempt = latest.get("run_attempt", 1)
                    require(type(run_id) is int and run_id > 0
                            and type(attempt) is int and attempt > 0,
                            "Invalid cancelled CI run identity.")
                    # The tag/main and the exact latest push run may have changed
                    # while the initial query was running. Never rerun a stale run.
                    require(identity() == initial, "Release identity changed during CI verification.")
                    current = common.latest_ci_run(sha)
                    require(current and current.get("id") == run_id
                            and current.get("run_attempt", 1) == attempt
                            and current.get("status") == "completed"
                            and current.get("conclusion") == "cancelled",
                            "Source CI changed before rerun; retry the release.")
                    require(identity() == initial, "Release identity changed during CI verification.")
                    try:
                        common.gh("POST", f"/actions/runs/{run_id}/rerun", {}, allow_empty=True)
                    except ReleaseError as error:
                        raise ReleaseError(
                            f"Could not rerun cancelled source CI ({error}); "
                            "check Actions permissions and rerun limits."
                        ) from None
                    retried = (run_id, attempt)
                    pending = True
                elif (wait and is_old_source and retried is not None
                      and latest.get("id") == retried[0]
                      and latest.get("run_attempt", 1) == retried[1]
                      and latest.get("conclusion") == "cancelled"):
                    # The API can briefly return the previous attempt after
                    # accepting the rerun; keep waiting but never request twice.
                    pending = True
                else:
                    raise ReleaseError("Latest exact-commit CI failed.")
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


def encryption_scope(source):
    """Hash tracked iOS configuration, dependencies and direct crypto importers."""
    tracked = run(["git", "-C", str(source), "ls-files", "-z", "--",
                   "ios", "lib", "pubspec.yaml", "pubspec.lock"]).decode().split("\0")
    hashes = {}
    for name in sorted(filter(None, tracked)):
        path = source / name
        require(path.is_file() and not path.is_symlink(), f"Missing reviewed encryption input: {name}")
        if name.startswith("lib/"):
            if not name.endswith(".dart"):
                continue
            if not CRYPTO_IMPORT.search(path.read_text(encoding="utf-8")):
                continue
        hashes[name] = hashlib.sha256(path.read_bytes()).hexdigest()
    require("pubspec.yaml" in hashes and "pubspec.lock" in hashes
            and "lib/features/reader/offline_resource_store.dart" in hashes,
            "Encryption review scope is incomplete.")
    return hashes


def verify_encryption_attestation(source):
    try:
        attestation = json.loads(ENCRYPTION_ATTESTATION.read_text(encoding="utf-8"))
    except (OSError, ValueError) as error:
        raise ReleaseError("Missing or invalid encryption review attestation.") from error
    require(attestation.get("confirmedExempt") is True and isinstance(attestation.get("files"), dict),
            "Encryption exemption has not been attested.")
    actual = encryption_scope(source)
    expected = attestation["files"]
    changed = sorted(name for name in set(actual) | set(expected) if actual.get(name) != expected.get(name))
    require(not changed, "Encryption review inputs changed; review export compliance and update the "
            "attestation before building: " + ", ".join(changed[:8]))


def plan():
    data = gate()
    exempt = os.environ.get("ENCRYPTION_EXEMPT", "false")
    require(exempt in {"true", "false"}, "Invalid encryption declaration input.")
    existing = os.environ.get("VERIFY_BUILD", "").strip()
    if exempt == "true" and not existing:
        verify_encryption_attestation(SOURCE)
    api = Apple()
    app = api.request("GET", f"/v1/apps/{APP}")["data"]
    require(app["id"] == APP and app["attributes"]["bundleId"] == BUNDLE,
            "Apple app does not match the intended bundle.")
    builds = api.all("/v1/builds?" + urlencode({"filter[app]": APP, "limit": 200}))
    maximum = max([0, *(build_number(item["attributes"]["version"]) for item in builds)])
    if existing:
        number = build_number(existing)
        require(common.commit_for_tag(PREFIX + str(number)) == data["sourceCommit"],
                "Existing build reservation does not match the release source.")
        matches = api.all("/v1/builds?" + urlencode({"filter[app]": APP, "filter[version]": number,
                                                   "filter[preReleaseVersion.version]": data["version"],
                                                   "filter[preReleaseVersion.platform]": "IOS", "limit": 200}))
        require(len(matches) == 1, "Existing Apple build not found unambiguously; no upload will be attempted.")
    else:
        number = reserve(maximum, data["sourceCommit"])
    data.update(build=number, uploaded=False, verificationOnly=bool(existing),
                encryptionExemptDeclaration=exempt == "true",
                processingVerified=False, uploadAttempted=False)
    write_manifest(data)
    output({"version": data["version"], "build": data["build"]})
    print(f"{'Verifying existing' if existing else 'Reserved'} iOS {data['version']} ({data['build']}).")


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


def distribution_project(project, fingerprint):
    # Project-level conditional settings override Release.xcconfig. Flutter's
    # template explicitly selects iPhone Developer here, even for Release.
    require(re.fullmatch(r"[A-F0-9]{40}", fingerprint), "Invalid signing fingerprint.")
    pattern = r'"CODE_SIGN_IDENTITY\[sdk=iphoneos\*\]" = [^;]+;'
    replaced, count = re.subn(pattern, '"CODE_SIGN_IDENTITY[sdk=iphoneos*]" = "' + fingerprint + '";', project)
    require(count == 3, "Unexpected Xcode signing layout; review the released project.")
    return replaced


def importable_pkcs12(source, destination):
    # Apple Security's PKCS#12 importer is not compatible with every OpenSSL 3
    # PBES2/MAC combination. Convert only the temporary CI copy to its supported
    # 3DES/SHA-1 container. The private RSA key/certificate and canonical AES p12
    # are unchanged. The seekable intermediate PEM is encrypted with AES-256.
    env = dict(os.environ, AKRIBOS_IMPORT_PASSWORD=secret("IOS_CERTIFICATE_PASSWORD"))
    pem = destination.with_suffix(".encrypted.pem")
    protected_write(pem, b"")
    try:
        run(["openssl", "pkcs12", "-in", str(source), "-out", str(pem), "-aes256",
             "-passin", "env:AKRIBOS_IMPORT_PASSWORD", "-passout", "env:AKRIBOS_IMPORT_PASSWORD"], env=env)
        run(["openssl", "pkcs12", "-export", "-in", str(pem), "-out", str(destination),
             "-keypbe", "PBE-SHA1-3DES", "-certpbe", "PBE-SHA1-3DES", "-macalg", "SHA1",
             "-passin", "env:AKRIBOS_IMPORT_PASSWORD", "-passout", "env:AKRIBOS_IMPORT_PASSWORD"], env=env)
    finally:
        pem.unlink(missing_ok=True)
    destination.chmod(0o600)


def prepare_signing():
    data = checked_plan()
    directory = private_dir()
    p12, profile_file = directory / "distribution.p12", directory / "profile.mobileprovision"
    protected_write(p12, base64.b64decode(secret("IOS_CERTIFICATE_P12_BASE64"), validate=True))
    protected_write(profile_file, base64.b64decode(secret("IOS_PROVISIONING_PROFILE_BASE64"), validate=True))
    profile = plistlib.loads(run(["security", "cms", "-D", "-i", str(profile_file)]))
    validate_profile(profile)
    compatible = directory / "import.p12"
    importable_pkcs12(p12, compatible)
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
    run(["security", "import", str(compatible), "-P", secret("IOS_CERTIFICATE_PASSWORD"),
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
    project = SOURCE / "ios/Runner.xcodeproj/project.pbxproj"
    project.write_text(distribution_project(project.read_text(), fingerprint))
    if data["encryptionExemptDeclaration"]:
        # The operator's attestation was checked against this exact release source.
        info_path = SOURCE / "ios/Runner/Info.plist"
        info = plistlib.loads(info_path.read_bytes())
        info["ITSAppUsesNonExemptEncryption"] = False
        info_path.write_bytes(plistlib.dumps(info))
    data.update(profileUuid=profile["UUID"], signingCertificateSha1=fingerprint)
    write_manifest(data)
    p12.unlink()
    compatible.unlink()
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
    print("Verified IPA SHA-256: " + data["sha256"])
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as stream:
            stream.write(f"Signed IPA **{data['version']} ({data['build']})**, source `{data['sourceCommit']}`.\n\n"
                         f"SHA-256: `{data['sha256']}`\n\n")
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
    require(not data.get("verificationOnly"), "Verification-only runs must never upload.")
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
    record_processed(api, data, item)
    verify_internal_distribution(api, data, item["id"])


def verify_internal_distribution(api, data, build_id, timeout=5 * 60):
    """Verify Apple's automatic delivery, without adding groups or testers."""
    deadline = time.monotonic() + timeout
    while True:
        response = api.request("GET", "/v1/builds/" + build_id
                               + "?include=betaGroups,buildBetaDetail,preReleaseVersion")
        included = response.get("included", [])
        versions = [entry["attributes"] for entry in included if entry["type"] == "preReleaseVersions"]
        details = [entry["attributes"] for entry in included if entry["type"] == "buildBetaDetails"]
        require(len(details) == len(versions) == 1 and versions[0]["version"] == data["version"]
                and versions[0]["platform"] == "IOS", "Unexpected Apple build metadata/version.")
        state = details[0].get("internalBuildState")
        groups = [entry for entry in included if entry["type"] == "betaGroups"
                  and entry["attributes"].get("isInternalGroup")]
        assigned = any(group.get("id") == INTERNAL_GROUP for group in groups)
        data.update(internalBuildState=state,
                    internalGroups=[group["attributes"]["name"] for group in groups],
                    internalDistributionVerified=assigned and state == "IN_BETA_TESTING")
        write_manifest(data)
        if data["internalDistributionVerified"]:
            print("Apple confirmed the exact build is testing in the internal Betatester group.")
            if os.environ.get("GITHUB_STEP_SUMMARY"):
                with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as stream:
                    stream.write("Internal group **Betatester** and **IN_BETA_TESTING** confirmed.\n\n")
            return
        require(state != "MISSING_EXPORT_COMPLIANCE",
                "Build uploaded but Apple requires export compliance information; resolve it in TestFlight.")
        require(state not in {"PROCESSING_EXCEPTION", "EXPIRED"},
                f"Build uploaded but internal testing is unavailable: {state}.")
        require(time.monotonic() < deadline,
                f"Build uploaded but internal Betatester distribution was not confirmed (state: {state}). "
                "Inspect TestFlight before retrying; do not upload again blindly.")
        print(f"Waiting for automatic internal group distribution (state: {state}).", flush=True)
        time.sleep(min(15, max(0, deadline - time.monotonic())))


def record_processed(api, data, item):
    data.update(processingVerified=True,
                usesNonExemptEncryption=item["attributes"].get("usesNonExemptEncryption"))
    write_manifest(data)  # Preserve VALID even if supplementary metadata fails.
    response = api.request("GET", "/v1/builds/" + item["id"]
                           + "?include=betaGroups,buildBetaDetail,preReleaseVersion")
    included = response.get("included", [])
    details = [entry["attributes"] for entry in included if entry["type"] == "buildBetaDetails"]
    versions = [entry["attributes"] for entry in included if entry["type"] == "preReleaseVersions"]
    require(len(details) == len(versions) == 1 and versions[0]["version"] == data["version"]
            and versions[0]["platform"] == "IOS", "Unexpected Apple build metadata/version.")
    detail = details[0]
    data.update(internalBuildState=detail.get("internalBuildState"),
                externalBuildState=detail.get("externalBuildState"))
    groups = [entry for entry in included if entry["type"] == "betaGroups"]
    data["internalGroups"] = [g["attributes"]["name"] for g in groups if g["attributes"].get("isInternalGroup")]
    write_manifest(data)
    print("Verified Apple result: " + json.dumps(data, sort_keys=True))
    print(f"Apple processing VALID. Internal state: {data['internalBuildState']}. "
          "No public release or external beta review was requested.")
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as stream:
            stream.write(f"Akribos **{data['version']} ({data['build']})** confirmed at Apple; processing **VALID**.\n\n"
                         f"Verification only (no upload in this run): **{data.get('verificationOnly', False)}**.\n\n"
                         f"Internal TestFlight state: **{data['internalBuildState']}**.\n\n"
                         f"[Open TestFlight](https://appstoreconnect.apple.com/apps/{APP}/testflight)\n")


def verify_existing():
    data = checked_plan()
    require(data.get("verificationOnly"), "Explicit existing build number is required.")
    api = Apple()
    item = find_processed_build(api, data)
    data["uploaded"] = True  # Observed at Apple, not uploaded by this run.
    record_processed(api, data, item)


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
    parser.add_argument("action", choices=["wait-for-ci", "plan", "prepare-signing", "build", "publish", "verify-existing", "cleanup"])
    args = parser.parse_args()
    try:
        if args.action == "wait-for-ci":
            data = gate(wait=True)
            output({"source_commit": data["sourceCommit"]})
        else:
            {"plan": plan, "prepare-signing": prepare_signing, "build": build,
             "publish": publish, "verify-existing": verify_existing, "cleanup": cleanup}[args.action]()
    except ReleaseError as error:
        print(f"TestFlight stopped: {error}", file=sys.stderr)
        return 1
    except Exception as error:
        print(f"TestFlight stopped ({type(error).__name__}); inspect configuration and Apple status.", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
