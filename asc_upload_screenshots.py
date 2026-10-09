#!/usr/bin/env python3
"""asc_upload_screenshots.py — upload PNGs to an App Store version's screenshot set.

    python asc_upload_screenshots.py <displayType> <png> [<png> ...]
    e.g. APP_IPHONE_67 build/screenshots/upload/*.png   (1320x2868 for the 6.9-inch slot)

Creates the set on the en-US localization of the 2.0 version if missing, reserves each
screenshot, uploads the bytes to the returned upload operations, then commits with the MD5.
Auth: as asc_publish_build.py (ASC_KEY_P8, ASC_KEY_ID, ASC_ISSUER_ID).
"""
import hashlib, sys, json, urllib.request
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent))
import asc_publish_build as a

VID = "cc9c875e-3847-4f70-8f15-343fbb1c9931"   # App Store version 2.0 (CoreAI Zoo)

def main():
    display, files = sys.argv[1], [Path(p) for p in sys.argv[2:]]
    loc = next(l for l in a.call("GET", f"/appStoreVersions/{VID}/appStoreVersionLocalizations?fields[appStoreVersionLocalizations]=locale")["data"] if l["attributes"]["locale"] == "en-US")
    sets = a.call("GET", f"/appStoreVersionLocalizations/{loc['id']}/appScreenshotSets?fields[appScreenshotSets]=screenshotDisplayType")["data"]
    s = next((x for x in sets if x["attributes"]["screenshotDisplayType"] == display), None)
    if s is None:
        s = a.call("POST", "/appScreenshotSets", {"data": {"type": "appScreenshotSets", "attributes": {"screenshotDisplayType": display},
             "relationships": {"appStoreVersionLocalization": {"data": {"type": "appStoreVersionLocalizations", "id": loc["id"]}}}}})["data"]
        print("created set", display, s["id"])
    existing = a.call("GET", f"/appScreenshotSets/{s['id']}/appScreenshots?fields[appScreenshots]=fileName,assetDeliveryState")["data"]
    print("existing:", [(x["attributes"]["fileName"], x["attributes"]["assetDeliveryState"]["state"]) for x in existing])
    for f in files:
        data = f.read_bytes()
        r = a.call("POST", "/appScreenshots", {"data": {"type": "appScreenshots", "attributes": {"fileName": f.name, "fileSize": len(data)},
             "relationships": {"appScreenshotSet": {"data": {"type": "appScreenshotSets", "id": s["id"]}}}}})["data"]
        for op in r["attributes"]["uploadOperations"]:
            chunk = data[op["offset"]: op["offset"] + op["length"]]
            req = urllib.request.Request(op["url"], method=op["method"], data=chunk,
                                         headers={h["name"]: h["value"] for h in op["requestHeaders"]})
            with urllib.request.urlopen(req, timeout=120) as resp: resp.read()
        r = a.call("PATCH", f"/appScreenshots/{r['id']}", {"data": {"type": "appScreenshots", "id": r["id"],
             "attributes": {"uploaded": True, "sourceFileChecksum": hashlib.md5(data).hexdigest()}}})
        print("uploaded", f.name, r["data"]["attributes"]["assetDeliveryState"]["state"])
    final = a.call("GET", f"/appScreenshotSets/{s['id']}/appScreenshots?fields[appScreenshots]=fileName,assetDeliveryState")["data"]
    print("set now:", [(x["attributes"]["fileName"], x["attributes"]["assetDeliveryState"]["state"]) for x in final])

if __name__ == "__main__":
    main()
