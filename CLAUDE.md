# cable-tester

USB-C cable labeller: native SwiftUI Mac app (`App/`) on the `CableKit` package. README.md has
the overview; docs/app-spec-and-plan.md is the spec; docs/emarker.md the chip findings.

## Build and test
- `xcodegen generate` (project.yml is the source; the .xcodeproj is gitignored), then
  `xcodebuild -project CableTester.xcodeproj -scheme CableTester -configuration Debug -derivedDataPath build/dd build`.
- `cd CableKit && swift test`. Fixtures are real `ioreg -a -r -c AppleHPMInterfaceType10 -l` dumps.
- Never open a window to check things: use the app's `--probe` (live ports, text) and
  `--snapshot <dir>` (all screens rendered offscreen from demo data).

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

## Release (notarized 2026-11-22, v0.1.0)
- Xcode's Release build has no secure timestamp: re-sign with `codesign --force --options runtime
  --timestamp -s "Developer ID Application: MAX AUBERT (WV7BY8CUM8)"`, `ditto -c -k --keepParent` to a zip,
  `xcrun notarytool submit <zip> --keychain-profile notary --wait`, then `xcrun stapler staple` the app.
- Notarized copies go to `~/Documents/Claude/zz-Misc/cable-tester/release/` (app + zip).

## Status (2026-11-22)
- v1 app built on branch `app`. Verified on the Mac mini: chip read with a Mac or a small USB device at
  the far end; far end unplugged gives no chip. Untested: charger path on the MacBook, a Thunderbolt
  link (CIO transport keys), telling Thunderbolt cables from plain USB 4 ones.
- Later ideas (Ethernet, HDMI, USB-A, transfer test): end of docs/app-spec-and-plan.md.
