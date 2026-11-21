# Accessibility findings

The sweep: `scripts/sweep.sh` (fresh "LS iPad mini" and "LS iPad Pro 13" simulators, iOS 27.2, standard size and AX5, light and dark). Screenshots in `build/sweep/<date>/`, audit lines in its logs. Apple's audit runs on each screen in light mode with contrast left out until the colours are settled.

## Phase 3, 2026-11-21

### Fixed

- **The size row pushed the sample off the iPad mini's screen.** Smaller, the size and Larger side by side needed 684 pt; the column is 616 pt. The row now takes one line when it fits, else stacks.
- **Onboarding's side margins at AX5** were 128 pt (64 doubled); now 48 grows to 96 at most.
- **Pedal keys did nothing.** `.onKeyPress` needs focus, which a full-screen cover doesn't give, and keyboard shortcuts on hidden buttons never fired. A first-responder view with key commands takes them now: arrows and Space checked in the test; Page Up and Down are handled as presses but the simulator's runner never delivers them, so they're left for a real keyboard or pedal.

### Written down as the audit's, not the app's

- **"Text clipped" on Lines, Bold, Page and Light in Settings at AX5.** These are `FittingPicker` menus; the audit can't measure text inside a `Menu`'s label (as in Rosie). The screenshots show each word whole.
- **"Dynamic Type partially unsupported" on the instrument buttons, the library card, the reader strip's labels and the settings rows**, at the standard size. The AX5 screenshots show all of them at the larger size: the strip's Library button and page number, the cards and the instrument buttons grow. To recheck once more screens exist.

### Still to check by hand

- VoiceOver on a device: the page as one adjustable element ("Evening Air, Page 1 of 2, bars 1 to 8"), swiping up and down to turn.
- Page Up and Page Down from a keyboard or pedal.
- Voice Control: "Tap Size", "Tap Library".

### Second run, same day

- **One line of music a page on the iPad mini at AX5.** The strip grew to a third of the screen. It now stops growing at the largest standard size (xxxLarge): written down as intended, since the music has its own size setting and is what this screen is for.
- **Onboarding text showed behind the status bar when scrolled** at AX5; the scroll view's top edge is solid now.

## Phase 4, 2026-11-21

Changes from Kris's first look at build 1:

- **Bold was hard to tell from Thin.** Bold now takes Verovio's lines close to their limits (staff lines 0.30 staff space, stems 0.40, bar lines 0.60, slurs 0.9) and outlines every glyph by 7% of a staff space, so note heads, clefs and dynamics get heavier too. Thin is Verovio's own, close to print.
- **Three lines where five fit.** The gap between lines was a fixed 14 half-spaces on top of the room Verovio already makes for slurs and dynamics; it's now Verovio's 4. On a 13-inch iPad upright at size 4 of 7: 5 lines a page (was 3).
- **Side margins.** The staff ran from 108 pt on the left to 64 pt on the right. Now 12 pt in the reader plus an equal small margin inside the page for bar numbers: measured on the 13-inch screenshot, 69 px (34.5 pt) from each edge.
- **Several instruments, several parts.** Setup and Settings take every instrument played; the import sheet and the library's Change Parts take several parts, read together. Rehearsal marks and tempo, which notation programs write into every part, show once, on the top part.
- **An AirDropped .mxl went to Files.** The app now offers to open any file (lowest rank) and ZIP archives besides its own types, and Add Music accepts any file; the contents are checked when read.
- **The Entertainer (Kris's first real file, build 2):** about 380 pt of room left under three lines; the tempo's note missing; chord names at the wrong size and overlapping, with a missing-character box; a brace before each line. Text is now laid out span by span as Verovio writes it, with SMuFL characters drawn from Verovio's own glyph outlines; the one-part copy drops the score's part groups; pages are filled with a tight bottom margin and engraved again with more room only when something under a page's last line would run off.

## Phase 5, 2026-11-21

- **Add Pieces went into the toolbar's overflow menu** once Rename joined Reorder. It's now a large button after the programme's last piece, always in sight.
- **"Dynamic Type partially unsupported" on Rename and Reorder** in the navigation bar: the system's own bar buttons, written down as the platform's.
- The reader's Next button names the piece ("Next piece: Long Evening Air"); a piece reached by a pedal or tap past the end is announced by its title.

## Phase 6, 2026-11-21

- **Notes landed off their bars.** Verovio's page units are 9/8 of a point, and the notes were drawn and read in points. They're now drawn inside the music's own transform and touches are converted; checked at sizes 4 and 6 of 7 that a circle, a highlight, a breath mark and ink stay on their bars.
- **The notes palette stops growing at xxxLarge**, like the reader's strip: written down as intended (the audit's "partially unsupported" on its buttons).
- **Writing notes is a visual task.** VoiceOver hears how many notes a page has ("Page 1 of 2, bars 1 to 8, 3 notes") and every tool has a spoken name ("Finger 3" for the button showing 3); placing marks needs sight, which is written down rather than worked around.

## Phase 7, 2026-11-21

- **Sizes:** the sweep now runs on the iPad mini, the standard iPad (A16) and the iPad Pro 13, standard and AX5, light and dark, with landscape shots of the library and the reader on each.
- **Reading order:** each screen's accessibility tree is written to `docs/voiceover/<device>-<screen>.txt` by `AccessibilityTreeTests`, kept so a later run shows what changed. The reader is heard as the music first ("Evening Air for Four, Page 1 of 1, bars 1 to 16"), then the strip.
- **Spoken names:** every button, switch and field has one; the check counts the outermost control only, since a menu or switch shows as a named control around an unnamed inner one (Sort, Half-Page Turns). Tab buttons carry system icon ids ("music.note.list") as identifiers, but VoiceOver reads their labels ("Today").
- **Contrast, audited on its own:** two flags, both kept. Undo in the notes palette is disabled until there is something to undo (40% opacity; WCAG exempts disabled controls). Add Music in the library toolbar was flagged in light and dark; measured on the screenshots it is 8.4:1 (light) and 8.1:1 (dark) against the toolbar's glass, so the audit misreads the glass.
- **Still for a real iPad, by hand:** VoiceOver gestures on the page (swipe up and down to turn), Voice Control ("Tap Notes", "Tap Next Piece"), and how a piece reached by pedal is announced.

## VoiceOver, 2026-11-21

Not claimed on the App Store: reading sheet music needs sight, so someone using VoiceOver can't play from Large Score (Kris). Spoken names, the reading order and the page's spoken value stay, since Voice Control, Switch Control and Full Keyboard Access use them; the by-hand VoiceOver check is dropped from the release list.

## Apple's audits (Xcode plugin), 2026-11-21

Run with Apple's `accessibility-dynamic-type-specialist` and `accessibility-sufficient-contrast-specialist` skills over the source; VoiceOver skipped (not claimed).

- **Dynamic Type: PASS after two fixes.** Every text uses a text style; the one fixed `.system(size:)` (LayoutKit's disclosure triangle) is driven by `@ScaledMetric`; the fixed frames hold engraved music, which has its own size setting. Fixed: the reader's strip and the notes palette, capped at xxxLarge so the music keeps the screen, now show every control in the Large Content Viewer (touch and hold), as Apple's criteria ask of capped bars; "Next: title" keeps the whole title (`fixedSize`) so the strip switches layout instead of cutting it.
- **Contrast: PASS after two fixes.** Computed: accent on button fill 7.3:1 light, 8.4:1 dark; chosen buttons 9.4:1 and 10.4:1; notes colour 6.5:1 on white, 9.2:1 on black; music on a highlight 17.9:1 and 8.6:1. Fixed: the bar highlight (1.2:1 on white, 2.4:1 on black as a fill alone) has an outline in the notes colour; section headers and footers, in the system's secondary grey at 13 pt (3.3:1 in light, enough only for large text), are now body and headline size in a quiet grey of their own (#55555A light, 6.6:1; #C7C7CC dark, 10:1). The audit tests' two remaining flags are unchanged: disabled Undo, and Add Music on the toolbar glass (measured 8.4:1 and 8.1:1).
