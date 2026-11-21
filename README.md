# Large Score

An iPad app that reads MusicXML and lays the music out again at the size you need: only your own part, as few bars a line as your eyes ask for, pages turned by tap, swipe or a Bluetooth pedal.

## Building

1. `scripts/fetch-verovio.sh` fetches the pinned Verovio release into `Packages/VerovioKit/verovio`.
2. `xcodegen generate`, then open `LargeScore.xcodeproj`.

## Licences

The app's own code is MIT (see `LICENSE`). It is built with [Verovio](https://github.com/rism-digital/verovio), LGPL-3.0, used unmodified from its release tag through a small Swift package (`Packages/VerovioKit`) that declares Verovio's own targets. To build Large Score with another Verovio, set `VEROVIO_TAG` (or replace `Packages/VerovioKit/verovio`) and rebuild: the full source of the app is here for that. Verovio's music fonts (Leipzig, Bravura) are under the SIL Open Font License.
