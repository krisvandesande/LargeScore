# Privacy, accessibility answers and review notes

## App Privacy

**Data Not Collected.** The app has no accounts, analytics, ads or servers. Music,
programmes and notes stay on the device; once iCloud sync is on
(docs/icloud-setup.md) they're in the person's own private iCloud database, which
Apple doesn't count as collection by the developer.

Privacy policy URL: needed by App Store Connect; one short page saying the above.
Not written yet: where it should live (kvdsmedia site or the GitHub repo) is Kris's call.

## Accessibility (App Store accessibility labels)

Claim only what's been checked; the common tasks are opening a piece, turning pages,
adding music, making a programme and writing notes.

| Feature | Claim | Basis |
|---|---|---|
| Larger Text | Yes | Every screen follows Dynamic Type; swept at AX5 on iPad mini, iPad and iPad Pro 13. The reader's strip and the notes palette stop at xxxLarge on purpose; the music has its own size. |
| Dark Interface | Yes | Every screen in dark, including a white-on-black page. |
| Differentiate Without Color Alone | Yes | Chosen options carry a checkmark; notes are marks and lines, not colour alone. |
| Sufficient Contrast | Yes | Text 4.5:1 or more, the accent 9.5:1 (light) and 10:1 (dark); the contrast audit's two flags measured and explained in docs/accessibility-findings.md. |
| Reduced Motion | Yes | No animations beyond the system's own; page turns are instant. |
| Voice Control | Yes, after the hand check | Every control has a spoken name containing its words (checked by AccessibilityTreeTests). |
| VoiceOver | Not yet | Opening, turning, adding music and programmes work by ear in the tree; writing notes needs sight, so this waits for the hand check and for deciding whether notes count as a common task. |
| Captions, Audio Descriptions | Not applicable | No audio or video. |

## Notes for App Review

Large Score opens MusicXML files and has none of its own. To try it: download any
MusicXML or .mxl file (for example from the MusicXML test suite at w3.org), open it
from Files or AirDrop it to the iPad, choose a part, tap Add, and open the piece in
the Library.
