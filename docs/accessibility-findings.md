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
