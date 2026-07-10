#!/usr/bin/env bash
# make-testflight.sh — archive CoreAI Zoo and upload the build to TestFlight.
#
# Much simpler than the CoreAIChat reference: the zoo app is a THIN SHELL over the coreai-kit
# Swift package, which vendors the patched Core AI runtime — so there is NO coreai-models clone
# to patch and NO tokenizer to bundle (the kit downloads each model's bundle, tokenizer included).
# This script is just: xcodegen -> archive -> export -> upload via the App Store Connect API.
#
# Ship identity is applied here as build-setting OVERRIDES, so daily builds keep the dev bundle
# id (com.daisukemajima.coreaizoo) from project.yml and only the TestFlight archive carries the
# existing "CoreAI Zoo" App Store Connect record's bundle id (com.daisukemajima.CoreAIChat).
#
# Prerequisites (the parts this script can NOT do for you):
#   1. An App Store Connect API key (Users and Access > Integrations > App Store Connect API),
#      role "App Manager" or higher: a .p8 file, a Key ID, and an Issuer ID.
#   2. The existing app record "CoreAI Zoo" (bundle id com.daisukemajima.CoreAIChat) — already
#      exists in App Store Connect; this uploads a new build to it.
#   3. An AppIcon asset (1024 incl.) in the asset catalog — TestFlight validation requires it
#      (error 90713 / 90704). Add it before running (P4.1).
#   4. Xcode 27 beta 2 (27A5209h) or newer selected via DEVELOPER_DIR — beta 1 (27A5194q) is
#      rejected by App Store Connect (90534 Unsupported SDK); ASC accepts only the latest beta/RC.
#
# Usage:
#   export ASC_KEY_P8=~/.appstoreconnect/private_keys/AuthKey_3ZR8BRVF9H.p8
#   export ASC_KEY_ID=3ZR8BRVF9H
#   export ASC_ISSUER_ID=69a6de96-8f3e-47e3-e053-5b8c7c11a4d1
#   export DEVELOPER_DIR=/Applications/Xcode-27.0.0-Beta.3.app/Contents/Developer
#   ./make-testflight.sh                 # build number defaults to 6
#   BUILD_NUMBER=8 ./make-testflight.sh  # or override
#
# ⚠️ Devices on an OLDER OS beta seed than the archiving SDK dyld-crash at launch when a
# framework's Swift manglings churn between seeds (FoundationModels did, beta 1 -> beta 3;
# build 7 crashed on launch on beta 1 devices). The app weak-links FoundationModels and
# gates the FM features (see FMSeedGate.swift) so a seed mismatch degrades gracefully —
# keep that in place while the app targets OS betas.
set -euo pipefail

APP_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD="$APP_DIR/build"
ARCHIVE="$BUILD/CoreAIZoo.xcarchive"

# The existing "CoreAI Zoo" ASC record lives under this bundle id (see ZOO_APP_SHIP_KICKOFF.md).
SHIP_BUNDLE_ID="${SHIP_BUNDLE_ID:-com.daisukemajima.CoreAIChat}"
BUILD_NUMBER="${BUILD_NUMBER:-6}"

: "${DEVELOPER_DIR:?set DEVELOPER_DIR to the Xcode 27 beta 2+ Developer dir}"
: "${ASC_KEY_P8:?set ASC_KEY_P8 to the App Store Connect API .p8 path}"
: "${ASC_KEY_ID:?set ASC_KEY_ID}"
: "${ASC_ISSUER_ID:?set ASC_ISSUER_ID}"

echo "==> Xcode: $(xcodebuild -version | head -1)"
echo "==> Ship bundle id: $SHIP_BUNDLE_ID  build: $BUILD_NUMBER"

# 1. Generate the project from project.yml.
echo "==> xcodegen generate"
( cd "$APP_DIR" && xcodegen generate )

# 2. Archive (Release, generic iOS device, automatic signing via the API key). The ship bundle
#    id + build number are overridden here so project.yml stays on the dev id for daily builds.
echo "==> Archiving"
xcodebuild archive \
  -project "$APP_DIR/CoreAIZoo.xcodeproj" \
  -scheme CoreAIZoo \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$ASC_KEY_P8" \
  -authenticationKeyID "$ASC_KEY_ID" \
  -authenticationKeyIssuerID "$ASC_ISSUER_ID" \
  PRODUCT_BUNDLE_IDENTIFIER="$SHIP_BUNDLE_ID" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER"

# 2b. Inject the top-level CFBundleIconName. actool writes CFBundleIcons:CFBundlePrimaryIcon into
#     the generated Info.plist but NOT the top-level CFBundleIconName key that App Store Connect
#     validation requires (error 90713); the GENERATE_INFOPLIST_FILE flow on Xcode 27 beta omits
#     it and INFOPLIST_KEY_CFBundleIconName is ignored. Patch the archived app before export;
#     -exportArchive re-signs, sealing the change. Idempotent.
APP="$ARCHIVE/Products/Applications/CoreAIZoo.app"
/usr/libexec/PlistBuddy -c "Add :CFBundleIconName string AppIcon" "$APP/Info.plist" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Set :CFBundleIconName AppIcon" "$APP/Info.plist"

# 3. Export the .ipa locally (ExportOptions.plist uses destination=export — no upload yet).
echo "==> Exporting .ipa"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportOptionsPlist "$APP_DIR/ExportOptions.plist" \
  -exportPath "$BUILD/export" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$ASC_KEY_P8" \
  -authenticationKeyID "$ASC_KEY_ID" \
  -authenticationKeyIssuerID "$ASC_ISSUER_ID"

IPA="$BUILD/export/CoreAIZoo.ipa"

# 4. Validate, then upload to TestFlight. altool reads the key from ~/.appstoreconnect/private_keys.
#    cp exits 1 when source and destination are the same file (key already in place) — the
#    `|| true` keeps that from aborting the upload under `set -e`.
mkdir -p ~/.appstoreconnect/private_keys
cp -f "$ASC_KEY_P8" ~/.appstoreconnect/private_keys/ 2>/dev/null || true
echo "==> Validating"
xcrun altool --validate-app -f "$IPA" -t ios \
  --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"
echo "==> Uploading to TestFlight"
xcrun altool --upload-app -f "$IPA" -t ios \
  --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"

echo "==> Done. Watch processing at https://appstoreconnect.apple.com (TestFlight tab)."
echo "    Public link: https://testflight.apple.com/join/bK4P7xby"
