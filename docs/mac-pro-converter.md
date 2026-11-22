# PDFs to Large Score, on the Mac Pro

For pieces that only exist as a PDF. The Mac Pro (2013, Intel, macOS 12 Monterey)
converts each PDF to MusicXML with Audiveris and puts it, with the PDF beside it,
in a folder in iCloud Drive. The iPad reads that folder: the piece appears in the
library marked "Check against the PDF".

Pieces written in MuseScore don't need any of this: export them as MusicXML
straight into the same iCloud Drive folder.

## Once, on the Mac Pro

1. **iCloud Drive** on (System Preferences, Apple ID, iCloud), signed in with the
   same Apple Account as the iPad.
2. **Audiveris:** download `Audiveris-5.11.0-macosx-x86_64.dmg` (the Intel build)
   from github.com/Audiveris/audiveris/releases and drag Audiveris into
   Applications. It isn't signed by a known developer: the first time, right-click
   it in Applications, choose Open, and confirm. If it doesn't start on Monterey
   (it brings its own Java 25), try the newest earlier release that does.
3. **The converter:** copy the `scripts/macpro` folder from the Large Score
   repository to the Mac Pro, open Terminal there and run `bash install.sh`. It
   makes the folder "Large Score" in iCloud Drive, with "PDF in" inside it, and
   starts watching. `bash install.sh --remove` takes it away again.
4. **MuseScore Studio**, for fixing what Audiveris got wrong (musescore.org). If
   the newest version doesn't install on Monterey, musescore.org keeps older ones.

## Once, on the iPad

Large Score, Settings, Music Folder, Choose Folder: iCloud Drive, "Large Score".

## Every PDF

1. Put the PDF in iCloud Drive, "Large Score", "PDF in" (from any Mac or iPad
   signed in to that Apple Account).
2. Within a minute the Mac Pro converts it. The MusicXML and the PDF appear in
   "Large Score", the PDF moves to "PDF in", "Converted". A PDF that can't be
   read moves to "Not converted"; the log is `~/Library/Logs/LargeScoreConverter.log`.
3. On the iPad the piece appears in the library marked "Check against the PDF".
   Touch and hold its card, Compare with PDF: the original and Large Score's
   engraving side by side. Mark as Checked when it matches.
4. Something wrong: on the iPad, Fix Notes (on the compare screen, or touch and
   hold the card). Tap a note to change its pitch (Higher, Lower, Sharp, Flat,
   Natural), its length, a dot, a tie or a rest; tap a bar to add a rehearsal
   mark, a tempo word or a fermata. Bars whose notes don't add up to the time
   signature are outlined. Save Fixes keeps the version before, for Restore
   Previous Version.
5. Anything Fix Notes can't do (adding bars, chords, a second voice, lyrics):
   open the `.mxl` from "Large Score" in MuseScore Studio on the Mac Pro, fix it,
   and export it as MusicXML over the same file. The iPad takes the new version,
   keeps the notes written on it, and counts it as checked.

## What to expect

Tested on a clean digital PDF of a one-voice part (2026-11-22): every note, bar,
slur, dynamic, hairpin and repeat right; rehearsal marks, the tempo word and a
fermata missing. Check those first. Chords, several voices, triplets and lyrics
are harder and haven't been tested on real files yet.

The Mac Pro must be on and logged in for conversion; nothing else needs to stay open.
