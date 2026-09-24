import Foundation
import IOKit
import IOKit.hid

/// Builds the 11-byte timestamp payload expected by the keyboard's MCU.
func getLocalTimePayload() -> [UInt8] {
    let now = Date()
    let calendar = Calendar.current
    let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second, .weekday], from: now)

    let year = UInt16(components.year ?? 2026)
    let month = UInt8(components.month ?? 1)
    let day = UInt8(components.day ?? 1)
    let hour = UInt8(components.hour ?? 0)
    let minute = UInt8(components.minute ?? 0)
    let second = UInt8(components.second ?? 0)
    // Calendar weekday: 1 = Sunday, 2 = Monday, ..., 7 = Saturday
    // Windows SYSTEMTIME: 0 = Sunday, 1 = Monday, ..., 6 = Saturday
    let weekday = UInt8((components.weekday ?? 1) - 1)

    var p = [UInt8](repeating: 0, count: 11)
    p[0] = 0
    p[1] = 0
    p[2] = 0
    p[3] = UInt8(year & 0xFF)
    p[4] = UInt8((year >> 8) & 0xFF)
    p[5] = month
    p[6] = day
    p[7] = hour
    p[8] = minute
    p[9] = second
    p[10] = weekday
    return p
}

/// Discovers connected RK / SinoWealth keyboards and transmits the synchronization packet.
func syncKeyboard() -> Bool {
    let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    let matchDicts: [[String: Any]] = [
        [kIOHIDVendorIDKey: 0x258A],
        [kIOHIDVendorIDKey: 0x0C45],
        [kIOHIDVendorIDKey: 0x3938]
    ]
    IOHIDManagerSetDeviceMatchingMultiple(manager, matchDicts as CFArray)
    IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))

    guard let deviceSet = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>, !deviceSet.isEmpty else {
        print("[-] No SinoWealth / RK keyboard or dongle detected.")
        fflush(stdout)
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        return false
    }

    let payload = getLocalTimePayload()
    let nowStr = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .medium)
    var success = false

    for dev in deviceSet {
        let ret = IOHIDDeviceOpen(dev, IOOptionBits(kIOHIDOptionsTypeNone))
        if ret != kIOReturnSuccess {
            continue
        }

        let pidVal = IOHIDDeviceGetProperty(dev, kIOHIDProductIDKey as CFString) as? Int ?? 0
        let maxFeat = IOHIDDeviceGetProperty(dev, kIOHIDMaxFeatureReportSizeKey as CFString) as? Int ?? 0
        let maxOut = IOHIDDeviceGetProperty(dev, kIOHIDMaxOutputReportSizeKey as CFString) as? Int ?? 0

        // Case 1: 2.4GHz Dongle (PID 0x0150 / MaxFeatureReportSize >= 1031)
        if maxFeat >= 1031 || maxOut >= 19 {
            // Feature Report 6 (1031 bytes data, padded with 0s)
            var feat = [UInt8](repeating: 0, count: 1031)
            feat[0] = 0x0B
            feat[1] = 0x00
            feat[2] = 0x00
            feat[3] = 0x01 // Package count = 1
            feat[4] = 0x00 // Package index = 0
            feat[5] = 0x0B // Chunk length low = 11
            feat[6] = 0x00 // Chunk length high = 0
            for i in 0..<11 { feat[7 + i] = payload[i] }

            let r1 = IOHIDDeviceSetReport(dev, kIOHIDReportTypeFeature, 6, feat, feat.count)

            // Output Report 19 (19 bytes data with CRC checksum)
            var outRpt = [UInt8](repeating: 0, count: 19)
            outRpt[0] = 0x0B
            outRpt[1] = 1
            outRpt[2] = 0
            outRpt[3] = 11
            for i in 0..<11 { outRpt[4 + i] = payload[i] }
            var crc: UInt32 = 19
            for i in 0..<18 { crc += UInt32(outRpt[i]) }
            outRpt[18] = UInt8(crc & 0xFF)

            let r2 = IOHIDDeviceSetReport(dev, kIOHIDReportTypeOutput, 19, outRpt, outRpt.count)

            if r1 == kIOReturnSuccess || r2 == kIOReturnSuccess {
                print("[SUCCESS] Synced RK-S98 via 2.4G Dongle at \(nowStr)")
                fflush(stdout)
                success = true
            }
        }
        // Case 2: Wired USB Cable (PID 0x01AF / 0x0174 / MaxFeatureReportSize == 520)
        else if maxFeat >= 520 || pidVal == 0x01AF || pidVal == 0x0174 {
            var wired = [UInt8](repeating: 0, count: 520)
            wired[0] = 0x00
            wired[1] = 0x0B
            wired[2] = 0x00
            wired[3] = 0x00
            wired[4] = 0x01
            wired[5] = 0x00
            wired[6] = 0x0B
            wired[7] = 0x00
            for i in 0..<11 { wired[8 + i] = payload[i] }

            let rWired = IOHIDDeviceSetReport(dev, kIOHIDReportTypeFeature, 0, wired, wired.count)
            if rWired == kIOReturnSuccess {
                print("[SUCCESS] Synced RK-S98 via USB Cable at \(nowStr)")
                fflush(stdout)
                success = true
            }
        }

        IOHIDDeviceClose(dev, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    return success
}

let args = CommandLine.arguments
if args.contains("--daemon") {
    print("[*] RK-S98 Native Time Sync Daemon started.")
    print("[*] Monitoring for keyboard connection...")
    fflush(stdout)
    var wasSynced = false
    while true {
        let ok = syncKeyboard()
        if ok && !wasSynced {
            wasSynced = true
            sleep(600) // Sleep 10 minutes when synced
        } else if !ok {
            wasSynced = false
            sleep(10)
        } else {
            sleep(600)
        }
    }
} else {
    let ok = syncKeyboard()
    exit(ok ? 0 : 1)
}
