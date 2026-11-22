# Reading the cable's e-marker on macOS

Found 2026-11-22 on the MacBook Pro (Mac18,5), cable plugged MacBook to Mac mini.

macOS exposes the cable's own e-marker (USB-PD Discover Identity on SOP') in the IORegistry:
node `SOP'` (class `IOPortTransportComponentCCUSBPDSOPp`) under `Port-USB-C@N/CC`, property
`Metadata` = `{"VDOs"=(id header, cert stat, product, cable VDO), "Product Type Description",
"Vendor ID", "Product ID", ...}`. Find it with `ioreg -l -w0 | grep -a -A8 "SOP'"`.

So the cable rates itself: no charger and no data link needed for the rating.

## Decoding the Cable VDO (4th VDO, little-endian bytes)

USB PD 3.1 Passive Cable VDO bits:

| Bits | Field | Values |
|---|---|---|
| 2:0 | highest USB speed | 000 USB 2.0, 001 USB 3.2 Gen1, 010 Gen2 / USB4 Gen2, 011 USB4 Gen3, 100 USB4 Gen4 |
| 6:5 | VBUS current | 01 3 A, 10 5 A |
| 10:9 | max VBUS voltage | 00 20 V, 11 50 V |
| 12:11 | termination | 00 VCONN not required, 01 VCONN required |
| 16:13 | latency (rough length) | 0001 <10 ns (~1 m), 0010 10-20 ns (~2 m), ... |
| 17 | EPR capable | 1 = 240 W |
| 19:18 | plug | 10 Type-C |

Example seen: VDOs `00000018, 00000000, 00000000, 404e0a00` -> Cable VDO `0x000A4E40`:
passive, USB 2.0 only, 5 A, 50 V, EPR = a 240 W charge-only cable, ~2 m, Vendor ID 0 (no-name).

## Limits
- No serial number: VID, PID and the VDOs identify a cable *model*, not one cable. Two identical
  cables look the same, so "remembering" cables can only work per model (plus a physical label).
- Cables without an e-marker (most 60 W USB 2 cables) have no `SOP'` data: treat them as 3 A / 60 W
  and use the live link test for data.
- Far end plugged into nothing (tested 2026-11-22, 240 W no-name cable in MacBook port 1): the port
  shows `ConnectionActive = Yes` and `TransportsActive = ("CC")`, but no `SOP` partner and no `SOP'`
  node. So the Mac notices a cable was plugged in, but cannot read its chip. The app can say
  "Cable detected, plug the other end into a charger or a Mac".
- Small USB device at the far end works (tested 2026-11-22): same 240 W cable, MacBook port 1 to a
  SteelSeries Arctis GameBuds (USB 2 full speed, 12 Mb/s). `SOP'` was read with the full cable VDO.
  So any small powered device lets the Mac read the chip. The live link then shows the device's
  speed (12 Mb/s here), not the cable's: the app must say "limited by the device".
- Untested: whether `SOP'` appears when the far end is a charger (the charger, not the Mac, may run
  the cable discovery). Confirmed with the Mac mini as the far end.
