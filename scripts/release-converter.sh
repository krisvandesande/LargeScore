#!/bin/bash
# Large Score Converter: a universal (Intel and Apple silicon) Release build for
# macOS 12 and later, signed with Developer ID, notarised by Apple and stapled, as
# build/converter/Large Score Converter.zip to copy to the Mac Pro.
#
# Needs a "Developer ID Application" certificate in the login keychain (only the
# Account Holder can make one: Xcode › Settings › Accounts › Manage Certificates).
# The first signing may ask once to use its key: choose Always Allow.
# Notarising uses the App Store Connect key in scripts/asc.env.
set -euo pipefail
cd "$(dirname "$0")/.."
[ -f scripts/asc.env ] && source scripts/asc.env
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
: "${ASC_KEY_ID:?set ASC_KEY_ID in scripts/asc.env}"
: "${ASC_ISSUER_ID:?set ASC_ISSUER_ID in scripts/asc.env}"
: "${ASC_KEY_PATH:=$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8}"

identity=$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p' | head -n 1)
if [ -z "$identity" ]; then
  echo "error: no Developer ID Application certificate in the keychain (Xcode › Settings › Accounts › Manage Certificates)" >&2
  exit 1
fi

out=build/converter
rm -rf "$out/Release" && mkdir -p "$out"
xcodegen generate >/dev/null
xcodebuild -project LargeScore.xcodeproj -scheme LargeScoreConverter -configuration Release \
  -destination "generic/platform=macOS" -derivedDataPath build/ddconv \
  CODE_SIGN_IDENTITY="$identity" CODE_SIGN_STYLE=Manual OTHER_CODE_SIGN_FLAGS="--timestamp" \
  build | grep -E "error:|warning: .*sign|BUILD" || true

app="build/ddconv/Build/Products/Release/Large Score Converter.app"
[ -d "$app" ] || { echo "error: the build failed" >&2; exit 1; }
lipo -info "$app/Contents/MacOS/Large Score Converter"
codesign --verify --strict --deep "$app"

zip="$out/Large Score Converter.zip"
rm -f "$zip"
ditto -c -k --keepParent "$app" "$zip"
xcrun notarytool submit "$zip" --key "$ASC_KEY_PATH" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID" --wait
xcrun stapler staple "$app"
# The stapled app, zipped again for copying.
rm -f "$zip"
ditto -c -k --keepParent "$app" "$zip"
spctl --assess --type execute --verbose "$app"
echo "Ready: $zip"
