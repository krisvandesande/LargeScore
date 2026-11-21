#!/usr/bin/env python3
"""App Store Connect helper: attach every external tester group to a build and
submit it for beta review.

Deliberately dependency-free. It signs its own ES256 JWT using nothing but the
standard library and the `openssl` already on every Mac, so releasing never depends
on a `pip install` that has gone stale between builds.

Credentials come from the environment (see Scripts/release.sh):

    ASC_KEY_ID      the key's ten-character id, e.g. 7G4HDP7YGG
    ASC_ISSUER_ID   the issuer UUID, from App Store Connect → Users and Access → Keys
    ASC_KEY_PATH    path to the .p8 (defaults to ~/.appstoreconnect/private_keys/)
"""

import base64
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request

API = "https://api.appstoreconnect.apple.com/v1"


def fail(message):
    print(f"error: {message}", file=sys.stderr)
    sys.exit(1)


# --- Authentication ---------------------------------------------------------

def b64(data):
    """JWT wants base64url with the padding stripped."""
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def der_to_raw(der):
    """Convert openssl's DER ECDSA signature to the raw r||s JOSE form.

    openssl emits SEQUENCE { INTEGER r, INTEGER s }, but JWS wants the two values
    plain and fixed-width. Both integers are left-padded to 32 bytes; a leading zero
    byte that DER adds to keep a value positive is dropped.
    """
    if der[0] != 0x30:
        raise ValueError("not a DER sequence")
    # Skip the sequence header (long-form length is possible but never happens for
    # P-256, where the whole structure is well under 128 bytes).
    index = 2 if der[1] < 0x80 else 3 + (der[1] & 0x7F)

    values = []
    for _ in range(2):
        if der[index] != 0x02:
            raise ValueError("expected a DER integer")
        length = der[index + 1]
        value = der[index + 2: index + 2 + length]
        values.append(value.lstrip(b"\x00").rjust(32, b"\x00"))
        index += 2 + length
    return values[0] + values[1]


def token():
    key_id = os.environ.get("ASC_KEY_ID")
    issuer = os.environ.get("ASC_ISSUER_ID")
    if not key_id:
        fail("ASC_KEY_ID is not set.")
    if not issuer:
        fail(
            "ASC_ISSUER_ID is not set. Find it in App Store Connect → Users and "
            "Access → Integrations → App Store Connect API; it's the UUID above the "
            "key list, and it's the same for every key on the team."
        )

    key_path = os.environ.get(
        "ASC_KEY_PATH",
        os.path.expanduser(f"~/.appstoreconnect/private_keys/AuthKey_{key_id}.p8"),
    )
    if not os.path.exists(key_path):
        fail(f"private key not found at {key_path}")

    now = int(time.time())
    header = {"alg": "ES256", "kid": key_id, "typ": "JWT"}
    # Twenty minutes is Apple's maximum; anything longer is rejected outright.
    payload = {"iss": issuer, "iat": now, "exp": now + 1200, "aud": "appstoreconnect-v1"}

    signing_input = (
        b64(json.dumps(header, separators=(",", ":")).encode())
        + "."
        + b64(json.dumps(payload, separators=(",", ":")).encode())
    ).encode()

    signed = subprocess.run(
        ["openssl", "dgst", "-sha256", "-sign", key_path],
        input=signing_input,
        capture_output=True,
    )
    if signed.returncode != 0:
        fail(f"signing failed: {signed.stderr.decode().strip()}")

    return signing_input.decode() + "." + b64(der_to_raw(signed.stdout))


def request(method, path, body=None, bearer=None):
    url = path if path.startswith("http") else f"{API}{path}"
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Authorization", f"Bearer {bearer}")
    req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req) as response:
            raw = response.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as error:
        detail = error.read().decode()
        try:
            errors = json.loads(detail).get("errors", [])
            detail = "; ".join(f"{e.get('title')}: {e.get('detail')}" for e in errors)
        except json.JSONDecodeError:
            pass
        fail(f"{method} {url} → {error.code}\n  {detail}")


# --- The work ---------------------------------------------------------------

def find_app(bundle_id, bearer):
    found = request("GET", f"/apps?filter[bundleId]={bundle_id}&limit=1", bearer=bearer)
    if not found.get("data"):
        fail(f"no app found for bundle id {bundle_id}")
    return found["data"][0]["id"]


def wait_for_build(app_id, version, bearer, platform="IOS", timeout=1800):
    """Wait for the newest build to finish processing.

    Polls rather than assumes: a build that is still PROCESSING cannot be assigned to
    a group or submitted for review, and Apple's own upload step returns long before
    processing is done. `version` is the build number to wait for; without it the most
    recent build wins, which is only safe when nothing else is uploading.
    """
    # Per platform: an iOS and a Mac build share a number, and waiting on "build 15"
    # alone could pick up whichever finished first.
    query = (f"/builds?filter[app]={app_id}&sort=-uploadedDate&limit=1"
             f"&filter[preReleaseVersion.platform]={platform}")
    if version:
        query += f"&filter[version]={version}"

    deadline = time.time() + timeout
    reported = None
    while time.time() < deadline:
        builds = request("GET", query, bearer=bearer).get("data", [])
        if builds:
            build = builds[0]
            state = build["attributes"]["processingState"]
            if state != reported:
                print(f"  build {build['attributes'].get('version')}: {state}")
                reported = state
            if state == "VALID":
                return build["id"], build["attributes"].get("version")
            if state in ("INVALID", "FAILED"):
                fail(f"build did not process cleanly ({state}). Check App Store Connect.")
        else:
            print("  waiting for the build to appear…")
        time.sleep(30)
    fail("timed out waiting for the build to finish processing")


def external_groups(app_id, bearer):
    """Every external group on the app, paging through the whole list.

    Internal groups are excluded: they get every build automatically, so adding them
    is at best a no-op and at worst an error.
    """
    groups = []
    url = f"/apps/{app_id}/betaGroups?limit=200"
    while url:
        page = request("GET", url, bearer=bearer)
        for group in page.get("data", []):
            if not group["attributes"].get("isInternalGroup"):
                groups.append((group["id"], group["attributes"].get("name")))
        url = page.get("links", {}).get("next")
    return groups


def set_what_to_test(build_id, note, bearer, locale="en-US"):
    """The note testers see in TestFlight. Created or replaced, so a re-run fixes it.

    Mandatory on purpose: without one, testers see nothing about what changed. Plain
    text only — App Store Connect rejects some symbols outright (it refused a tick
    mark in Hideaway's notes).
    """
    existing = request("GET", f"/builds/{build_id}/betaBuildLocalizations", bearer=bearer).get("data", [])
    match = next((loc for loc in existing if loc["attributes"].get("locale") == locale), None)
    if match:
        request(
            "PATCH",
            f"/betaBuildLocalizations/{match['id']}",
            body={"data": {"type": "betaBuildLocalizations", "id": match["id"],
                           "attributes": {"whatsNew": note}}},
            bearer=bearer,
        )
    else:
        request(
            "POST",
            "/betaBuildLocalizations",
            body={"data": {
                "type": "betaBuildLocalizations",
                "attributes": {"locale": locale, "whatsNew": note},
                "relationships": {"build": {"data": {"type": "builds", "id": build_id}}},
            }},
            bearer=bearer,
        )
    print("  What to Test set")


def distribute(bundle_id, build_version, submit, note, platform="IOS"):
    bearer = token()

    app_id = find_app(bundle_id, bearer)
    print(f"App {bundle_id} → {app_id}")

    build_id, version = wait_for_build(app_id, build_version, bearer, platform=platform)
    print(f"Build {version} ({platform}) is ready ({build_id})")

    set_what_to_test(build_id, note, bearer)

    groups = external_groups(app_id, bearer)
    if not groups:
        print("No external tester groups exist yet — nothing to add.")
    else:
        request(
            "POST",
            f"/builds/{build_id}/relationships/betaGroups",
            body={"data": [{"type": "betaGroups", "id": gid} for gid, _ in groups]},
            bearer=bearer,
        )
        for _, name in groups:
            print(f"  added to {name}")

    if submit:
        # Already-submitted builds return a conflict rather than succeeding quietly,
        # which is why this is the last step: everything above is safe to re-run.
        request(
            "POST",
            "/betaAppReviewSubmissions",
            body={
                "data": {
                    "type": "betaAppReviewSubmissions",
                    "relationships": {"build": {"data": {"type": "builds", "id": build_id}}},
                }
            },
            bearer=bearer,
        )
        print("Submitted for Beta App Review.")


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bundle-id", default="com.kvds.LargeScore")
    parser.add_argument(
        "--build",
        help="Build number to wait for. Without it, the most recent upload is used.",
    )
    parser.add_argument(
        "--no-submit",
        action="store_true",
        help="Add the tester groups but don't submit for beta review.",
    )
    parser.add_argument(
        "--note",
        required=True,
        help="What to Test, as testers will read it. Plain words, plain text.",
    )
    parser.add_argument(
        "--platform",
        default="IOS",
        choices=["IOS", "MAC_OS"],
        help="Which platform's build to distribute.",
    )
    args = parser.parse_args()

    distribute(args.bundle_id, args.build, submit=not args.no_submit, note=args.note, platform=args.platform)
