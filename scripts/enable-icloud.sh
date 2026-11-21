#!/bin/bash
# Turns on iCloud sync once the container iCloud.com.kvds.LargeScore exists (see
# docs/icloud-setup.md): capabilities on the bundle id, entitlements, background
# mode, and the App Store profiles made again with iCloud in them.
set -euo pipefail
cd "$(dirname "$0")/.."
[ -f scripts/asc.env ] && source scripts/asc.env
CONTAINER=iCloud.com.kvds.LargeScore

python3 - <<'PY'
import importlib.util, base64, os
spec = importlib.util.spec_from_file_location("asc", "scripts/asc.py"); m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
bearer = m.token()
bundle = "BL3HR4LVX7"
for kind, settings in [("ICLOUD", [{"key": "ICLOUD_VERSION", "options": [{"key": "XCODE_6", "enabled": True}]}]),
                       ("PUSH_NOTIFICATIONS", None)]:
    body = {"data": {"type": "bundleIdCapabilities", "attributes": {"capabilityType": kind},
                     "relationships": {"bundleId": {"data": {"type": "bundleIds", "id": bundle}}}}}
    if settings: body["data"]["attributes"]["settings"] = settings
    try:
        m.request("POST", "/bundleIdCapabilities", body=body, bearer=bearer); print("enabled", kind)
    except SystemExit:
        print(kind, "may already be on")
folder = os.path.expanduser("~/Library/Developer/Xcode/UserData/Provisioning Profiles")
for name, kind, ext in [("Large Score App Store", "IOS_APP_STORE", "mobileprovision"),
                        ("Large Score Mac App Store", "MAC_CATALYST_APP_STORE", "provisionprofile")]:
    old = m.request("GET", f"/profiles?filter[name]={name.replace(' ', '%20')}", bearer=bearer).get("data", [])
    for p in old: m.request("DELETE", f"/profiles/{p['id']}", bearer=bearer)
    r = m.request("POST", "/profiles", body={"data": {"type": "profiles", "attributes": {"name": name, "profileType": kind},
        "relationships": {"bundleId": {"data": {"type": "bundleIds", "id": bundle}},
                          "certificates": {"data": [{"type": "certificates", "id": "YH8NPR9U9Z"}]}}}}, bearer=bearer)
    a = r["data"]["attributes"]
    open(f"{folder}/{a['uuid']}.{ext}", "wb").write(base64.b64decode(a["profileContent"]))
    print("profile", name, a["uuid"])
PY

python3 - "$CONTAINER" <<'PY'
import plistlib, sys
container = sys.argv[1]
for path, push in [("LargeScore/LargeScore.entitlements", "aps-environment"),
                   ("LargeScore/LargeScoreMac.entitlements", "com.apple.developer.aps-environment")]:
    with open(path, "rb") as f: e = plistlib.load(f)
    e["com.apple.developer.icloud-container-identifiers"] = [container]
    e["com.apple.developer.icloud-services"] = ["CloudKit"]
    e[push] = "development"
    with open(path, "wb") as f: plistlib.dump(e, f)
    print("entitlements", path)
PY

# Sync is woken by silent pushes.
grep -q "remote-notification" project.yml || python3 - <<'PY'
p = "project.yml"; s = open(p).read()
s = s.replace("        ITSAppUsesNonExemptEncryption: false",
              "        ITSAppUsesNonExemptEncryption: false\n        UIBackgroundModes: [remote-notification]", 1)
open(p, "w").write(s)
PY
xcodegen generate
echo "Done. Build, run once signed in to iCloud, then deploy the schema (docs/icloud-setup.md, step 3)."
