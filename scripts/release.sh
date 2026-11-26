#!/bin/bash
#
# Archive Large Score, upload it to TestFlight, then hand every external tester group the
# build and submit it for beta review.
#
# One command, because the manual version has four steps and the one people forget is
# the last one — a build that processes cleanly and then sits there reaching nobody.
#
# Usage:
#   scripts/release.sh --note "…"                 # iOS
#   scripts/release.sh --note "…" --mac           # macOS as well
#   scripts/release.sh --note "…" --no-submit     # add the groups, don't submit for review
#   scripts/release.sh --note "…" --internal-only # internal testers only: no review, no groups
#
# --note is what testers read under What to Test. It is required, and it is text
# other people read: agree the wording before running this.
#
# Credentials, once, in your shell profile or in scripts/asc.env:
#   export ASC_KEY_ID=7G4HDP7YGG
#   export ASC_ISSUER_ID=<the UUID from App Store Connect → Users and Access → Keys>
#
set -euo pipefail

cd "$(dirname "$0")/.."

# Optional untracked file so the issuer id doesn't have to live in a shell profile.
[ -f scripts/asc.env ] && source scripts/asc.env

# A machine whose xcode-select points at the Command Line Tools can't archive
# anything — xcodebuild exits with "requires Xcode". Pointing DEVELOPER_DIR at the
# real Xcode fixes it for this process only, which beats needing sudo to change a
# global setting in order to run a release.
if [ -z "${DEVELOPER_DIR:-}" ] && ! xcode-select -p 2>/dev/null | grep -q "Xcode.app"; then
  if [ -d /Applications/Xcode.app ]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
    echo "note: xcode-select points outside Xcode; using $DEVELOPER_DIR"
  else
    echo "error: no Xcode found — xcodebuild can't archive with the Command Line Tools alone" >&2
    exit 1
  fi
fi

: "${ASC_KEY_ID:?set ASC_KEY_ID (the ten-character App Store Connect key id)}"
: "${ASC_ISSUER_ID:?set ASC_ISSUER_ID (the issuer UUID from App Store Connect)}"
: "${ASC_KEY_PATH:=$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8}"
export ASC_KEY_ID ASC_ISSUER_ID ASC_KEY_PATH

BUILD_MAC=no
SUBMIT_FLAG=""
NOTE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --mac) BUILD_MAC=yes ;;
    --no-submit) SUBMIT_FLAG="--no-submit" ;;
    --internal-only) SUBMIT_FLAG="--internal-only" ;;
    --note) NOTE="${2:-}"; shift ;;
    *) echo "unknown option: $1" >&2; exit 1 ;;
  esac
  shift
done
[ -n "$NOTE" ] || { echo "error: --note \"…\" is required (what testers read under What to Test)" >&2; exit 1; }

ARCHIVE_DIR=build
mkdir -p "$ARCHIVE_DIR"

# Written here rather than read from build/, which is gitignored — a release script
# that depends on an untracked file works until the first fresh clone.
EXPORT_OPTIONS="$ARCHIVE_DIR/ExportOptions.plist"
cat > "$EXPORT_OPTIONS" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>app-store-connect</string>
	<key>destination</key>
	<string>upload</string>
	<!-- Manual: the App Store Connect key can't make profiles through Xcode's cloud
	     signing ("No profiles for com.kvds.LargeScore"). The profile was made through
	     the API (2026-11-21, "Large Score App Store") and is installed locally. -->
	<key>signingStyle</key>
	<string>manual</string>
	<key>signingCertificate</key>
	<string>Apple Distribution</string>
	<key>provisioningProfiles</key>
	<dict>
		<key>com.kvds.LargeScore</key>
		<string>Large Score App Store</string>
	</dict>
	<key>teamID</key>
	<string>UJJPJ9ZHNN</string>
	<key>uploadSymbols</key>
	<true/>
	<!-- Off: the build number is the one in the project, which is what asc.py waits
	     for. Letting Xcode bump it on upload could leave asc.py waiting forever. -->
	<key>manageAppVersionAndBuildNumber</key>
	<false/>
</dict>
</plist>
PLIST

# The Mac build is Mac Catalyst: its own profile, and a package signed with the
# installer certificate.
MAC_EXPORT_OPTIONS="$ARCHIVE_DIR/ExportOptionsMac.plist"
cat > "$MAC_EXPORT_OPTIONS" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>app-store-connect</string>
	<key>destination</key>
	<string>upload</string>
	<key>signingStyle</key>
	<string>manual</string>
	<key>signingCertificate</key>
	<string>Apple Distribution</string>
	<key>installerSigningCertificate</key>
	<string>3rd Party Mac Developer Installer</string>
	<key>provisioningProfiles</key>
	<dict>
		<key>com.kvds.LargeScore</key>
		<string>Large Score Mac App Store</string>
	</dict>
	<key>teamID</key>
	<string>UJJPJ9ZHNN</string>
	<key>manageAppVersionAndBuildNumber</key>
	<false/>
</dict>
</plist>
PLIST

# The build number the API should wait for, read from the project rather than guessed,
# so a concurrent upload from Xcode can't be mistaken for this one.
BUILD_NUMBER=$(xcodebuild -project LargeScore.xcodeproj -target LargeScore -showBuildSettings 2>/dev/null \
  | awk -F' = ' '/ CURRENT_PROJECT_VERSION /{print $2; exit}')
echo "Releasing build ${BUILD_NUMBER}"

archive_and_upload() {
  local platform="$1" archive="$2" options="${3:-$EXPORT_OPTIONS}"

  # Signed with the App Store Connect key, as Chester and Hideaway are. It used to go
  # through Xcode's signed-in account, because the key can only *download* profiles,
  # not create them. But since Xcode 27.1 xcodebuild from a script sees "No Accounts"
  # even with Kris signed in, so the account route stopped working at all.
  #
  # The catch that remains: after a capability changes (push on the watch, say),
  # the store profile has to be remade, and the key can't. Export once from Xcode's
  # Organizer (Distribute App → Custom → App Store Connect → Export) to remake it;
  # the error that means "do that" is "Cloud signing permission error".
  local auth=(-allowProvisioningUpdates
    -authenticationKeyPath "$ASC_KEY_PATH"
    -authenticationKeyID "$ASC_KEY_ID"
    -authenticationKeyIssuerID "$ASC_ISSUER_ID")

  echo "==> Archiving for ${platform}"
  xcodebuild archive \
    -project LargeScore.xcodeproj \
    -scheme LargeScore \
    -destination "generic/platform=${platform}" \
    -archivePath "$archive" \
    "${auth[@]}"
  # Archives keep the plain name; a tagged one means the naming settings broke.
  if ls "$archive/Products/Applications" | grep -q "("; then echo "error: the archived app is named for a local build (Debug or Test), not uploading" >&2; exit 1; fi

  echo "==> Uploading ${platform} build"
  xcodebuild -exportArchive \
    -archivePath "$archive" \
    -exportOptionsPlist "$options" \
    -exportPath "$ARCHIVE_DIR/export-${platform// /-}" \
    "${auth[@]}"
}

archive_and_upload "iOS" "$ARCHIVE_DIR/LargeScore-iOS.xcarchive"
if [ "$BUILD_MAC" = yes ]; then
  archive_and_upload "macOS,variant=Mac Catalyst" "$ARCHIVE_DIR/LargeScore-macOS.xcarchive" "$MAC_EXPORT_OPTIONS"
fi

echo "==> Waiting for processing, then adding testers"
python3 scripts/asc.py --build "$BUILD_NUMBER" --note "$NOTE" $SUBMIT_FLAG
if [ "$BUILD_MAC" = yes ]; then
  python3 scripts/asc.py --build "$BUILD_NUMBER" --note "$NOTE" --platform MAC_OS $SUBMIT_FLAG
fi

echo "Done."
