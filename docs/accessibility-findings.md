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
