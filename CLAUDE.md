# cable-tester

USB-C cable labeller. See README.md for how it works and the tested setup.

## Facts that are easy to get wrong
- Must RUN on the MacBook Pro (M5 Pro). Power readings come from `AdapterDetails` in
  `ioreg -rn AppleSmartBattery`, which only exists on a Mac with a battery. The Mac mini (M6,
  Thunderbolt 4) is only the far end for the data test, but code can be edited anywhere.
- Power label comes from the charger's offer list (`UsbHvcMenu`), not from live draw: no load needed.
  Reading is the lower of charger and cable, so test with the Apple 140 W charger on USB-C, not MagSafe.
- Data label comes from `TransportsActive` in `ioreg -l` (`CIO` = Thunderbolt/USB4, `USB2` alone =
  USB 2 cable), speed from `system_profiler SPThunderboltDataType -json`.
- `ioreg -l` output is not valid UTF-8: decode with errors="replace".
- The cable e-marker (watts, speed, EPR, length, vendor) IS readable from the `SOP'` node in
  ioreg, see docs/emarker.md. Still no serial, so it identifies a model, not one cable.
- macOS exposes no cable ID or serial, so cables are tracked by number labels plus the CSV log
  (`~/Documents/Claude/zz-Misc/cable-tester/cables.csv`, outside the repo).

## Status (2026-11-22)
- Tested: 100 W path, USB 2 detection. Untested: 240 W path (140 W charger), a Thunderbolt cable.
- Next: turn the CLI into a small, good-looking Mac app (Max's request). Labelling the pile waits
  for coloured cable ties, so colour may become part of the label scheme.
