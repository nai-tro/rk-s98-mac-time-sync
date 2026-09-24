#!/usr/bin/env python3
"""
Royal Kludge RK-S98 Time Sync Tool for macOS (Python Implementation)
Synchronizes TFT display clock via 2.4GHz USB Dongle or USB Cable.
"""

import sys
import os
import time
import datetime
import argparse

try:
    import hid
except ImportError:
    print("Error: 'hidapi' not installed. Install with: pip3 install hidapi", flush=True)
    sys.exit(1)

TARGET_VIDS = [0x258A, 0x0C45, 0x3938]
DONGLE_PIDS = [0x0150, 0x01FF, 0x00C5]
WIRED_PIDS = [0x01AF, 0x0174, 0x01BF, 0x0223, 0x0224, 0x022B, 0x022F, 0x0230, 0x023F, 0x0240, 0x0241]

def build_time_payload(dt=None):
    if dt is None:
        dt = datetime.datetime.now()
    payload = bytearray(11)
    payload[0] = 0x00
    payload[1] = 0x00
    payload[2] = 0x00
    payload[3] = dt.year & 0xFF
    payload[4] = (dt.year >> 8) & 0xFF
    payload[5] = dt.month
    payload[6] = dt.day
    payload[7] = dt.hour
    payload[8] = dt.minute
    payload[9] = dt.second
    # Windows SYSTEMTIME DayOfWeek: Sunday=0, Monday=1, ..., Saturday=6
    payload[10] = (dt.weekday() + 1) % 7
    return payload

def build_520_wired_packet(dt=None):
    """520-byte Feature Report for Wired USB connection (Report ID 0)."""
    payload = build_time_payload(dt)
    buf = bytearray(520)
    buf[0] = 0x00       # Report ID
    buf[1] = 0x0B       # Length / Subcmd (11)
    buf[2] = 0x00
    buf[3] = 0x00
    buf[4] = 0x01       # Package count = 1
    buf[5] = 0x00       # Package index = 0
    buf[6] = 0x0B       # Chunk length low = 11
    buf[7] = 0x00       # Chunk length high = 0
    buf[8:19] = payload
    return buf

def build_1032_dongle_packet(dt=None):
    """1032-byte Feature Report for 2.4G Dongle (Report ID 6)."""
    payload = build_time_payload(dt)
    buf = bytearray(1032)
    buf[0] = 6          # Report ID 6
    buf[1] = 0x0B       # Subcmd (11)
    buf[2] = 0x00
    buf[3] = 0x00
    buf[4] = 0x01       # Package count = 1
    buf[5] = 0x00       # Package index = 0
    buf[6] = 0x0B       # Chunk length low = 11
    buf[7] = 0x00       # Chunk length high = 0
    buf[8:19] = payload
    return buf

def build_19_dongle_report(dt=None):
    """20-byte Output Report for 2.4G Dongle (Report ID 19 + 19 bytes with CRC)."""
    payload = build_time_payload(dt)
    rpt = bytearray(19)
    rpt[0] = 0x0B       # cmdId (11)
    rpt[1] = 1          # packageNum = 1
    rpt[2] = 0          # packageIndex = 0
    rpt[3] = 11         # dataLength = 11
    rpt[4:15] = payload # 11 bytes of payload
    # CRC calculation: initial sum = 19, sum first 18 bytes
    crc = 19
    for b in rpt[:18]:
        crc += b
    rpt[18] = crc & 0xFF
    return bytes([19]) + bytes(rpt)

def check_dongle_link(h):
    """Queries dongle to see if keyboard is wirelessly linked."""
    rpt = bytearray(19)
    rpt[0] = 7  # GetDongleStatus
    rpt[1] = 1
    rpt[2] = 0
    rpt[3] = 0
    crc = 19
    for b in rpt[:18]: crc += b
    rpt[18] = crc & 0xFF

    try:
        h.write(bytes([19]) + bytes(rpt))
        data = h.read(64, timeout_ms=300)
        if data and len(data) >= 6:
            # data[5] > 0 means linked
            return bool(data[5]), data
    except Exception:
        pass
    return False, None

def find_s98_devices():
    """Finds all unique vendor HID interfaces on USB (Dongle or Cable)."""
    seen_paths = set()
    candidates = []
    for d in hid.enumerate():
        path = d.get("path")
        if path in seen_paths:
            continue

        vid = d.get("vendor_id") or 0
        pid = d.get("product_id") or 0
        prod = (d.get("product_string") or "").lower()
        mfr = (d.get("manufacturer_string") or "").lower()
        up = d.get("usage_page") or 0
        u = d.get("usage") or 0
        bus = d.get("bus_type")  # 1 = USB, 2 = Bluetooth

        if bus == 2:
            continue

        is_dongle = (vid == 0x258A and pid in DONGLE_PIDS and up in [0xFF02, 0xFF00])
        is_wired = (vid in TARGET_VIDS and (pid in WIRED_PIDS or "s98" in prod) and up in [0xFF00, 0xFF01])
        is_generic_vendor = (vid == 0x258A and (up >= 0xFF00 or u in [1, 2]))

        if is_dongle or is_wired or is_generic_vendor:
            seen_paths.add(path)
            candidates.append(d)

    return candidates

def sync_time():
    """Synchronizes time to connected RK-S98 device."""
    candidates = find_s98_devices()
    if not candidates:
        return False, "No RK-S98 2.4GHz Dongle or USB cable detected. Please plug the dongle or cable in."

    now = datetime.datetime.now()
    pkt_wired = build_520_wired_packet(now)
    pkt_dongle_feat = build_1032_dongle_packet(now)
    pkt_dongle_out = build_19_dongle_report(now)
    synced_any = False
    details = []

    for dev_info in candidates:
        path = dev_info["path"]
        vid = dev_info.get("vendor_id")
        pid = dev_info.get("product_id")
        prod = dev_info.get("product_string") or "RK Device"

        h = None
        try:
            h = hid.device()
            h.open_path(path)
        except Exception as e:
            details.append(f"Cannot open {prod}: {e}")
            continue

        try:
            if pid in DONGLE_PIDS:
                linked, _ = check_dongle_link(h)
                if not linked:
                    details.append(
                        f"2.4G Dongle detected (PID:0x{pid:04X}), but keyboard is not linked yet. "
                        f"Flip keyboard switch to '2.4G' and press any key to wake."
                    )
                else:
                    res_f = h.send_feature_report(pkt_dongle_feat)
                    res_o = h.write(pkt_dongle_out)
                    if res_f > 0 or res_o > 0:
                        synced_any = True
                        details.append(f"Synced via 2.4G Dongle ({now.strftime('%H:%M:%S')})")
                    else:
                        details.append(f"Dongle write failed: {h.error()}")
            else:
                res = h.send_feature_report(pkt_wired)
                if res > 0:
                    synced_any = True
                    details.append(f"Synced via USB Cable ({now.strftime('%H:%M:%S')})")
                else:
                    details.append(f"Wired write failed: {h.error()}")
        except Exception as e:
            details.append(f"Error on {prod}: {e}")
        finally:
            if h is not None:
                try:
                    h.close()
                except Exception:
                    pass

    if synced_any:
        return True, "Success: " + "; ".join(details)
    else:
        return False, "Sync attempt: " + "; ".join(details)

def daemon_loop(poll_interval=10, sync_interval=600):
    print("[*] RK-S98 Time Sync Daemon started.", flush=True)
    print("[*] Monitoring 2.4GHz USB Dongle or USB Cable...", flush=True)
    last_sync_time = 0
    was_linked = False

    while True:
        now_ts = time.time()
        candidates = find_s98_devices()

        if candidates:
            if not was_linked or (now_ts - last_sync_time >= sync_interval):
                success, msg = sync_time()
                if success:
                    print(f"[+] {msg}", flush=True)
                    last_sync_time = now_ts
                    was_linked = True
                else:
                    print(f"[-] {msg}", flush=True)
                    was_linked = False
        else:
            if was_linked:
                print("[*] Keyboard / Dongle disconnected.", flush=True)
                was_linked = False

        time.sleep(poll_interval)

def main():
    parser = argparse.ArgumentParser(description="RK-S98 Time Sync Tool for macOS")
    parser.add_argument("--daemon", action="store_true", help="Run continuously in background")
    parser.add_argument("--interval", type=int, default=10, help="Polling interval in seconds")
    args = parser.parse_args()

    if args.daemon:
        daemon_loop(args.interval)
    else:
        success, msg = sync_time()
        if success:
            print(f"[SUCCESS] {msg}")
            sys.exit(0)
        else:
            print(f"[INFO] {msg}")
            sys.exit(1)

if __name__ == "__main__":
    main()
