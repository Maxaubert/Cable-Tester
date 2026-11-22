import CableKit
import Foundation
import IOKit
import Observation

/// Watches the Mac's USB-C ports and the charger, and publishes the cable that was plugged in last.
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
        guard let n = focusedPort, let p = ports.first(where: { $0.number == n }) else { return nil }
        return CableResult.make(port: p, charger: charger)
    }

    var focusedPortState: PortState? { ports.first { $0.number == focusedPort } }

    private var notifyPort: IONotificationPortRef?
    private var iterators: [io_iterator_t] = []
    private var timer: Timer?
    private var knownConnections: [Int: String] = [:]
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
        charger = IORegistryReader.charger()
        // A port whose connection changed is where the user just plugged a cable.
        for p in new {
            let key = p.connectionActive ? (p.connectionUUID ?? "on") : ""
            let old = knownConnections[p.number]
            if !initial, key != old, p.connectionActive {
                focusedPort = p.number; pluggedAt = Date()
            }
            knownConnections[p.number] = key
        }
        if initial {
            // On launch, show a port that has a cable chip; permanent hubs and displays stay out of the way.
            if let p = new.first(where: { $0.connectionActive && $0.cable != nil }) {
                focusedPort = p.number; pluggedAt = Date()
            }
        }
        if let f = focusedPort, !(new.first { $0.number == f }?.connectionActive ?? false) {
            focusedPort = nil; pluggedAt = nil
        }
        if new != ports { ports = new }
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
