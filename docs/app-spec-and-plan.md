# Cable Tester app: spec and build plan

Written 2026-11-22 from the mockup rounds with Max. Approved mockups: `.impeccable/mocks/`. All rounds (36 images, gallery.html) are archived in
`~/Documents/Claude/zz-Misc/cable-tester/mockups/`. Product facts: `PRODUCT.md`. E-marker decoding: `docs/emarker.md`.

## Spec

### What it is
A small native macOS app (Swift 6, SwiftUI, macOS 26+, Apple Silicon). Plug a USB-C cable into the
MacBook and the window shows the cable's power rating and, when the other end is a Mac, its data speed.
No clicks needed to get a result. Dark, Apple-like, two panes: result on the left, inspector on the right.

### Screens (approved mockups)
| State | Mockup | What shows |
|---|---|---|
| Nothing plugged in | `round2-n2-empty-illustration` | Plug illustration, "Plug in a cable", recent cables list on the right |
| Cable to a Mac, chip read | `r5-main` | Big watts, "USB 4 · 40 Gb/s" with the Thunderbolt icon, chips, Save + copy icon, inspector (e-marker + live connection) |
| Cable to a charger | `r3-c1-charger` | Big watts, no data line (only "Plug it into another Mac to see data speed."), inspector (e-marker + charger, Max row shows watts: "28 V × 5 A · 140 W") |
| No chip in the cable | `round2-x1-no-chip-inspector` | "60 W est.", live data speed, amber note on the 3 A limit, inspector says "Not present" |
| Save | `r7-sheet` | Always a sheet (see below) |
| History | `r7-table` | Table, see below |

Rules for the result:
- Wattage always shows. Data speed shows only when there is a data link; on a charger it is simply absent.
- Watts come from the e-marker when present; otherwise from the charger's offers; with no chip and no
  charger, "60 W est." (no chip means 3 A max).
- Say why a number is limited, in plain words ("Mac mini limits to 40 Gb/s").
- Data type text is the USB name, never "TB" or "Thunderbolt": `USB 2`, `USB 3`, `USB 4`, `USB 4 v2`.
  Only Thunderbolt-capable links get an icon (the Thunderbolt glyph, blue); plain USB 4, USB 3 and
  USB 2 have no icon (Max, 2026-11-22).
- "Seen this model": when VID + PID + cable VDO match an earlier cable, a quiet line "Same model as #03".
  There is no serial number, so this is per model only.

### Save sheet (every save)
- Opens on every Save, even when only one thing is missing.
- Everything is editable (no locks, Max 2026-11-22), prefilled with everything already known (from
  the chip, charger or link): power, data, speed, tie colour, length, vendor. Rows still missing a value are gently highlighted. No Skip buttons: Save saves
  whatever is filled in and leaves empty fields blank (Max, 2026-11-22).
- Length is typed, in metres, with validation: accepts `0.13`, `2`, `1,5` (comma ok), range 0.01 to 10 m.
  Invalid input shows a red hint ("Enter a length in metres, like 0.13 or 2") and disables Save.
- No name field, no notes field.
- Number is assigned automatically (next free `#NN`).

### History
- Native sortable table: `#`, Tie, Power, Data, Speed, Vendor, Length, Tested. No notes, no name.
  Data is the USB name (with the Thunderbolt icon when it applies); Speed is its own column
  (`40 Gb/s`, `480 Mb/s`), sortable by real speed.
- Search field, filter `All | 240 W | 100 W | 60 W | Thunderbolt` (filter by the icon's meaning), "N cables" status bar.
- Every column except `#` and Tested is editable inline (no locks); empty cells show "Add".
  Power: pop-up 15/60/100/140/240 W or typed. Data: pop-up USB 2/3/4/4 v2 plus a Thunderbolt toggle.
  Speed: typed with validation (Mb/s or Gb/s). Edited values are marked as edited so the measured
  value can be restored.
  Length uses the same typed field and validation as the sheet. A validation message floats over the
  row below (popover style); it never makes the row taller.
- Toolbar: back to Now, copy label, print label, export (CSV). Delete via context menu.
- Imports the existing CSV log (`~/Documents/Claude/zz-Misc/cable-tester/cables.csv`) on first run.

### Label
`#07 240W USB4` (number, watts, USB name; no "TB"). Copy puts it on the clipboard; Print prints a small
label via the system print dialog.

## Architecture
- `CableKit` (Swift package, no UI, fully unit-tested): e-marker VDO decoding, power classification from
  charger offers, data classification from transports and link speed, label builder, length parser,
  model fingerprint.
- `PortMonitor`: IOKit notifications (not polling) on the `SOP'` node, `AppleSmartBattery`
  (`AdapterDetails`) and port `TransportsActive`; publishes one `Reading` value.
- Thunderbolt speed: find an IORegistry property for the link speed; fall back to
  `system_profiler SPThunderboltDataType -json` off the main thread.
- Store: JSON file in Application Support, CSV import and export.
- App: SwiftUI views per state above, `Table` for history, `.sheet` for save.
- Xcode project generated from a checked-in `project.yml` (XcodeGen), signed with the Developer ID
  (team WV7BY8CUM8).

## Testing (headless, never on screen)
- Unit tests for CableKit with fixtures recorded from real ioreg output (the 240 W USB 2 cable, the
  USB 2 link, charger offers).
- A demo mode (`--demo <state>`) that feeds recorded readings, so every screen renders without hardware.
- Screenshots of each state rendered offscreen (`ImageRenderer`), compared by eye against the mockups.
- Hardware check on the MacBook at the end: the real cables, charger and Mac mini.

## Decisions made while building (2026-11-22, from the code review)
- The charger reading has no port number, so it is only tied to a port when the charger and the cable
  were connected within 10 s of each other. Otherwise a chipless cable shows the 60 W estimate.
- A Thunderbolt (CIO) link wins over tunnelled USB links; when the port node gives no speed, the app
  asks `system_profiler SPThunderboltDataType` once per connection.
- Cable numbers are never reused, even after a delete (stored high-water mark).
- A saved-cables file that cannot be read is left untouched; the app runs in memory and says so.
- Power is typed (1 to 240 W) with a menu of common ratings. Edited values show a small dot whose
  tooltip gives the measured value; "Restore Measured Values" is in the row menu.

## Open questions to settle while building
- Whether `SOP'` (the chip) is readable when the far end is a charger. If not, the charger screen shows
  watts from the charger's offers and says so.
- Which IORegistry key carries the Thunderbolt link speed.
- How to tell a Thunderbolt cable from a plain USB 4 one: likely the Thunderbolt alt mode (Intel SVID
  0x8087) in the cable's SOP' identity; confirm on real cables.

## Build plan
1. Branch `app`, scaffold: `project.yml`, app target, `CableKit` package, test target, `.gitignore`.
2. CableKit: VDO decoder, power and data classifiers, label, length parser, fingerprint, with tests and
   recorded fixtures (port the Python logic from `cable_tester.py`).
3. PortMonitor: IOKit matching notifications, reading assembly, Thunderbolt speed lookup.
4. Store: model, JSON persistence, CSV import/export, next number, model match.
5. UI: window shell and inspector; empty, result, charger and no-chip states; save sheet with
   validation; history table with inline editing, filters, search; copy and print.
6. Demo mode and offscreen screenshots of every state; impeccable finish review against the mockups.
7. Hardware test on the MacBook; fix what it finds; update README (with screenshots) and CLAUDE.md.
8. Open the PR with the screenshots, then ask Max to merge.
Release and installer come afterwards through the `shipping` skill, not in this plan.

## Later ideas (not in v1, Max 2026-11-22: keep v1 USB-C only)
- **Ethernet:** negotiated link speed (2.5G / 1G / 100M) from the Mac's port. 100 Mb/s flags a cable
  with only two working pairs. No category or length.
- **HDMI:** best mode carried (e.g. 4K 120 Hz) as an estimate. HDMI cables are passive (no chip); the
  devices talk over DDC (EDID), HDCP, CEC and, on HDMI 2.1, SCDC (FRL link training and character
  error counters). On the Mac mini the HDMI port sits behind an internal DisplayPort-to-HDMI converter
  (`BranchDeviceID` "pHDMIg"): macOS exposes the TV's EDID and the DisplayPort side (`LinkRateDescription`
  "8.1 Gbps (HBR3)", 4 lanes), not the HDMI FRL rate or SCDC error counts (checked 2026-11-22).
- **USB-A to USB-C:** data only (USB 2 vs USB 3) via a USB-A host port and a USB-C device.
- **Real transfer test:** "Measure" button timing real data to the Mac mini over Thunderbolt.
