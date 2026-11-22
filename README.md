<div align="center">

# cable-tester

Label a drawer full of USB-C cables by **wattage** and **data speed**, using a MacBook instead of a hardware tester.

![macOS](https://img.shields.io/badge/macOS-Apple%20Silicon-2f6fde?logo=apple&logoColor=white)
![Python](https://img.shields.io/badge/python-3-2f6fde?logo=python&logoColor=white)
![No dependencies](https://img.shields.io/badge/dependencies-none-2f6fde)

</div>

## What it tells you

| Label | Meaning |
|---|---|
| `60W` | 3 A cable (no e-marker or a 3 A one) |
| `100W` | 5 A cable, 20 V max |
| `240W` | EPR cable (28 V and up) |
| `TB` | Thunderbolt/USB4 link at 40 Gb/s or more |
| `20G`, `10G` | USB4 link at a lower speed |
| `USB3` | USB 3 link but no Thunderbolt |
| `USB2` | Only a USB 2 link: the cable has no high-speed wires |
| `?` | No link at all (faulty cable, Mini asleep, or front port) |

Each cable gets a number and a line in a CSV log, so a label like `#07 240W TB` can be looked up later.

## How it works

**Power, no load needed.** When a cable is plugged in, the charger reads the cable's e-marker and then
sends the Mac a list of what it will supply. It only offers 5 A when the cable allows 5 A, and only offers
28 V (EPR) when the cable is a 240 W cable. macOS stores that list in `AdapterDetails`
(`ioreg -rn AppleSmartBattery`), and the script rates the cable from it. What the Mac actually draws
does not matter.

**Data.** The same cable is then plugged between the MacBook and another Thunderbolt Mac. The
script reads which links are active on the port (`TransportsActive` in `ioreg`: `CIO` is
Thunderbolt/USB4, `USB2` alone means a USB 2 cable) and the Thunderbolt speed from
`system_profiler SPThunderboltDataType`. Tested 2026-11-22: a USB 2 charging cable to the Mac mini
showed `CC, USB2` only.

> [!IMPORTANT]
> The result can never be higher than the weakest part. A 100 W charger makes a 240 W cable read
> `100W`; a Thunderbolt 4 Mac makes a TB5 cable read `TB` (40 Gb/s).

## Setup used

- MacBook Pro M5 Pro (140 W USB-C charging, Thunderbolt 5)
- Apple 140 W USB-C charger (EPR), plugged into a **USB-C port, not MagSafe**
- Mac mini M6 (Thunderbolt 4, 40 Gb/s). Use a **back** port: the front USB-C ports are USB 3 only
  (10 Gb/s). Source: [Apple Mac mini specs](https://www.apple.com/mac-mini/specs/), checked 2026-11-22.

macOS does not expose any cable ID or serial number (only `ActiveCable` and `OpticalCable` flags),
so cables cannot be recognised automatically. Physical labels plus the log are the way to go.

## Usage

```sh
./cable_tester.py          # test cables one by one
./cable_tester.py --read   # show the current power offers and Thunderbolt links once
```

Per cable: unplug power, plug the cable charger to MacBook, wait for the power reading, move the
cable to MacBook to Mac mini (or press Enter to skip), add an optional note, write the label on the cable.

The log goes to `~/Documents/Claude/zz-Misc/cable-tester/cables.csv`. Override with `CABLE_LOG=/path/file.csv`.
