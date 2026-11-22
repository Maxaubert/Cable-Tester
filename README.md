<div align="center">
  <img src="docs/icon.png" alt="Cable Tester icon" width="128">

  # Cable Tester

  Plug in a USB-C cable. See its watts and data speed.

  [![Latest release](https://img.shields.io/github/v/release/loftspace/cable-tester-releases?style=flat-square&color=a4de06&label=release)](https://github.com/loftspace/cable-tester-releases/releases/latest)
  [![macOS 15+](https://img.shields.io/badge/macOS-15%2B-a4de06?style=flat-square)](#install)
  [![Signed and notarized](https://img.shields.io/badge/signed-notarized-a4de06?style=flat-square)](#install)

  [Download](https://github.com/loftspace/cable-tester-releases/releases/latest) · [Releases](https://github.com/loftspace/cable-tester-releases/releases) · [How it reads the chip](docs/emarker.md)
</div>

https://github.com/user-attachments/assets/d37fcfc2-c120-4b40-a396-9c51f74ea87a

## About

Cable Tester is a small native Mac app that reads the chip inside a USB-C cable, so you can sort and
label a drawer of cables without a hardware tester. Plug a cable into the Mac, plug the other end
into a charger, another Mac or any USB-C device, and it shows what the cable can do.
[Watch the demo as MP4](docs/media/demo.mp4).

## Features

- Reads the cable's e-marker chip: wattage (60, 100 or 240 W), USB generation, rated speed, EPR, length and vendor.
- Shows the live link from the port: the speed it negotiated, Thunderbolt when the link is Thunderbolt, and the device at the other end.
- Works with a Mac, a charger or any small USB-C device at the far end. A charger shows watts only, since there is no data link.
- A plug-in checklist ticks off each end as it goes in; cables already connected when the app starts are ignored until you replug them.
- Cables without a chip show **60 W est.**: they are USB 2 cables limited to 3 A.
- Saves each cable with a number label and a tie colour. History edits every field in place, filters by 240/100/60 W and Thunderbolt, prints labels and exports CSV.
- Signed, notarized and updates itself.

## Install

[Download the latest DMG](https://github.com/loftspace/cable-tester-releases/releases/latest),
open it and drag **Cable Tester** into Applications.

- Needs an Apple Silicon Mac with macOS 15 or later.
- Signed with a Developer ID and notarized by Apple, so it opens without a warning.
- Checks for updates once a day (Sparkle); **Cable Tester > Check for Updates…** checks now.
- Saved cables stay in `~/Library/Application Support/Cable Tester/cables.json`.

## Usage

- **Plug in** one end into the Mac, then the other end into a charger, a Mac or a USB-C device. The result shows once both ends are in.
- **Save** (⌘S) opens a sheet filled in from the cable. Add the tie colour and anything else you know; empty fields stay blank.
- **Label** the cable with what the app gives you, for example `#13 240W USB4v2`. The copy button puts it on the clipboard.
- **History** (⌘Y) lists every saved cable. Click any value to change it; right-click a row to copy or print its label or restore the measured values.

## Limits

- A cable has no serial number, so identical cables cannot be told apart by the app. It says "same model as #03"; the number label and tie colour do the rest.
- The Mac reads the cable's chip only when something is plugged into the other end.
- Charger readings need a Mac with a battery (a MacBook). The chip and the live link work on any Mac, including a Mac mini.
- The data speed you see is the slower of the cable and the device at the other end; the app says when the device is the limit.
- Telling a Thunderbolt cable from a plain USB 4 cable has not been verified on hardware yet.

## Development

`xcodegen generate` creates the Xcode project from `project.yml`, then
`xcodebuild -project CableTester.xcodeproj -scheme CableTester -configuration Debug -derivedDataPath build/dd build`
builds the app. `cd CableKit && swift test` runs the logic tests, with real IORegistry readings as fixtures.
The app has headless modes that never open a window: `--probe` prints what every USB-C port shows,
`--snapshot <dir>` renders every screen from demo data, and `--demo <state>` runs on demo data.
`scripts/release.sh` builds, signs, notarizes and publishes a release and its update feed.
The spec is [docs/app-spec-and-plan.md](docs/app-spec-and-plan.md), the chip findings are
[docs/emarker.md](docs/emarker.md), and the demo film is a [HyperFrames](video/README.md) project.
The original command-line prototype, `cable_tester.py`, still works.
