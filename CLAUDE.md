# Large Score — session notes

Single-maintainer repo (public: github.com/krisvandesande/LargeScore); work on `main` and push.

## What it is

An iPad app (and the same app on the Mac through Mac Catalyst) that reads MusicXML and engraves it again at a large size: only your own part, as few bars a line as you ask for, pages turned by tap, swipe or a Bluetooth pedal. Made for Kris's grandfather (early nineties, low vision, still performing, writes his own scores in notation software); App Store release later. Layout B (tabs Today, Programmes, Library, Settings; reader with a strip at the foot), chosen 2026-11-21: `docs/design-decisions.md`.

Licences: the app is MIT; Verovio (LGPL-3.0) is used unmodified from its release tag. Keep it unmodified and keep it swappable (`VEROVIO_TAG`), as the README promises.

## Repo

- `project.yml` is the source of the project (XcodeGen). `LargeScore.xcodeproj` is generated but committed: edit `project.yml`, then `xcodegen generate`, and commit both.
- `LargeScore/`: `App` (entry, `LayoutKit`, `Style`, `ReaderSettings`), `Engraving` (Verovio, `SVGScene`, `TextLayout`, `PartSplitter`), `Import` (files, `.mxl` ZIP reader, music folder), `Library`, `Programmes`, `Reader`, `Notes`, `Onboarding`, `Settings`, `Resources/Samples` (the bundled test pieces).
- `Packages/VerovioKit`: a small package declaring Verovio's own targets over `Packages/VerovioKit/verovio` (gitignored, fetched).
- `docs/`: `accessibility-findings.md` (per phase), `design-decisions.md`, `icloud-setup.md`, `voiceover/` (reading-order trees per device and screen, kept so a later run shows what changed).
- `AppStore/`: `store-text.md` (English and Dutch drafts for Kris to approve; nothing is in App Store Connect yet), `privacy-and-review.md` (privacy, accessibility answers, review notes; privacy policy page not written yet).
- `scripts/`: `fetch-verovio.sh`, `sweep.sh`, `release.sh`, `asc.py`, `enable-icloud.sh`, `make-test-piece.py`, `make-icon.swift`. `scripts/asc.env` is gitignored.

## Build and test

`xcode-select` points at the Command Line Tools, so prefix `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` for `xcodebuild` and `xcrun simctl`.

```sh
scripts/fetch-verovio.sh          # once per clone: Verovio version-6.4.1
xcodegen generate
xcodebuild -project LargeScore.xcodeproj -scheme LargeScore \
  -destination "id=<simulator udid>" -derivedDataPath build/dd test
```

- One scheme, `LargeScore`, testing `LargeScoreTests` (engraving, import, notes, programmes, reader, render tests) and `LargeScoreUITests` (`ScreenSweepTests`, `AccessibilityTreeTests`). iPad and Mac only (`TARGETED_DEVICE_FAMILY` 2,6): use an iPad simulator.
- Render tests write their pictures to `build/` (simulator) or the app's temporary folder (Mac).
- Mac build check without signing: `-destination "platform=macOS,variant=Mac Catalyst" -derivedDataPath build/ddmac build CODE_SIGNING_ALLOWED=NO`.
- Launch arguments for tests: `-resetSettings` (clean settings, library in memory), `-skipOnboarding`, `-importSamples` (opens the import sheet with the bundled samples).

## Accessibility sweep

`scripts/sweep.sh` makes (or reuses) its own simulators "LS iPad mini", "LS iPad" and "LS iPad Pro 13" on iOS 27.2, warms new ones up, runs `LargeScoreUITests` on each at standard size and AX5, light and dark, and checks crash reports after each run. Screenshots go to `build/sweep/<date>/`, audit lines to its logs, reading-order trees to `docs/voiceover/` (tracked: a run changes them). Write the verdicts into `docs/accessibility-findings.md`.

## Gotchas

- **Verovio's page units are 9/8 of a point,** not points. Notes landed off their bars until everything was drawn inside the music's own transform.
- **Test with real files.** Kris's first real piece (The Entertainer) exposed text, chord-name and page-fill bugs the generated test pieces never showed.
- Notes are stored in staff spaces from their bar's staff, so they stay on their bar at any size and through a new version of the piece.
- Version and build come from the build settings (`MARKETING_VERSION`, `CURRENT_PROJECT_VERSION` in `project.yml`); XcodeGen once wrote fixed values into Info.plist and build 2 archived as 1.
- Local builds are named "Large Score (Debug)" / "Large Score (Test)"; archives keep the plain name and `release.sh` refuses a tagged one.
- `.onKeyPress` doesn't reach a full-screen cover; pedal keys go through a first-responder view with key commands. Page Up/Down never arrive from the simulator's runner.
- iCloud sync is on (container `iCloud.com.kvds.LargeScore`, 2026-11-22); the CloudKit schema still needs deploying to production once (`docs/icloud-setup.md`, step 3). Xcode's agent tools build headless and see "No Accounts": anything that needs Kris's account (registering a container) needs a build in his Xcode window.
- PDFs go through Audiveris on the grandfather's Mac Pro (2013, Intel, Monterey): `scripts/macpro/` (converter and installer, bash 3.2), guide in `docs/mac-pro-converter.md`. Files a recognition program wrote (`encoding/software`) are marked "Check against the PDF" until checked; a version saved from MuseScore counts as checked. The Large Score Mac app can't run on that Mac (macOS 26, Apple silicon).
- Fix Notes edits the MusicXML itself (`MusicXMLEdit`): every note and bar gets an id on import (`ls-n…`, `ls-m…`), Verovio keeps those ids on what it draws, and `SVGScene.noteBoxes` maps a tap back to the note. Edits assume the echo writer's form (opening and closing tags, no self-closing).

## TestFlight

- Bundle id `com.kvds.LargeScore`, App Store Connect app 6837723299.
- Bump `CURRENT_PROJECT_VERSION` in `project.yml`, `xcodegen generate`, commit as "Build N", push.
- `scripts/release.sh --note "…"` archives, uploads, gives every external group the build and submits it for beta review; `--mac` adds the Mac build, `--no-submit` skips review. The note is What to Test: agree its wording with Kris first.
- Signing is manual with API-made profiles "Large Score App Store" and "Large Score Mac App Store" (the key can't make profiles through cloud signing). After a capability change the profile must be made again.
- Kris wants the remaining phases built back to back and one TestFlight build at the end, not an upload offer per phase.

No website yet.
