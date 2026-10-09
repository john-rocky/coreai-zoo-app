#!/usr/bin/env python3
"""asc_submit_version.py — create/attach/submit an App Store version through the ASC API.

    <venv with pyjwt>/bin/python asc_submit_version.py <versionString> <buildNumber> [--whats-new FILE] [--go]

Without --go it only reads and prints the state (dry run). With --go it: creates the
appStoreVersion if missing (releaseType MANUAL), attaches the build (waits for VALID), sets
en-US What's New, then creates a reviewSubmission + item and submits it.
Written 2026-09-18 for 2.0.1 (build 10); traced from the 2.0 submission logs.

Auth: the same API key variables as make-testflight.sh (ASC_KEY_P8, ASC_KEY_ID, ASC_ISSUER_ID).
Unset, they fall back to this app's key id and ~/.appstoreconnect/private_keys/AuthKey_<id>.p8.
"""
import json, os, sys, time, urllib.request, urllib.error
from pathlib import Path
import jwt

APP = "6780135339"
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
        print(method, path, "->", e.code, e.read().decode()[:1200]); raise

def main():
    version, build_number = sys.argv[1], sys.argv[2]
    go = "--go" in sys.argv
    whats_new = Path(sys.argv[sys.argv.index("--whats-new") + 1]).read_text().strip() if "--whats-new" in sys.argv else None

    # 1. build
    b = call("GET", f"/builds?filter[app]={APP}&filter[version]={build_number}&fields[builds]=version,processingState,uploadedDate,expired,usesNonExemptEncryption&limit=5")["data"]
    build = b[0] if b else None
    print("build:", build["attributes"] if build else "NOT UPLOADED YET")
    if go:
        deadline = time.time() + 3600
        while build is None or build["attributes"]["processingState"] != "VALID":
            if build and build["attributes"]["processingState"] in ("FAILED", "INVALID"):
                sys.exit("processing " + build["attributes"]["processingState"])
            if time.time() > deadline: sys.exit("timed out waiting for processing")
            time.sleep(60)
            b = call("GET", f"/builds?filter[app]={APP}&filter[version]={build_number}&fields[builds]=version,processingState&limit=5")["data"]
            build = b[0] if b else None
            print(time.strftime("%H:%M:%S"), "build", build_number, build["attributes"]["processingState"] if build else "NOT UPLOADED YET")

    # 2. version
    vs = call("GET", f"/apps/{APP}/appStoreVersions?fields[appStoreVersions]=versionString,appStoreState,appVersionState,releaseType,copyright&limit=10")["data"]
    for v in vs: print("version:", v["id"], v["attributes"])
    ver = next((v for v in vs if v["attributes"]["versionString"] == version), None)
    if ver is None:
        print(f"version {version}: absent")
        if go:
            prev = next((v for v in vs if v["attributes"]["appStoreState"] == "READY_FOR_SALE"), None)
            copyright_ = prev["attributes"].get("copyright") if prev else "2026 Daisuke Majima"
            ver = call("POST", "/appStoreVersions", {"data": {"type": "appStoreVersions",
                "attributes": {"platform": "IOS", "versionString": version, "releaseType": "MANUAL", "copyright": copyright_},
                "relationships": {"app": {"data": {"type": "apps", "id": APP}}}}})["data"]
            print("created version:", ver["id"], ver["attributes"])
    if ver is None: return
    vid = ver["id"]

    # 3. attach build
    cur = call("GET", f"/appStoreVersions/{vid}/build?fields[builds]=version,processingState")
    cur_b = cur.get("data")
    print("attached build:", cur_b["attributes"] if cur_b else None)
    if go and build and (cur_b is None or cur_b["id"] != build["id"]):
        call("PATCH", f"/appStoreVersions/{vid}/relationships/build", {"data": {"type": "builds", "id": build["id"]}})
        print("attached build", build_number)

    # 4. localization / What's New
    locs = call("GET", f"/appStoreVersions/{vid}/appStoreVersionLocalizations?fields[appStoreVersionLocalizations]=locale,whatsNew,description,keywords,promotionalText,supportUrl,marketingUrl")["data"]
    for l in locs:
        a = l["attributes"]; print("loc:", l["id"], a["locale"], {k: (len(v) if isinstance(v, str) else v) for k, v in a.items() if k != "locale"})
    en = next((l for l in locs if l["attributes"]["locale"] == "en-US"), None)
    if go and whats_new:
        if en is None:
            en = call("POST", "/appStoreVersionLocalizations", {"data": {"type": "appStoreVersionLocalizations",
                "attributes": {"locale": "en-US", "whatsNew": whats_new},
                "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": vid}}}}})["data"]
            print("created en-US localization with What's New")
        elif (en["attributes"].get("whatsNew") or "").strip() != whats_new:
            call("PATCH", f"/appStoreVersionLocalizations/{en['id']}", {"data": {"type": "appStoreVersionLocalizations", "id": en["id"], "attributes": {"whatsNew": whats_new}}})
            print("What's New set (%d chars)" % len(whats_new))
    if en:
        ss = call("GET", f"/appStoreVersionLocalizations/{en['id']}/appScreenshotSets?fields[appScreenshotSets]=screenshotDisplayType&include=appScreenshots&fields[appScreenshots]=fileName,assetDeliveryState")
        print("screenshots:", [(i["attributes"]["fileName"], i["attributes"]["assetDeliveryState"]["state"]) for i in ss.get("included", [])])

    # 5. review submission
    subs = call("GET", f"/reviewSubmissions?filter[app]={APP}&filter[state]=READY_FOR_REVIEW,WAITING_FOR_REVIEW,IN_REVIEW,UNRESOLVED_ISSUES&fields[reviewSubmissions]=platform,state,submittedDate&limit=5")["data"]
    print("open submissions:", [(s["id"], s["attributes"]) for s in subs])
    if not go: return
    sub = next((s for s in subs if s["attributes"]["state"] == "READY_FOR_REVIEW"), None)
    if sub is None and not subs:
        sub = call("POST", "/reviewSubmissions", {"data": {"type": "reviewSubmissions", "attributes": {"platform": "IOS"},
            "relationships": {"app": {"data": {"type": "apps", "id": APP}}}}})["data"]
        print("created submission", sub["id"], sub["attributes"])
    if sub is None: sys.exit("a submission is already in flight: %s" % subs)
    items = call("GET", f"/reviewSubmissions/{sub['id']}/items?fields[reviewSubmissionItems]=state&limit=5")["data"]
    if not items:
        item = call("POST", "/reviewSubmissionItems", {"data": {"type": "reviewSubmissionItems",
            "relationships": {"reviewSubmission": {"data": {"type": "reviewSubmissions", "id": sub["id"]}},
                              "appStoreVersion": {"data": {"type": "appStoreVersions", "id": vid}}}}})["data"]
        print("added item", item["id"], item["attributes"])
    done = call("PATCH", f"/reviewSubmissions/{sub['id']}", {"data": {"type": "reviewSubmissions", "id": sub["id"], "attributes": {"submitted": True}}})["data"]
    print("SUBMITTED:", done["attributes"])
    v = call("GET", f"/appStoreVersions/{vid}?fields[appStoreVersions]=versionString,appVersionState")["data"]
    print("version state:", v["attributes"])

if __name__ == "__main__":
    main()
