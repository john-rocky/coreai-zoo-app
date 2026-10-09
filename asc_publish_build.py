#!/usr/bin/env python3
"""asc_publish_build.py — after `make-testflight.sh`: wait for processing, add the build to the
public TestFlight group, set "What to Test".

    <venv with pyjwt+cryptography>/bin/python asc_publish_build.py <build-number> [--whats-new FILE]

The public link (https://testflight.apple.com/join/bK4P7xby) is an EXTERNAL group; a new build is
not visible to its testers until it is added here (build 8 never was — the link served build 7
from 2026-07-08 until 2026-09-10). Internal groups get every build automatically.

Auth: the same API key variables as make-testflight.sh (ASC_KEY_P8, ASC_KEY_ID, ASC_ISSUER_ID).
Unset, they fall back to this app's key id and ~/.appstoreconnect/private_keys/AuthKey_<id>.p8.
"""
import json, os, sys, time, urllib.request, urllib.error
from pathlib import Path
import jwt

APP = "6780135339"                                   # CoreAI Zoo (com.daisukemajima.CoreAIChat)
EXTERNAL_GROUP = "6d680029-43f3-4e01-bc63-f0fe05734cf5"  # "Public Preview", publicLinkId bK4P7xby
KEY_ID = os.environ.get("ASC_KEY_ID") or "3ZR8BRVF9H"
ISSUER = os.environ.get("ASC_ISSUER_ID") or "69a6de96-8f3e-47e3-e053-5b8c7c11a4d1"
KEY_P8 = Path(os.environ.get("ASC_KEY_P8") or f"~/.appstoreconnect/private_keys/AuthKey_{KEY_ID}.p8").expanduser()
BASE = "https://api.appstoreconnect.apple.com/v1"

def token():
    key = KEY_P8.read_text()
    now = int(time.time())
    return jwt.encode({"iss": ISSUER, "iat": now, "exp": now + 900, "aud": "appstoreconnect-v1"},
                      key, algorithm="ES256", headers={"kid": KEY_ID})

def call(method, path, body=None):
    req = urllib.request.Request(BASE + path, method=method,
                                 headers={"Authorization": "Bearer " + token(), "Content-Type": "application/json"},
                                 data=json.dumps(body).encode() if body is not None else None)
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            raw = r.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        print(method, path, "->", e.code, e.read().decode()[:600]); raise

def find_build(version):
    r = call("GET", f"/builds?filter[app]={APP}&filter[version]={version}&fields[builds]=version,processingState,uploadedDate,expired&limit=5")
    return r["data"][0] if r["data"] else None

def main():
    version = sys.argv[1]
    whats_new = None
    if "--whats-new" in sys.argv:
        whats_new = Path(sys.argv[sys.argv.index("--whats-new") + 1]).read_text().strip()
    deadline = time.time() + 3600
    while True:
        b = find_build(version)
        state = b["attributes"]["processingState"] if b else "NOT_UPLOADED_YET"
        print(time.strftime("%H:%M:%S"), "build", version, state)
        if b and state == "VALID":
            break
        if b and state in ("FAILED", "INVALID"):
            sys.exit(f"processing {state}")
        if time.time() > deadline:
            sys.exit("timed out waiting for processing")
        time.sleep(60)
    bid = b["id"]
    # 1. add to the external (public link) group
    call("POST", f"/betaGroups/{EXTERNAL_GROUP}/relationships/builds", {"data": [{"type": "builds", "id": bid}]})
    print("added to external group")
    # 2. What to Test (en-US), create or update
    if whats_new:
        loc = call("GET", f"/builds/{bid}/betaBuildLocalizations?fields[betaBuildLocalizations]=locale,whatsNew")
        en = next((l for l in loc["data"] if l["attributes"]["locale"] == "en-US"), None)
        if en:
            call("PATCH", f"/betaBuildLocalizations/{en['id']}", {"data": {"type": "betaBuildLocalizations", "id": en["id"], "attributes": {"whatsNew": whats_new}}})
        else:
            call("POST", "/betaBuildLocalizations", {"data": {"type": "betaBuildLocalizations", "attributes": {"locale": "en-US", "whatsNew": whats_new}, "relationships": {"build": {"data": {"type": "builds", "id": bid}}}}})
        print("what to test set")
    # 3. report: which builds the public group now serves, and the beta review state
    g = call("GET", f"/betaGroups/{EXTERNAL_GROUP}/builds?fields[builds]=version,expired&limit=20")
    print("external group builds:", [x["attributes"]["version"] for x in g["data"]])
    try:
        s = call("GET", f"/builds/{bid}/betaAppReviewSubmission?fields[betaAppReviewSubmissions]=betaReviewState")
        print("beta review:", s.get("data", {}).get("attributes"))
    except Exception:
        print("beta review: (no submission object yet)")

if __name__ == "__main__":
    main()
