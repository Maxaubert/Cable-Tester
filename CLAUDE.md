# cable-tester

USB-C cable labeller: native SwiftUI Mac app (`App/`) on the `CableKit` package. README.md has
the overview; docs/app-spec-and-plan.md is the spec; docs/emarker.md the chip findings.

## Build, test, release
- Typecheck/lint: the Swift compiler (`xcodegen generate` then the build below; the .xcodeproj is gitignored)
- Unit: `cd CableKit && swift test` (fixtures are real `ioreg -a -r -c AppleHPMInterfaceType10 -l` dumps)
- E2E (headless): `"<app>/Contents/MacOS/Cable Tester" --snapshot <dir>` and `--probe`    Run when: App/**
- Build / package: `xcodebuild -project CableTester.xcodeproj -scheme CableTester -configuration Debug -derivedDataPath build/dd build`   Artifact: `Cable-Tester-<version>.dmg`
- Known failures to tolerate: none
- Version source: `project.yml` (MARKETING_VERSION + CURRENT_PROJECT_VERSION, bump both)   Release: `scripts/release.sh` on this Mac after merge (not release.yml: the certificate stays in the Keychain)
- Install locally after merge: copy the app from the DMG to /Applications   Confirm version: `PlistBuddy -c "Print :CFBundleShortVersionString"` on the installed app, or About
- Deploy: DMG + Sparkle feed (`appcast.xml` as a release asset) on the releases of Maxaubert/cable-tester; apps from 0.4.6 read `releases/latest/download/appcast.xml`. Up to 0.4.5 the feed was `raw.githubusercontent.com/loftspace/cable-tester-releases/main/appcast.xml` (that repo is archived after 0.4.6, whose entry moves old installs over; 2026-11-24). Code: public, github.com/Maxaubert/cable-tester
- Signing: Developer ID WV7BY8CUM8 + notarization (profile `notary`), Sparkle EdDSA key in the Keychain (account `cable-tester`)
- Never open a window to check things: use `--probe` and `--snapshot`.

## Facts that are easy to get wrong
- Charger readings (`AdapterDetails` in `ioreg -rn AppleSmartBattery`) need a Mac with a battery
  (the MacBook Pro M5 Pro). The cable chip (`SOP'`) and the live link are readable on the Mac mini
  too (M6, Mac18,5, Thunderbolt 4, 2.5 GbE), which is where the 2026-11-22 chip tests ran.
- Power label comes from the charger's offer list (`UsbHvcMenu`), not from live draw: no load needed.
  Reading is the lower of charger and cable, so test with the Apple 140 W charger on USB-C, not MagSafe.
- Data label comes from `TransportsActive` in `ioreg -l` (`CIO` = Thunderbolt/USB4, `USB2` alone =
  USB 2 cable), speed from `system_profiler SPThunderboltDataType -json`.
- `ioreg -l` output is not valid UTF-8: decode with errors="replace".
- The cable e-marker (watts, speed, EPR, length, vendor) IS readable from the `SOP'` node in
  ioreg, see docs/emarker.md. Still no serial, so it identifies a model, not one cable.
- macOS exposes no cable ID or serial, so cables are tracked by number labels plus the CSV log
  (`~/Documents/Claude/zz-Misc/cable-tester/cables.csv`, outside the repo).

## README film
- `video/` is a HyperFrames project (spec in `video/SPEC.md`) that rebuilds the app at 1.6x. SF Pro is
  git-ignored (Apple licence): copy `/System/Library/Fonts/SFNS.ttf` to `video/assets/fonts/` first.
- `cd video && npx hyperframes render --output renders/cable-tester-demo.mp4`, copy it to `docs/media/demo.mp4`,
  then drag it into a GitHub comment box and put the `user-attachments` URL on its own line in the README
  (GitHub's player, as in Wind; there is no API for that upload). Change the film when the app's look changes.

## Release notes
- `scripts/release.sh [--notes notes.md] [--dry-run]` signs Sparkle's helpers inside out, notarizes app and
  DMG, publishes to cable-tester-releases and prepends the item to its appcast.xml. Xcode alone signs
  Sparkle's Updater.app and Autoupdate ad hoc, which notarization rejects: always release via the script.

## Status (2026-11-22)
- v0.4.0 released: app icon, Pure Black Lime theme, bolt plug-in animation, cascades (spec "Visual design").
  The Now screen tests only a cable plugged in after launch, with a two-step checklist ("Plug-in flow").
- Verified on the Mac mini: chip read with a Mac or a small USB device at the far end; far end free
  gives CC only, no chip. 2026-11-23, MacBook: chip also read with a charger at the far end (0.4.3
  shows its rated speed). Untested: a Thunderbolt link (CIO keys),
  telling Thunderbolt cables from plain USB 4 ones, a Sparkle update end to end, the animations on real hardware.
- Later ideas (Ethernet, HDMI, USB-A, transfer test): end of docs/app-spec-and-plan.md.
