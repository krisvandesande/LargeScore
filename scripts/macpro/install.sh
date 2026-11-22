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

# Audiveris reads words (tempo, section names, rehearsal marks) with Tesseract,
# which needs a language file; without it every word in the PDF is lost.
TESSDATA="$HOME_DIR/tessdata"
ENG_SHA=daa0c97d651c19fba3b25e81317cd697e9908c8208090c94c3905381c23fc047
mkdir -p "$TESSDATA"
if [ "$(shasum -a 256 "$TESSDATA/eng.traineddata" 2>/dev/null | cut -d' ' -f1)" != "$ENG_SHA" ]; then
  echo "Downloading the English language file for reading words (23 MB)..."
  curl -fsSL -o "$TESSDATA/eng.traineddata.part" https://github.com/tesseract-ocr/tessdata/raw/main/eng.traineddata
  if [ "$(shasum -a 256 "$TESSDATA/eng.traineddata.part" | cut -d' ' -f1)" != "$ENG_SHA" ]; then
    rm -f "$TESSDATA/eng.traineddata.part"
    echo "The language file didn't match what was expected; words won't be read. Ask Kris."
  else
    mv "$TESSDATA/eng.traineddata.part" "$TESSDATA/eng.traineddata"
  fi
fi
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
