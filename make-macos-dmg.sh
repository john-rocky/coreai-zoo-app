#!/usr/bin/env bash
# make-macos-dmg.sh — archive CoreAI Zoo for macOS, export with Developer ID, notarize, staple, dmg.
#
# Same shape as make-testflight.sh, for the Mac side. Nothing here publishes anything: the result
# is build/CoreAIZoo-<version>-<build>.dmg, notarized and stapled, verified with spctl. Where it goes
# (GitHub release, site) is a separate decision.
#
# Usage:
#   export ASC_KEY_P8=~/.appstoreconnect/private_keys/AuthKey_3ZR8BRVF9H.p8
#   export ASC_KEY_ID=3ZR8BRVF9H
#   export ASC_ISSUER_ID=69a6de96-8f3e-47e3-e053-5b8c7c11a4d1
#   export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
#   BUILD_NUMBER=9 ./make-macos-dmg.sh
set -euo pipefail

APP_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD="$APP_DIR/build"
ARCHIVE="$BUILD/CoreAIZoo-mac.xcarchive"
EXPORT="$BUILD/mac-export"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
SHIP_BUNDLE_ID="${SHIP_BUNDLE_ID:-com.daisukemajima.CoreAIChat}"

: "${DEVELOPER_DIR:?set DEVELOPER_DIR}"
: "${ASC_KEY_P8:?set ASC_KEY_P8}"
: "${ASC_KEY_ID:?set ASC_KEY_ID}"
: "${ASC_ISSUER_ID:?set ASC_ISSUER_ID}"

echo "==> Xcode: $(xcodebuild -version | head -1)"
( cd "$APP_DIR" && xcodegen generate )

# The iOS entitlements (increased-memory-limit, extended-virtual-addressing) do not exist on
# macOS; archive the Mac app without an entitlements file. Hardened runtime is required for
# notarization.
echo "==> Archiving (macOS)"
xcodebuild archive \
  -project "$APP_DIR/CoreAIZoo.xcodeproj" \
  -scheme CoreAIZoo \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$ARCHIVE" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$ASC_KEY_P8" \
  -authenticationKeyID "$ASC_KEY_ID" \
  -authenticationKeyIssuerID "$ASC_ISSUER_ID" \
  PRODUCT_BUNDLE_IDENTIFIER="$SHIP_BUNDLE_ID" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  CODE_SIGN_ENTITLEMENTS="" \
  ENABLE_HARDENED_RUNTIME=YES

cat > "$BUILD/ExportOptions-developer-id.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>MFN25KNUGJ</string>
    <key>signingStyle</key>
    <string>automatic</string>
</dict>
</plist>
PLIST

echo "==> Exporting (Developer ID)"
rm -rf "$EXPORT"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportOptionsPlist "$BUILD/ExportOptions-developer-id.plist" \
  -exportPath "$EXPORT" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$ASC_KEY_P8" \
  -authenticationKeyID "$ASC_KEY_ID" \
  -authenticationKeyIssuerID "$ASC_ISSUER_ID"

APP="$EXPORT/CoreAIZoo.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DMG="$BUILD/CoreAIZoo-$VERSION-$BUILD_NUMBER.dmg"

echo "==> dmg"
rm -f "$DMG"
hdiutil create -volname "CoreAI Zoo" -srcfolder "$APP" -ov -format UDZO "$DMG" >/dev/null

# Sign the dmg container too: spctl -t install rejects an unsigned dmg ("no usable signature")
# even when the app inside is notarized and the ticket is stapled.
echo "==> Signing the dmg"
codesign --force --sign "Developer ID Application: Daisuke Majima (MFN25KNUGJ)" --timestamp "$DMG"
echo "==> Notarizing (waits for Apple)"
xcrun notarytool submit "$DMG" --key "$ASC_KEY_P8" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID" --wait
xcrun stapler staple "$DMG"

echo "==> Verify"
spctl -a -vv -t install "$DMG" 2>&1 | tail -2
codesign -dv --verbose=2 "$APP" 2>&1 | grep -E "Authority|Runtime|Identifier" | head -4
echo "==> Done: $DMG"
