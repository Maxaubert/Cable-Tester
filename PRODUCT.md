# Product

<!-- impeccable:product-schema 1 -->

## Platform

macos (native SwiftUI app; mockups are HTML/images). Not one of impeccable's web/ios/android values:
follow macOS Human Interface Guidelines and native controls.

## Stack

Swift + SwiftUI, small single window (Max, 2026-11-22). Reads IOKit / IORegistry directly and reacts
to plug events instead of polling. Signed with the existing Developer ID.

## Users

Max first: at a desk with a MacBook Pro, the Apple 140 W charger and a Mac mini, working through a
drawer of USB-C cables one at a time. Plug a cable in, read its rating within seconds, label it, move on.
May go public later, so it must make sense to someone with no setup knowledge.

## Product Purpose

Tell you what a USB-C cable can do (wattage and data speed) the moment you plug it in, without a
hardware tester. Success: one plug, answer in a few seconds, nothing to read or configure.

## Positioning

Uses what the Mac already sees: the cable's own e-marker (watts, speed, EPR, length, vendor from the
`SOP'` node, see docs/emarker.md), plus the charger's offer list and the live link. No extra hardware.

## Operating Context

- Cable plugged charger -> MacBook: only wattage is meaningful; no data link, so data speed is hidden.
- Cable plugged MacBook -> Mac: data speed shows; wattage from the far end is limited by that Mac, so
  the cable's own e-marker rating is the trustworthy watt figure.
- Cables without an e-marker report nothing about themselves: treat as 3 A / 60 W, use the live link.
- Results never exceed the weakest part (charger, Mac, port).

## Capabilities and Constraints

- Shows wattage always, data speed only when there is a data link.
- History list of tested cables (number, label, colour tie, notes), replacing the CSV log.
- "Seen this model" match from e-marker VID/PID/VDOs. No serial number exists, so identical cables
  cannot be told apart; matching is per model.
- Detail view with the raw facts (volts, amps, link speed, length, vendor).
- Copy or print a short label like `#07 240W TB`.
- Must run on a Mac with a battery for charger readings (AdapterDetails).

## Brand Commitments

Max, 2026-11-22: "extraordinarily sleek, Apple-like, intuitive, easy, non-bloated". Native macOS look.

## Evidence on Hand

Real readings: 240 W USB 2 no-name cable (Cable VDO 0x000A4E40), USB 2 cable to Mac mini
(`CC, USB2`), 100 W path tested. No Thunderbolt cable or 240 W charger path tested yet.

## Product Principles

1. One plug, one answer: the result appears without any click.
2. Show only what is true for this connection; hide what cannot be known.
3. Say why a number is limited (charger, Mac, no e-marker) in plain words.
4. Fast enough to run a whole drawer in one sitting.
