#!/bin/bash
# Sets up the Large Score PDF converter on this Mac: copies convert-pdfs.sh into
# Application Support and starts a launch agent that runs it whenever the
# "PDF in" folder (in iCloud Drive, Large Score) changes, and every 10 minutes.
# Run it once from Terminal:  bash install.sh
# Undo:                       bash install.sh --remove
set -eu
LABEL=com.kvds.largescore.converter
HOME_DIR="$HOME/Library/Application Support/LargeScoreConverter"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LARGE_SCORE="$HOME/Library/Mobile Documents/com~apple~CloudDocs/Large Score"

if [ "${1:-}" = "--remove" ]; then
  launchctl unload "$PLIST" 2>/dev/null || true
  rm -f "$PLIST"
  rm -rf "$HOME_DIR"
  echo "The converter is removed. Your folders and files are untouched."
  exit 0
fi

if [ ! -d "$HOME/Library/Mobile Documents/com~apple~CloudDocs" ]; then
  echo "iCloud Drive isn't on for this Mac. Turn it on in System Preferences, Apple ID, iCloud."
  exit 1
fi
if [ ! -x /Applications/Audiveris.app/Contents/MacOS/Audiveris ]; then
  echo "Install Audiveris in Applications first (docs/mac-pro-converter.md)."
  exit 1
fi

mkdir -p "$HOME_DIR" "$HOME/Library/LaunchAgents" "$LARGE_SCORE/PDF in"
cp "$(dirname "$0")/convert-pdfs.sh" "$HOME_DIR/convert-pdfs.sh"
chmod +x "$HOME_DIR/convert-pdfs.sh"

cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>$LABEL</string>
	<key>ProgramArguments</key>
	<array>
		<string>/bin/bash</string>
		<string>$HOME_DIR/convert-pdfs.sh</string>
	</array>
	<key>WatchPaths</key>
	<array>
		<string>$LARGE_SCORE/PDF in</string>
	</array>
	<key>StartInterval</key>
	<integer>600</integer>
	<key>RunAtLoad</key>
	<true/>
</dict>
</plist>
PLIST

launchctl unload "$PLIST" 2>/dev/null || true
launchctl load "$PLIST"
echo "The converter is running. Put PDFs in iCloud Drive, Large Score, PDF in."
