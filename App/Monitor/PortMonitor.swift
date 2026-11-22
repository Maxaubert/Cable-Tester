import CableKit
import Foundation
import IOKit
import Observation

/// Watches the Mac's USB-C ports and the charger, and publishes the cable the user plugs in to test.
/// Cables that were already connected when the app started are ignored until they are replugged.
/// Reacts to IOKit add/remove notifications, with a slow poll as a safety net (some changes, like a
/// link speed settling, publish no notification).
@MainActor @Observable
final class PortMonitor {
    private(set) var ports: [PortState] = []
    private(set) var charger: ChargerInfo?
    /// The port the user plugged into most recently (nil: show the empty state).
    private(set) var focusedPort: Int?
    private(set) var pluggedAt: Date?

    var result: CableResult? {
        guard let n = focusedPort, var p = ports.first(where: { $0.number == n }) else { return nil }
        // Fill in a Thunderbolt speed the port node does not report.
        if let i = p.links.firstIndex(where: { $0.kind == .cio && $0.speed == nil }), let s = cioSpeed[n] {
            p.links[i].speed = s
        }
        return CableResult.make(port: p, charger: chargerBelongs(to: n) ? charger : nil)
    }

    /// The charger reading is machine-wide (no port number), so only tie it to this port when the
    /// charger appeared at about the same time as this cable, or as the device on its other end
    /// (people plug the Mac end first, then the charger).
    private func chargerBelongs(to port: Int) -> Bool {
        guard charger != nil, let since = chargerSince else { return demo }
        return [plugTimes[port], partnerTimes[port]].compactMap { $0 }
            .contains { abs(since.timeIntervalSince($0)) < 10 }
    }

    var focusedPortState: PortState? { ports.first { $0.number == focusedPort } }

    /// Connected ports other than the one being tested (already plugged in at launch, hubs, displays).
    var otherConnectedCount: Int { ports.filter { $0.connectionActive && $0.number != focusedPort }.count }

    var isDemo: Bool { demo }

    private var notifyPort: IONotificationPortRef?
    private var iterators: [io_iterator_t] = []
    private var timer: Timer?
    private var knownConnections: [Int: String] = [:]
    private var plugTimes: [Int: Date] = [:]
    private var partnerTimes: [Int: Date] = [:]
    private var hadPartner: [Int: Bool] = [:]
    private var chargerSince: Date?
    private var cioSpeed: [Int: DataSpeed] = [:]
    private var cioLookups: Set<String> = []
    private var demo = false

    init() {}

    /// Fixed readings for demo mode and screenshots.
    init(demoPorts: [PortState], charger: ChargerInfo?, focused: Int?, pluggedAt: Date?) {
        demo = true
        ports = demoPorts; self.charger = charger; focusedPort = focused; self.pluggedAt = pluggedAt
    }

    func start() {
        guard !demo, notifyPort == nil else { return }
        refresh(initial: true)
        let port = IONotificationPortCreate(kIOMainPortDefault)
        notifyPort = port
        IONotificationPortSetDispatchQueue(port, .main)
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        let classes = ["IOPortTransportComponentCCUSBPDSOPp", "IOPortTransportComponentCCUSBPDSOP",
                       "IOPortTransportStateUSB2", "IOPortTransportStateUSB3", "IOPortTransportStateCIO",
                       "IOUSBHostDevice", "AppleSmartBattery"]
        for cls in classes {
            for type in [kIOFirstMatchNotification, kIOTerminatedNotification] {
                var it: io_iterator_t = 0
                let kr = IOServiceAddMatchingNotification(port, type, IOServiceMatching(cls), { ctx, it in
                    PortMonitor.drain(it)
                    guard let ctx else { return }
                    let me = Unmanaged<PortMonitor>.fromOpaque(ctx).takeUnretainedValue()
                    MainActor.assumeIsolated { me.scheduleRefresh() }
                }, ctx, &it)
                if kr == KERN_SUCCESS { PortMonitor.drain(it); iterators.append(it) }
            }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh(initial: false) }
        }
    }

    nonisolated private static func drain(_ it: io_iterator_t) {
        while case let o = IOIteratorNext(it), o != 0 { IOObjectRelease(o) }
    }

    private var pending = false
    private func scheduleRefresh() {
        guard !pending else { return }
        pending = true
        // Let the port finish publishing its children (chip, links) before reading.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            MainActor.assumeIsolated {
                self?.pending = false
                self?.refresh(initial: false)
            }
        }
    }

    func refresh(initial: Bool) {
        guard !demo else { return }
        let new = IORegistryReader.ports()
        let newCharger = IORegistryReader.charger()
        if newCharger == nil { chargerSince = nil } else if charger == nil || chargerSince == nil { chargerSince = Date() }
        if newCharger != charger { charger = newCharger }
        // A port whose connection changed is where the user just plugged a cable.
        for p in new {
            let key = p.connectionActive ? (p.connectionUUID ?? "on") : ""
            let old = knownConnections[p.number]
            if key != old {
                cioSpeed[p.number] = nil
                if p.connectionActive {
                    if !initial { focusedPort = p.number; pluggedAt = Date(); plugTimes[p.number] = pluggedAt }
                } else {
                    plugTimes[p.number] = nil
                }
            }
            knownConnections[p.number] = key
            // When the far end (charger or device) shows up.
            let partner = p.connectionActive && p.hasPartner
            if partner, !(hadPartner[p.number] ?? false), !initial { partnerTimes[p.number] = Date() }
            if !partner { partnerTimes[p.number] = nil }
            hadPartner[p.number] = partner
        }
        // Unplugging the cable under test goes back to "plug in a cable"; it never jumps to another one.
        if let f = focusedPort, !(new.first { $0.number == f }?.connectionActive ?? false) {
            focusedPort = nil; pluggedAt = nil
        }
        if new != ports { ports = new }
        lookUpThunderboltSpeedIfNeeded()
    }
}

extension PortMonitor {
    /// The port node may not report a Thunderbolt link's speed. Ask system_profiler once per connection,
    /// off the main thread.
    fileprivate func lookUpThunderboltSpeedIfNeeded() {
        guard let n = focusedPort, let p = ports.first(where: { $0.number == n }),
              p.links.contains(where: { $0.kind == .cio && $0.speed == nil }), cioSpeed[n] == nil else { return }
        let key = "\(n)-\(p.connectionUUID ?? "")"
        guard !cioLookups.contains(key) else { return }
        cioLookups.insert(key)
        Task.detached(priority: .utility) {
            let speed = ThunderboltProfiler.linkSpeed()
            await MainActor.run { [weak self] in
                if let speed { self?.cioSpeed[n] = speed }
            }
        }
    }
}

/// `system_profiler SPThunderboltDataType -json`: the slowest connected receptacle's current speed.
enum ThunderboltProfiler {
    static func linkSpeed() -> DataSpeed? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        task.arguments = ["SPThunderboltDataType", "-json"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do { try task.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return nil }
        var speeds: [DataSpeed] = []
        func walk(_ o: Any) {
            if let d = o as? [String: Any] {
                for (k, v) in d {
                    if k.hasPrefix("receptacle"), let r = v as? [String: Any],
                       !((r["receptacle_status_key"] as? String) ?? "").contains("no_devices"),
                       let s = (r["current_speed_key"] as? String).flatMap(DataSpeed.parse(description:)) {
                        speeds.append(s)
                    }
                    walk(v)
                }
            } else if let a = o as? [Any] { a.forEach(walk) }
        }
        walk(json)
        return speeds.min()
    }
}

/// Reads the USB-C port subtrees and the battery's adapter details from the IORegistry.
enum IORegistryReader {
    static func ports() -> [PortState] {
        var it: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOPort"), &it) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(it) }
        var result: [PortState] = []
        while case let s = IOIteratorNext(it), s != 0 {
            defer { IOObjectRelease(s) }
            let tree = node(s, depth: 0)
            guard (tree["PortTypeDescription"] as? String) == "USB-C", let p = PortState.parse(tree) else { continue }
            if !result.contains(where: { $0.number == p.number }) { result.append(p) }
        }
        return result.sorted { $0.number < $1.number }
    }

    /// Same shape as `ioreg -a -l`: properties plus IOObjectClass, IORegistryEntryName, IORegistryEntryChildren.
    static func node(_ entry: io_registry_entry_t, depth: Int) -> [String: Any] {
        var props: Unmanaged<CFMutableDictionary>?
        var dict: [String: Any] = [:]
        if IORegistryEntryCreateCFProperties(entry, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
           let d = props?.takeRetainedValue() as? [String: Any] { dict = d }
        if let cls = IOObjectCopyClass(entry)?.takeRetainedValue() { dict["IOObjectClass"] = cls as String }
        var name = [CChar](repeating: 0, count: 128)
        if IORegistryEntryGetName(entry, &name) == KERN_SUCCESS {
            dict["IORegistryEntryName"] = String(decoding: name.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        }
        guard depth < 3 else { return dict }
        var kids: io_iterator_t = 0
        var children: [[String: Any]] = []
        if IORegistryEntryGetChildIterator(entry, kIOServicePlane, &kids) == KERN_SUCCESS {
            while case let c = IOIteratorNext(kids), c != 0 {
                children.append(node(c, depth: depth + 1))
                IOObjectRelease(c)
            }
            IOObjectRelease(kids)
        }
        if !children.isEmpty { dict["IORegistryEntryChildren"] = children }
        return dict
    }

    /// The connected charger's offers. Only Macs with a battery have AdapterDetails.
    static func charger() -> ChargerInfo? {
        let s = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard s != 0 else { return nil }
        defer { IOObjectRelease(s) }
        func prop(_ k: String) -> Any? {
            IORegistryEntryCreateCFProperty(s, k as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
        }
        guard (prop("ExternalConnected") as? Bool) == true,
              let details = prop("AdapterDetails") as? [String: Any] else { return nil }
        return ChargerInfo(adapterDetails: details)
    }
}
