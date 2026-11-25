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
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
  build | grep -E "error:|warning: .*sign|BUILD" || true

app="$PWD/build/ddconv/Build/Products/Release/Large Score Converter.app"
[ -d "$app" ] || { echo "error: the build failed" >&2; exit 1; }
lipo -info "$app/Contents/MacOS/Large Score Converter"

# Audiveris inside the app (Contents/Helpers), signed from the inside out with the
# same Developer ID: notarisation checks every program and library, the native
# libraries inside its jars included.
[ -d vendor/audiveris/Audiveris.app ] || scripts/fetch-audiveris.sh
helper="$app/Contents/Helpers/Audiveris.app"
rm -rf "$app/Contents/Helpers" && mkdir -p "$app/Contents/Helpers"
ditto vendor/audiveris/Audiveris.app "$helper"
entitlements=scripts/audiveris.entitlements
sign() { codesign --force --timestamp --options runtime --sign "$identity" "$@"; }
while IFS= read -r -d '' jar; do
  # Jars that carry native code for the Mac: every Mach-O file inside, whatever its
  # name (Tesseract's own program has no extension).
  # Listed first, then tested: a pipe into grep -q fails under pipefail when grep
  # stops reading early, which skipped jars at random.
  listing=$(unzip -Z1 "$jar" 2>/dev/null || true)
  grep -qE '\.(dylib|jnilib)$|macosx|darwin' <<< "$listing" || continue
  tmp=$(mktemp -d)
  (cd "$tmp" && unzip -o -q "$jar" < /dev/null)
  natives=()
  while IFS= read -r -d '' f; do
    [[ $(file -b "$f") == *Mach-O* ]] || continue
    sign "$f" >/dev/null
    natives+=("${f#$tmp/}")
  done < <(find "$tmp" -type f -print0)
  [ ${#natives[@]} -gt 0 ] && (cd "$tmp" && zip -q "$jar" "${natives[@]}")
  rm -rf "$tmp"
done < <(find "$helper" -name '*.jar' -print0)
while IFS= read -r -d '' file; do
  [[ $(file -b "$file") == *Mach-O* ]] || continue
  case "$file" in
    */Contents/MacOS/*|*/bin/*|*jspawnhelper) sign --entitlements "$entitlements" "$file" >/dev/null ;;
    *) sign "$file" >/dev/null ;;
  esac
done < <(find "$helper" -type f -print0)
# Nothing unsigned may be left inside a jar: notarisation looks inside them.
while IFS= read -r -d '' jar; do
  tmp=$(mktemp -d)
  (cd "$tmp" && unzip -o -q "$jar" < /dev/null) || true
  while IFS= read -r -d '' f; do
    [[ $(file -b "$f") == *Mach-O* ]] || continue
    codesign --verify "$f" 2>/dev/null || { echo "error: unsigned native code in $(basename "$jar"): ${f#$tmp/}" >&2; exit 1; }
  done < <(find "$tmp" -type f -print0)
  rm -rf "$tmp"
done < <(find "$helper" -name '*.jar' -print0)
sign --entitlements "$entitlements" "$helper" >/dev/null
# The Converter itself again, over its new contents.
sign --preserve-metadata=entitlements "$app" >/dev/null
codesign --verify --strict --deep "$app"

zip="$out/Large Score Converter.zip"
rm -f "$zip"
ditto -c -k --keepParent "$app" "$zip"
# The debugging entitlement Xcode adds would make Apple refuse it.
if [[ $(codesign -d --entitlements - "$app" 2>/dev/null || true) == *get-task-allow* ]]; then
  echo "error: the app still asks for get-task-allow" >&2; exit 1
fi
result=$(xcrun notarytool submit "$zip" --key "$ASC_KEY_PATH" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID" --wait 2>&1)
echo "$result"
if [[ $result != *"status: Accepted"* ]]; then
  id=$(echo "$result" | sed -n 's/^ *id: //p' | head -n 1)
  echo "error: Apple didn't accept it. Why: xcrun notarytool log $id --key … --key-id … --issuer …" >&2
  exit 1
fi
xcrun stapler staple "$app"
# The stapled app, zipped again for copying.
rm -f "$zip"
ditto -c -k --keepParent "$app" "$zip"
spctl --assess --type execute --verbose "$app"
echo "Ready: $zip"
