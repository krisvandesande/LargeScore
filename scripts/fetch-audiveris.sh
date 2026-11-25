#!/bin/bash
# Fetches Audiveris (AGPL-3.0, unmodified) for bundling into Large Score Converter:
# the Intel build, which the Mac Pro needs and Apple silicon runs through Rosetta.
# Checks the download against the checksum GitHub publishes, agrees to the disk
# image's licence screen (the AGPL itself), and copies the app to
# vendor/audiveris/Audiveris.app (gitignored). scripts/release-converter.sh puts it
# in the app and signs it.
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${AUDIVERIS_VERSION:-5.11.0}"
ASSET="Audiveris-$VERSION-macosx-x86_64.dmg"
work=vendor/audiveris-download
mkdir -p "$work"

read -r url digest < <(gh api "repos/Audiveris/audiveris/releases/tags/$VERSION" \
  --jq ".assets[] | select(.name==\"$ASSET\") | \"\(.browser_download_url) \(.digest)\"")
[ -n "${url:-}" ] || { echo "error: $ASSET not found in release $VERSION" >&2; exit 1; }
dmg="$work/$ASSET"
[ -f "$dmg" ] || curl -sSL -o "$dmg" "$url"
actual="sha256:$(shasum -a 256 "$dmg" | cut -d' ' -f1)"
[ "$actual" = "$digest" ] || { echo "error: checksum mismatch for $ASSET" >&2; rm -f "$dmg"; exit 1; }

mount=$(mktemp -d)
yes Y | hdiutil attach -nobrowse -readonly -noautoopen -mountpoint "$mount" "$dmg" >/dev/null
trap 'hdiutil detach "$mount" -quiet || true' EXIT
rm -rf vendor/audiveris && mkdir -p vendor/audiveris
ditto "$mount/Audiveris.app" vendor/audiveris/Audiveris.app
echo "$VERSION" > vendor/audiveris/VERSION
echo "Audiveris $VERSION in vendor/audiveris"
