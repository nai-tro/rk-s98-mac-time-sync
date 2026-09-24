# Royal Kludge RK-S98 Time Sync for macOS ⌨️ 🕒

A lightweight, zero-dependency macOS utility and background daemon to synchronize the onboard TFT smart display clock on **Royal Kludge (RK) S98** mechanical keyboards without Windows.

Works over the **2.4GHz USB Dongle** and **USB-C Wired Connection**.

---

## The Problem

If you use an RK-S98 keyboard on macOS, you may notice that the date and time on the TFT screen drifts or resets:
1. **Bluetooth cannot sync:** Over Bluetooth Low Energy (BLE), the SinoWealth MCU disables the vendor configuration endpoint to save battery and comply with standard Bluetooth HOGP profiles (`MaxOutputReportSize: 2`, `MaxFeatureReportSize: 1`). The keyboard clock cannot be updated over Bluetooth on stock firmware (`DisableBT=1` in official RK software).
2. **The 2.4G Dongle doesn't sync on its own:** The 2.4GHz USB dongle is just an RF transceiver. The keyboard has no internal internet or RTC battery; it requires host software on your computer to push a time packet.
3. **The Official Web App (`drive.rkgaming.com`) fails:** Reverse-engineering the official RK WebHID bundle revealed that Royal Kludge only implemented `syncDeviceSystemTimeSerial()` for newer QiWang-based models (`RK-S85`, `RK-L75Pro`). For the **RK-S98** (`class RO` / `class CO`), the official web app developers **omitted time synchronization entirely**.

---

## How It Works

By reverse-engineering the official Windows driver (`DeviceDriver.exe` / `CDevG5KB`), the exact hardware packet structure was extracted:

### 1. Connection Protocols & Endpoints

| Connection Type | Vendor ID | Product ID | Target Interface / Usage | Protocol Transport |
| :--- | :--- | :--- | :--- | :--- |
| **2.4GHz USB Dongle** | `0x258A` | `0x0150` | UsagePage `0xFF02`, Usage `0x0002` | **Report ID 6** (1032-byte Feature Report) & **Report ID 19** (20-byte Output Report + CRC) |
| **Wired USB Cable** | `0x258A` | `0x01AF` / `0x0174` | UsagePage `0xFF00`, Usage `0x0001` | **Report ID 0** (520-byte Feature Report) |

### 2. Time Packet Structure (`CDevG5KB::SetScreenParam`)

```c
struct RkScreenTimePacket {
    uint8_t  report_id;    // 0x06 (Dongle) or 0x00 (Wired)
    uint8_t  command;      // 0x0B (Time / Screen Param)
    uint8_t  flags;        // 0x00
    uint8_t  reserved;     // 0x00
    uint8_t  packet_count; // 0x01 (Total blocks)
    uint8_t  packet_index; // 0x00 (Block index)
    uint16_t chunk_len;    // 0x000B (11 bytes payload, little-endian)
    
    // 11-byte Timestamp Payload:
    uint8_t  unk[3];       // 0x00, 0x00, 0x00
    uint16_t year;         // Little-endian (e.g. 2026 -> 0xEA, 0x07)
    uint8_t  month;        // 1 - 12
    uint8_t  day;          // 1 - 31
    uint8_t  hour;         // 0 - 23
    uint8_t  minute;       // 0 - 59
    uint8_t  second;       // 0 - 59
    uint8_t  weekday;      // 0 = Sunday, 1 = Monday, ..., 6 = Saturday
};
```

---

## Installation

### Prerequisites
* macOS 12 (Monterey), 13 (Ventura), 14 (Sonoma), or 15 (Sequoia).
* Xcode Command Line Tools installed (`xcode-select --install`).

### Quick Install (One Command)
Clone the repository and run the installer:

```bash
git clone https://github.com/nai-tro/rk-s98-mac-time-sync.git
cd rk-s98-mac-time-sync
./Scripts/install.sh
```

Or using `make`:
```bash
make install
```

This will:
1. Compile the native Swift binary `rksync` to `~/.local/bin/rksync`.
2. Create a one-click Desktop app: `~/Desktop/Sync Keyboard Time.app`.
3. Install and load the background `launchd` LaunchAgent daemon.

---

## Usage

### Option 1: One-Click Desktop App (Easiest)
A shortcut called **`Sync Keyboard Time.app`** will be on your **Desktop**:
1. Make sure your keyboard switch is set to **`2.4G`** (with the USB dongle plugged in) or connected via **USB cable**.
2. Double-click **`Sync Keyboard Time.app`**.
3. A macOS notification banner confirms the time is updated.

### Option 2: Terminal Command
Run anywhere in your terminal:
```bash
rksync
```

Output:
```text
[SUCCESS] Synced RK-S98 via 2.4G Dongle at 24/9/2026, 22:54:45
```

### Option 3: Automated Background Sync via Daemon
To allow the background service (`launchd`) to keep the clock synced automatically without manual clicks:
1. Open **System Settings** $\rightarrow$ **Privacy & Security** $\rightarrow$ **Input Monitoring**.
2. Click the **`+`** button (enter your password/Touch ID).
3. Press `Cmd + Shift + G`, paste:
   ```text
   ~/.local/bin/rksync
   ```
4. Click **Open** and toggle it **On**.

*(Note: macOS requires Input Monitoring permission for background daemons opening devices that advertise keyboard usages to protect against background keyloggers).*

---

## Routine for Everyday Bluetooth Users

Because Bluetooth Low Energy cannot receive clock calibration packets:
1. Use **Bluetooth (`BT`)** for everyday typing.
2. **Once every few weeks** (or if the keyboard battery dies):
   * Flip the physical switch to **`2.4G`** (with the dongle plugged in) or plug in the USB cable.
   * Double-click **`Sync Keyboard Time.app`** on your Desktop.
   * The clock calibrates in **0.07 seconds**.
   * Flip back to **`BT`**.

---

## Troubleshooting

* **`[-] No SinoWealth / RK keyboard or dongle detected`**:
  * Verify that the 2.4GHz USB Dongle or USB-C cable is firmly plugged into your Mac or USB hub.
* **`[-] 2.4G Dongle detected, but keyboard is not linked yet`**:
  * Check the physical toggle switch on the back of the keyboard. It must be set to **`2.4G`** (not `BT` or `OFF`).
  * Tap any key to wake the keyboard from sleep.
* **Checking Daemon Logs**:
  ```bash
  cat /tmp/rk_s98_sync.log
  ```

---

## License

MIT License. See [LICENSE](LICENSE) for details.
