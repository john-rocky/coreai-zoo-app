# RC-day runbook — rebuild → sentinel → TestFlight, by tracing

Written 2026-09-01. Every step below was executed against Xcode 27 **beta 5
(27A5237l)** on 2026-09-01 and worked; on RC day, substitute the RC and trace top to bottom.
Last shipped build: **11** (2.0.2), uploaded 2026-10-27 with RC 27A266a (build 10 = 2.0.1, on the App Store; build 9 = 2.0, App Store since 09-18; build 8: 07-10, beta 3, expires ~10-08).

Traced again with the RC `27A266a` for build 9 (2.0, 2026-09-14), build 10 (2.0.1, 2026-09-18) and
build 11 (2.0.2, 2026-10-27). Each time the two sentinels were present and the app referenced 151
FoundationModels symbols (builds 9 and 10: the same list as beta 5), so `Sources/FMSeedGate.swift`
did not change.

## 0. Before RC day (do once, any time)

- [ ] Install a toolchain currently accepted by ASC. Apple's [release notes](https://developer.apple.com/help/app-store-connect/release-notes/)
      explicitly list Xcode 27 beta 6 for internal/external TestFlight testing as of August 25.
      Beta 5 was rejected with 90534 on September 10; do not infer that an RC is mandatory.
      The download needs an Apple Developer account login.
- [ ] ASC agreement is signed (an upload once failed with `FORBIDDEN.REQUIRED_AGREEMENTS` until the
      agreement was re-signed — check appstoreconnect.apple.com if in doubt).
- [ ] API key on disk: `~/.appstoreconnect/private_keys/AuthKey_3ZR8BRVF9H.p8`.
- [ ] Clean working tree. Whatever is in the tree ships in the archive: commit uncommitted work or
      set it aside deliberately before archiving; don't ship it by accident.

## 1. Select the RC toolchain

```sh
export DEVELOPER_DIR=/Applications/Xcode-27.0.0-RC.app/Contents/Developer   # adjust to actual path
xcodebuild -version    # confirm the RC build number, note it below
```

## 2. Sentinel check (FMSeedGate) — BEFORE archiving

FoundationModels is weak-linked (`project.yml` OTHER_LDFLAGS) and its Swift manglings have
churned between OS 27 seeds twice already. A mismatch is **silent**: the app launches, then the
Vision / Audio-Understand features trap or go dead. `Sources/FMSeedGate.swift` holds the two
mangled names this binary references; verify they are still what the RC SDK emits:

```sh
# from the repo root
xcodegen generate
xcodebuild build -project CoreAIZoo.xcodeproj -scheme CoreAIZoo -configuration Release \
  -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath build/dd \
  CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3        # expect: BUILD SUCCEEDED (~5 min)

nm -u build/dd/Build/Products/Release-iphoneos/CoreAIZoo.app/CoreAIZoo \
  | grep 16FoundationModels | sort > /tmp/fm_rc.txt

# Both sentinels must appear (note: nm prints a leading underscore; the Swift strings in
# FMSeedGate.swift do not have it — that is correct, dlsym takes the name without it):
grep -c 'AttachmentVA2A05ImageC7ContentVRszlE_11orientation' /tmp/fm_rc.txt   # want 1+
grep -c 'GenerationChannelV4sendyyAC5EventVYaF' /tmp/fm_rc.txt                # want 1+

# Optional: full churn diff against the list you saved from the previous SDK
# (151 symbols on beta 5 27A5237l and on the RC 27A266a, identical):
diff fm-symbols-<previous sdk build>.txt /tmp/fm_rc.txt
```

**If a grep returns 0** the RC re-mangled that call site. Fix:
1. In `/tmp/fm_rc.txt`, find the successor symbol — the Attachment sentinel is the one containing
   `AttachmentV…Image…orientation…CGImageRef`, the channel sentinel the one ending
   `ChannelV4send…EventVYaF`.
2. Replace the corresponding string in `Sources/FMSeedGate.swift` (drop nm's leading `_`).
3. Rebuild (same command) and re-run the greps until both hit.

If the `diff` shows churn only in NON-sentinel symbols, the gate still works but devices on older
seeds may trap in code paths the gate doesn't cover — record it with the build and move on
(the gate is a tripwire, not a proof).

## 3. Pick the build number

Use the next number after the last upload ("Last shipped build" above). On 2026-09-10 01:12 JST a
beta-5 archive of build 9 passed archive and export and was refused by altool with **90534** ("use
the latest Release Candidates") — with Xcode 27 beta 6 already out, beta 5 was no longer the newest,
so the "newest beta/RC only" rule holds. Listing builds without the web UI:
`asc_publish_build.py` (repo root) uses the API key.

**The public link is an external group and does not receive builds automatically.** Build 8
(07-09) was never added to it, so testers on https://testflight.apple.com/join/bK4P7xby ran
build 7 (07-08, pre weak-link) for two months. After every upload, run
`python asc_publish_build.py <build> --whats-new <file>` (any Python with pyjwt + cryptography;
earlier texts: `docs/WHATS_NEW_2.0_BUILD9.txt`, `docs/WHATS_NEW_2.0.1_TESTFLIGHT.txt`,
`docs/WHATS_NEW_2.0.2_TESTFLIGHT.txt`)
— it waits for processing, adds the build to the group, sets What to Test, and prints the
group's builds and the beta-review state. It does not submit the build for beta review (§8).

## 4. Archive + upload

```sh
export ASC_KEY_P8=~/.appstoreconnect/private_keys/AuthKey_3ZR8BRVF9H.p8
export ASC_KEY_ID=3ZR8BRVF9H
export ASC_ISSUER_ID=69a6de96-8f3e-47e3-e053-5b8c7c11a4d1
# DEVELOPER_DIR already set in step 1
BUILD_NUMBER=<next> ./make-testflight.sh 2>&1 | tee _rc_upload.log   # _*.log is gitignored
```

The script does: xcodegen → archive (Release, generic iOS, ship bundle id
`com.daisukemajima.CoreAIChat` overridden at archive time) → CFBundleIconName injection →
export → altool validate → upload. Success ends with `UPLOAD SUCCEEDED` + a Delivery UUID.

### Known failures, seen before

| Symptom | Cause | Fix |
|---|---|---|
| 90534 Unsupported SDK | not the newest beta/RC | install newest, redo step 1 |
| `FORBIDDEN.REQUIRED_AGREEMENTS` / "no app record" from altool | ASC agreement lapsed | re-sign the agreement on App Store Connect, rerun |
| 90474 orientations | regression of `a04c68a` | UISupportedInterfaceOrientations in project.yml |
| 90713 / 90704 icon | CFBundleIconName injection failed | script step 2b; check archive's Info.plist |
| Launch crash on device on older OS seed | FM mangling churn + device seed < SDK | that's what step 2 prevents; if it still happens the gate's sentinels missed the churned symbol — regenerate against the RC and pick the churned one |

## 5. After upload

- [ ] ASC processing completes (minutes to ~1 h).
- [ ] Install via TestFlight on the phone. 60-second smoke: Chat qwen3-0.6b gives a response;
      Vision tab responds to a photo; Audio tab opens. Vision/Understand dead = sentinel
      mismatch on that device's seed — check the device OS build vs. the SDK before blaming chat.
- [ ] Per-model loop and capability sweep: tables B and C in `DEVICE_SMOKE_2.0_BUILD9.md` (this folder).

## 6. Mac dmg

`BUILD_NUMBER=<n> ./make-macos-dmg.sh` (same environment as §4) archives the Mac app, exports it
with Developer ID, then signs, notarizes and staples the `.dmg` and checks it with `spctl`.
Sign the dmg itself as well as the app: `spctl -t install` rejects an unsigned dmg even when the app
inside is notarized and stapled.

The 2.0 Mac build is the GitHub release [mac-2.0.9](https://github.com/john-rocky/coreai-model-zoo/releases/tag/mac-2.0.9):
`CoreAIZoo-2.0-9.dmg`, SHA-256 `bc6b4768f4d447617a27f175598dd04b28fbf470ffcc5c0f878d4b2bbcd12f99`.
That dmg adds dependency license notices and install instructions to the script's output; the app
binary inside is the same.

## 7. App Store 2.0 submission (submitted 2026-09-15 → approved 09-17 → released 09-18)

Review completed 09-17 ("eligible for distribution", Pending Developer Release). After the device
smoke A0/A1 on the iPhone 17 Pro (`DEVICE_SMOKE_2.0_BUILD9.md`), Release This Version was pressed on
09-18; the API then read `appStoreState` READY_FOR_SALE. Store URL https://apps.apple.com/app/id6780135339 (app id 6780135339) — 404 at the time of release, then 301 → https://apps.apple.com/us/app/coreai-zoo/id6780135339 (200, title "CoreAI Zoo App - App Store") about 30 minutes later; `itunes.apple.com/lookup` still returned 0 results at that point. Liveness: `curl -s -o /dev/null -w '%{http_code}\n' -A Mozilla https://apps.apple.com/app/id6780135339` (want 200) and `curl -s 'https://itunes.apple.com/lookup?id=6780135339' | grep -c trackViewUrl` (want 1).

Done via the API: the lone 1.0 version record was renamed to
**2.0** with build 9 attached, release type MANUAL, copyright set; en-US description / keywords /
promotional text / support + marketing URLs (`docs/APP_STORE_DESCRIPTION_2.0.txt`); subtitle;
categories Developer Tools + Utilities; age rating all NONE/false (4+); App Review contact with
no demo account; content rights = uses third-party content (open-licensed model weights);
price Free (base USA); availability all 175 territories + new ones. What's New is not editable
on a first App Store release (409), and `usesNonExemptEncryption` is already false on build 9.

Submission checklist (all done for 2.0 except the age-rating judgment):
- [x] iPhone 6.9-inch screenshots: 5 uploaded 2026-09-15 via `asc_upload_screenshots.py`
      (Chat, model list, Bench, Audio Speak, Camera Depth), captured on the iPhone 17 Pro by the
      XCUITest driver in `UITests/ShotsTests.swift` (`project-shots.yml`, `xcodegen --spec`) and
      resized 1206x2622 -> 1320x2868. Vision could not be captured: under UI automation the
      PhotosPicker demands the device passcode. iOS simulators
      cannot build the app (no CoreAI.framework in the simulator SDK).
- [x] iPad 13-inch screenshot: 1 uploaded (Bench tab, landscape 2752x2064) — the iOS build run
      on this Mac as "Designed for iPad" (wrap `Release-iphoneos/CoreAIZoo.app` in
      `X.app/Wrapper/` + `WrappedBundle` symlink, `open` it, size the window with System Events,
      capture by window id: find the CoreAIZoo window with `CGWindowListCopyWindowInfo`, then
      `screencapture -x -o -l <window id>`).
- [x] Privacy policy URL: https://john-rocky.github.io/coreai-zoo-privacy/ (GitHub Pages).
- [x] App Privacy questionnaire: "Data Not Collected" published 2026-09-15 via the ASC web UI
      (there is no API for it — `/v1/appDataUsages` is web-session-only).
- [x] **Submitted for App Store review 2026-09-15 08:03 JST**: version 2.0 (build 9)
      WAITING_FOR_REVIEW, release type MANUAL. After approval, release it by hand
      (PATCH appStoreVersionReleaseRequests or the ASC button).
- [ ] Age rating judgment: declared 4+; an uncensored local LLM may draw a 17+ request from
      review — `ageRatingOverrideV2` can be set to SEVENTEEN_PLUS if you prefer to pre-empt it.

**Simulator screenshots: not possible (2026-09-14).** The iPhoneSimulator 27.0 SDK has no
`CoreAI.framework` (device SDK only, arm64e), so coreai-models' `CoreAIShared` fails to resolve
`import CoreAI` and the app cannot be built for any iOS simulator.

## 8. 2.0.1 (build 10) — 2026-09-18

Why: (a) chat replies were cut at the kit's 2048-token default (thinking models spend most of it in
`<think>`); (b) on the pipelined ports "Generating…" outlived the reply until Stop — the runtime drained
the engine to maxTokens after EOS (fixed in coreai-models fork tag `0.2.5-zoo`, commit dad1f64; Mac:
14-token LFM2.5 reply 8.3 s → 0.2 s to complete). Evidence: `DEVICE_SMOKE_2.0_BUILD9.md`.
Code: coreai-kit `e25f7ad` (branch `ane-variant`) and this repo's `416daa6`.

Traced §1–§4 again: sentinels 1/2 present, FM symbols identical to the RC snapshot. Archive → export →
validate → upload with `BUILD_NUMBER=10 ./make-testflight.sh`; the archive's Info.plist read 2.0.1 / 10 /
`com.daisukemajima.CoreAIChat`. Device check before upload: the same tree as a dev build
(`com.daisukemajima.coreaizoo` 2.0.1) on the iPhone 17 Pro — LFM2.5 returned to Ready right after the
reply, and Qwen3 with Think off was not cut.

Submission: `asc_submit_version.py 2.0.1 10 --whats-new docs/WHATS_NEW_2.0.1.txt --go` waits for VALID,
creates the 2.0.1 version (MANUAL release), attaches build 10, sets en-US What's New, creates the
reviewSubmission + item and submits. Without `--go` it only reads and prints the state. Then
`asc_publish_build.py 10 --whats-new docs/WHATS_NEW_2.0.1_TESTFLIGHT.txt` for the public TestFlight link.
Result (JST 18:29–18:31): build 10 VALID at 18:29; version 2.0.1 created (MANUAL), build attached,
What's New set (293 chars); review submitted 2026-09-18T09:29:29Z → version WAITING_FOR_REVIEW.

TestFlight: build 10 in the Public Preview group with What to Test. The public link serves a build only
after its beta review: create a `betaAppReviewSubmission` for the build (none of the scripts here does
this). Build 10's went to externalBuildState WAITING_FOR_BETA_REVIEW; build 9's was approved within
seconds, so check `buildBetaDetail` later. After App Store approval, release 2.0.1 by hand (ASC button
or appStoreVersionReleaseRequests).

## 9. 2.0.2 (build 11) — 2026-10-27

Why: a user report. (a) The Camera tab downloaded Depth Anything as soon as it opened, and the app had
no way to delete a downloaded model. (b) On an iPhone that is not an iPhone 17 model, VoxCPM2 failed
after its 4.3 GB download with "AIModelError error 0": its iOS files are `*.h18p.aimodelc` only.
Fixed: a "Downloaded models" list (the button next to the Chat, Camera and Audio pickers) with sizes
and a delete; Depth, Detect and Action show "Not downloaded yet" and a "Download <size>" button
instead of downloading on open; Speak marks the voices this device cannot run and says why before any
download (coreai-kit `KitSpeaker.unavailableReason(for:)`). On a phone other than an iPhone 17 model
none of the live catalog's four iOS voices runs in 2.0.2.
Code: coreai-kit `3a82d60` (branch `ane-variant`: c4fc800 + 3a82d60 on e25f7ad) and this repo's
`e7e990d` (7f3be69, c3b292d, 9966545, e7e990d on 5c7e4b2). The archive builds against
`../coreai-kit`, which must be on `ane-variant` at 3a82d60 or later: the app calls
`KitSpeaker.unavailableReason(for:)`.

Device check before upload: `UITests/DownloadsTests` on the iPhone 18 Pro (iOS 27.2 24B5099f), dev
build (`com.daisukemajima.coreaizoo`), 2026-10-27 12:08–12:11 JST: 4 passed, 1 skipped (the speak
test, which needs an iPhone 17 model). The first run (12:00–12:02) found the Speak row broken on that
phone: the `.fixedSize()` voice Picker showed "VoxCPM 0.5B (not on this device)" and squeezed
"Download & Load" to a letter or two per line; c3b292d picks the voice from a Menu, as CoreAIKitUI's
ModelPickerBar does. The runner asked for the phone's passcode once ("Enable UI Automation"); the
run about seven minutes later did not ask again. The camera permission alert outlives an app
relaunch and blocks the next test's taps until it is answered.

Traced §1–§4 again with the RC `27A266a`: sentinels 1/2 present, 151 FoundationModels symbols.
`BUILD_NUMBER=11 ./make-testflight.sh`: the archive's Info.plist read 2.0.2 / 11 /
`com.daisukemajima.CoreAIChat`; UPLOAD SUCCEEDED at 12:18 JST.

Submission: `asc_submit_version.py 2.0.2 11 --whats-new docs/WHATS_NEW_2.0.2.txt --go` (JST
12:18–12:21): build 11 VALID at 12:20; version 2.0.2 created (MANUAL), build attached, What's New set
(397 chars); review submitted 2026-10-27T03:21:00Z → version WAITING_FOR_REVIEW.
TestFlight: `asc_publish_build.py 11 --whats-new docs/WHATS_NEW_2.0.2_TESTFLIGHT.txt` added build 11
to Public Preview and set What to Test; the beta review was submitted at 2026-10-27T03:21:26Z
(`POST /betaAppReviewSubmissions` with the build) → externalBuildState WAITING_FOR_BETA_REVIEW.
After App Store approval, release 2.0.2 by hand (ASC button or appStoreVersionReleaseRequests).
