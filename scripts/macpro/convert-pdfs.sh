#!/bin/bash
# Large Score PDF converter, for the Mac that holds the PDFs (Monterey and later,
# Intel or Apple silicon). Converts every PDF in the "PDF in" folder to MusicXML
# with Audiveris, and puts the result with the original PDF beside it in the
# Large Score music folder, which the iPad reads. Run by the launch agent that
# install.sh sets up, whenever the "PDF in" folder changes.
#
# bash 3.2 (macOS's own), no Homebrew.

set -u
LARGE_SCORE="${LARGE_SCORE_FOLDER:-$HOME/Library/Mobile Documents/com~apple~CloudDocs/Large Score}"
INBOX="$LARGE_SCORE/PDF in"
DONE="$INBOX/Converted"
FAILED="$INBOX/Not converted"
AUDIVERIS="${AUDIVERIS:-/Applications/Audiveris.app/Contents/MacOS/Audiveris}"
LOG="$HOME/Library/Logs/LargeScoreConverter.log"
LOCK="${TMPDIR:-/tmp}/largescore-converter.lock"

mkdir -p "$INBOX" "$DONE" "$FAILED" "$(dirname "$LOG")"
log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG"; }
notify() { /usr/bin/osascript -e "display notification \"$1\" with title \"Large Score\"" >/dev/null 2>&1 || true; }

# One run at a time: the folder changes again while a run moves files.
if ! mkdir "$LOCK" 2>/dev/null; then exit 0; fi
trap 'rmdir "$LOCK" 2>/dev/null' EXIT

if [ ! -x "$AUDIVERIS" ]; then
  log "Audiveris not found at $AUDIVERIS"
  notify "Audiveris isn't installed, so PDFs can't be converted."
  exit 1
fi

converted=0
for pdf in "$INBOX"/*.pdf "$INBOX"/*.PDF; do
  [ -f "$pdf" ] || continue
  # A PDF still being copied or downloaded from iCloud: wait for the next run.
  size1=$(stat -f %z "$pdf"); sleep 2; size2=$(stat -f %z "$pdf")
  [ "$size1" = "$size2" ] || continue

  name=$(basename "$pdf"); base="${name%.*}"
  work=$(mktemp -d)
  log "converting $name"
  # Leland is MuseScore's music font: with Audiveris's default (Bravura) it missed
  # every whole note in MuseScore parts. MUSIC_FONT=Bravura for parts from Finale or Dorico.
  "$AUDIVERIS" -batch -export -option "org.audiveris.omr.ui.symbol.MusicFont.defaultMusicFamily=${MUSIC_FONT:-Leland}" \
    -output "$work" -- "$pdf" >> "$LOG" 2>&1
  # Audiveris names its output after the PDF, but may tidy the name; take what it made.
  result=$(find "$work" -name "*.mxl" -print | head -n 1)
  if [ -n "$result" ]; then
    cp "$result" "$LARGE_SCORE/$base.mxl"
    cp "$pdf" "$LARGE_SCORE/$base.pdf"
    mv "$pdf" "$DONE/$name"
    converted=$((converted + 1))
    log "done $name"
  else
    mv "$pdf" "$FAILED/$name"
    log "failed $name"
    notify "$base could not be converted. It's in the Not converted folder."
  fi
  rm -rf "$work"
done

if [ "$converted" -eq 1 ]; then
  notify "1 PDF converted. Check it against the PDF in Large Score."
elif [ "$converted" -gt 1 ]; then
  notify "$converted PDFs converted. Check them against the PDFs in Large Score."
fi
