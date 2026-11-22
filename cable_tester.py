#!/usr/bin/env python3
"""USB-C cable tester for an Apple Silicon MacBook.

Power: reads the charger's offer list (USB-PD source capabilities) that macOS
stores in AdapterDetails. The charger only offers 5 A or 28 V when the cable's
e-marker allows it, so the offer list rates the cable. No load is needed.

Data: plug the same cable between the MacBook and a Thunderbolt Mac (back port)
and read the negotiated link speed from system_profiler.

Usage:
  cable_tester.py          interactive: test cables one by one, log to cables.csv
  cable_tester.py --read   print the current power offer and Thunderbolt state once
"""
import csv
import datetime as dt
import json
import os
import plistlib
import re
import select
import subprocess
import sys
import time

LOG = os.environ.get("CABLE_LOG", os.path.expanduser(
    "~/Documents/Claude/zz-Misc/cable-tester/cables.csv"))
FIELDS = ["id", "date", "power", "data", "max_volts", "max_amps_at_20v",
          "watts", "link_speed", "notes"]


# ---------- power ----------

def adapter():
    """Return (external_connected, AdapterDetails dict or None)."""
    out = subprocess.run(["ioreg", "-rn", "AppleSmartBattery", "-a"],
                         capture_output=True).stdout
    try:
        data = plistlib.loads(out)[0]
    except Exception:
        return False, None
    return bool(data.get("ExternalConnected")), data.get("AdapterDetails")


def offers(details):
    """Valid (mV, mA) offers, dropping 65535 placeholders and zeros."""
    res = []
    for o in (details or {}).get("UsbHvcMenu", []) or []:
        v, a = o.get("MaxVoltage", 0), o.get("MaxCurrent", 0)
        if 0 < v < 65535 and 0 < a < 65535:
            res.append((v, a))
    return res


def classify_power(details):
    offs = offers(details)
    watts = (details or {}).get("Watts", 0)
    max_v = max((v for v, _ in offs), default=0)
    amps20 = max((a for v, a in offs if v == 20000), default=0)
    if max_v > 20000 or watts > 100:
        label = "240W"
    elif amps20 >= 5000:
        label = "100W"
    elif amps20 >= 3000:
        label = "60W"
    elif offs:
        label = f"<=60W? (max {max_v/1000:g}V)"
    else:
        label = "unknown"
    return label, max_v, amps20, watts


def wait_power_unplugged():
    ext, _ = adapter()
    if ext:
        print("  Unplug power from the MacBook (USB-C and MagSafe)...", flush=True)
        while adapter()[0]:
            time.sleep(0.5)


def wait_power_reading():
    """Wait for a charger, then for the offer list to stay the same for 4 s
    (the 28 V offer can arrive a moment after the first contract)."""
    while not adapter()[0]:
        time.sleep(0.5)
    print("  Charger detected, reading offers...", flush=True)
    last, stable_since, start = None, time.time(), time.time()
    while True:
        _, d = adapter()
        key = (tuple(offers(d)), (d or {}).get("Watts"))
        if key != last:
            last, stable_since = key, time.time()
        if time.time() - stable_since >= 4 or time.time() - start > 20:
            return d
        time.sleep(0.5)


# ---------- data ----------

def tb_links():
    """Gb/s numbers for every connected Thunderbolt/USB4 receptacle."""
    out = subprocess.run(["system_profiler", "SPThunderboltDataType", "-json"],
                         capture_output=True, text=True).stdout
    try:
        buses = json.loads(out).get("SPThunderboltDataType", [])
    except Exception:
        return []
    speeds = []

    def walk(node):
        if isinstance(node, dict):
            for k, v in node.items():
                if k.startswith("receptacle") and isinstance(v, dict):
                    status = v.get("receptacle_status_key", "")
                    if "no_devices" not in status:
                        m = re.search(r"([\d.]+)\s*Gb/s", v.get("current_speed_key", ""))
                        if m:
                            speeds.append(float(m.group(1)))
                walk(v)
        elif isinstance(node, list):
            for x in node:
                walk(x)

    walk(buses)
    return speeds


def port_transports():
    """Union of active transports on connected USB-C ports, e.g. {"CC", "USB2"}.
    CIO means a Thunderbolt/USB4 link; only USB2 means a USB 2 cable."""
    out = subprocess.run(["ioreg", "-l", "-w0"], capture_output=True).stdout.decode("utf-8", "replace")
    active = set()
    for m in re.finditer(r'"TransportsActive" = \(([^)]*)\)', out):
        items = {x.strip().strip('"') for x in m.group(1).split(",") if x.strip()}
        if "CC" in items:
            active |= items
    return active


def enter_pressed(timeout):
    r, _, _ = select.select([sys.stdin], [], [], timeout)
    if r:
        sys.stdin.readline()
        return True
    return False


def data_test():
    print("  Now plug the SAME cable: MacBook <-> Mac mini (a BACK port).")
    print("  Waiting up to 25 s for a link. Press Enter to skip the data test.", flush=True)
    start, seen_at = time.time(), None
    while time.time() - start < 25:
        tr = port_transports()
        if "CIO" in tr:
            for _ in range(10):  # Thunderbolt link up, wait for its speed
                speeds = tb_links()
                if speeds:
                    gb = min(speeds)
                    return ("TB" if gb >= 40 else f"{gb:g}G"), f"{gb:g} Gb/s"
                time.sleep(1)
            return "TB", "Thunderbolt link, speed not reported"
        if tr & {"USB2", "USB3"}:
            seen_at = seen_at or time.time()
            if time.time() - seen_at >= 8:  # gave Thunderbolt time to come up
                if "USB3" in tr:
                    return "USB3", "USB 3 link, no Thunderbolt"
                return "USB2", "USB 2 link only"
        if enter_pressed(1.5):
            return "", "skipped"
    return "?", "no link detected (cable faulty, Mini asleep, or front port)"


# ---------- log ----------

def next_id():
    if not os.path.exists(LOG):
        return 1
    with open(LOG, newline="") as f:
        ids = [int(r["id"]) for r in csv.DictReader(f) if r.get("id", "").isdigit()]
    return max(ids, default=0) + 1


def append(row):
    os.makedirs(os.path.dirname(LOG), exist_ok=True)
    new = not os.path.exists(LOG)
    with open(LOG, "a", newline="") as f:
        w = csv.DictWriter(f, fieldnames=FIELDS)
        if new:
            w.writeheader()
        w.writerow(row)


# ---------- main ----------

def read_once():
    ext, d = adapter()
    if ext and d:
        label, max_v, a20, watts = classify_power(d)
        print(f"Power: {label}  (charger takes {watts} W, max {max_v/1000:g} V, "
              f"{a20/1000:g} A at 20 V)")
        print("Offers:", ", ".join(f"{v/1000:g}V {a/1000:g}A" for v, a in offers(d)))
    else:
        print("Power: no charger connected")
    speeds = tb_links()
    print("Thunderbolt links:", ", ".join(f"{s:g} Gb/s" for s in speeds) or "none")
    print("Active on USB-C ports:", ", ".join(sorted(port_transports())) or "nothing")


def main():
    if "--read" in sys.argv:
        read_once()
        return
    print("Cable tester. Log:", LOG)
    print("Use the 140 W charger on a USB-C port. Ctrl+C to quit.\n")
    while True:
        cid = next_id()
        print(f"Cable #{cid:02d}")
        wait_power_unplugged()
        print("  Plug the cable: charger -> MacBook USB-C.", flush=True)
        label, max_v, a20, watts = classify_power(wait_power_reading())
        print(f"  Power: {label}  (charger offers max {max_v/1000:g} V, "
              f"{a20/1000:g} A at 20 V; Mac takes {watts} W)")
        data, link = data_test()
        print(f"  Data: {data or '-'}  ({link})")
        notes = input("  Notes (colour, length, brand), Enter for none: ").strip()
        tag = " ".join(x for x in [f"#{cid:02d}", label, data] if x)
        append({"id": cid, "date": dt.date.today().isoformat(), "power": label,
                "data": data, "max_volts": max_v / 1000, "max_amps_at_20v": a20 / 1000,
                "watts": watts, "link_speed": link, "notes": notes})
        print(f"\n  LABEL:  {tag}\n")


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\nDone.")
