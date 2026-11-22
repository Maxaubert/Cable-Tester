import AppKit
import CableKit
import SwiftUI

/// Demo readings for every screen, built from real chip data where we have it.
enum Demo {
    enum State: String, CaseIterable {
        case empty, mac, charger, nochip, cableonly, device, history
    }

    static func le(_ v: UInt32) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }

    static func chip(vendor: Int, product: Int, vdo: UInt32) -> CableIdentity {
        CableIdentity.decode(vdos: [Data(count: 4), Data(count: 4), Data(count: 4), le(vdo)],
                             vendorID: vendor, productID: product, productType: 3)!
    }

    /// Apple 240 W USB 4 cable: 5 A, 50 V, EPR, USB4 Gen3, ~1 m.
    static let appleUSB4 = chip(vendor: 0x05AC, product: 0x7314, vdo: (0b10 << 5) | 0b011 | (0b11 << 9) | (1 << 13) | (1 << 17) | (0b10 << 18))
    /// The real no-name 240 W USB 2 cable (Cable VDO 0x000A4E40).
    static let noName240 = chip(vendor: 0, product: 0, vdo: 0x000A4E40)
    static let ugreen240 = chip(vendor: 0x2B1D, product: 0x1512, vdo: 0x000A4E40)

    static let apple140 = ChargerInfo(name: "Apple 140W USB-C Power Adapter", offers: [
        .init(millivolts: 5000, milliamps: 3000), .init(millivolts: 9000, milliamps: 3000),
        .init(millivolts: 15000, milliamps: 3000), .init(millivolts: 20000, milliamps: 5000),
        .init(millivolts: 28000, milliamps: 5000)], negotiatedWatts: 140)

    static func port(_ cable: CableIdentity?, partner: Int? = nil, name: String? = nil, links: [LiveLink] = []) -> PortState {
        PortState(number: 1, connectionActive: true, connectionUUID: "demo", transportsActive: ["CC"],
                  cable: cable, partnerVendorID: partner, partnerName: name, links: links)
    }

    @MainActor static func monitor(_ s: State) -> PortMonitor {
        let at = Date().addingTimeInterval(-2)
        switch s {
        case .empty, .history:
            return PortMonitor(demoPorts: [], charger: nil, focused: nil, pluggedAt: nil)
        case .mac:
            return PortMonitor(demoPorts: [port(appleUSB4, partner: 0x05AC, name: "Macintosh",
                                                links: [LiveLink(kind: .cio, speed: .gbps(40), deviceName: "Mac mini")])],
                               charger: nil, focused: 1, pluggedAt: at)
        case .charger:
            return PortMonitor(demoPorts: [port(ugreen240, partner: 0x05AC)], charger: apple140, focused: 1, pluggedAt: at)
        case .nochip:
            return PortMonitor(demoPorts: [port(nil, partner: 0x05AC, name: "Macintosh",
                                                links: [LiveLink(kind: .usb2, speed: .mbps(480), deviceName: "Mac mini")])],
                               charger: nil, focused: 1, pluggedAt: at.addingTimeInterval(-1))
        case .cableonly:
            return PortMonitor(demoPorts: [port(nil)], charger: nil, focused: 1, pluggedAt: at)
        case .device:
            return PortMonitor(demoPorts: [port(noName240, links: [LiveLink(kind: .usb2, speed: .mbps(12), deviceName: "Arctis GameBuds")])],
                               charger: nil, focused: 1, pluggedAt: at)
        }
    }

    static let records: [CableRecord] = {
        let day: TimeInterval = 86400
        let now = Date()
        func r(_ n: Int, _ tie: TieColor?, _ w: Int?, _ g: DataGeneration?, tb: Bool = false, _ s: DataSpeed?,
               _ vendor: String?, _ len: Double?, _ ago: TimeInterval) -> CableRecord {
            CableRecord(number: n, tested: now.addingTimeInterval(-ago), tie: tie,
                        values: .init(watts: w, generation: g, thunderbolt: tb, speed: s, vendor: vendor, lengthMetres: len),
                        fingerprint: n == 3 ? appleUSB4.fingerprint : nil)
        }
        return [
            r(7, .blue, 240, .usb4, tb: true, .gbps(40), "Apple", 1, 600),
            r(6, .purple, 240, .usb2, .mbps(480), nil, 2, 1800),
            r(5, .yellow, 60, .usb2, .mbps(480), nil, nil, 3600),
            r(4, .green, 100, .usb3, .gbps(10), "Belkin", 1, day),
            r(3, .blue, 240, .usb4v2, tb: true, .gbps(80), "Apple", 1, day + 600),
            r(2, .gray, 100, .usb4, .gbps(40), "Anker", 0.8, day + 1200),
            r(1, .orange, 100, .usb2, .mbps(480), "Anker", 0.13, day + 1800),
        ]
    }()
}

/// `--snapshot <dir>`: renders each screen into PNGs from an offscreen window. Nothing is shown on
/// screen: the app never activates and the windows live far outside every display.
enum Snapshot {
    final class OffscreenWindow: NSWindow {
        override func constrainFrameRect(_ r: NSRect, to screen: NSScreen?) -> NSRect { r }
    }

    @MainActor static func run(to dir: URL) {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        app.appearance = NSAppearance(named: .darkAqua)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = CableStore(demo: Demo.records)

        for s in Demo.State.allCases {
            let monitor = Demo.monitor(s)
            let view = RootView(mode: s == .history ? .history : .now).environment(monitor).environment(store)
            render(view, size: CGSize(width: 1100, height: 700), to: dir.appendingPathComponent("\(s.rawValue).png"))
        }
        // Save sheets, on their own.
        for (name, s) in [("save-chip", Demo.State.mac), ("save-nochip", .nochip)] {
            guard let r = Demo.monitor(s).result else { continue }
            let sheet = SaveSheet(result: r).environment(store)
            render(sheet, size: CGSize(width: 520, height: 560), titled: false, to: dir.appendingPathComponent("\(name).png"))
        }
        let invalid = SaveSheet(result: Demo.monitor(.nochip).result!, initialLength: "0,13m x").environment(store)
        render(invalid, size: CGSize(width: 520, height: 580), titled: false, to: dir.appendingPathComponent("save-invalid.png"))
        print("Wrote snapshots to \(dir.path)")
    }

    @MainActor static func render<V: View>(_ view: V, size: CGSize, titled: Bool = true, to url: URL) {
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height)
            .background(Color(nsColor: .windowBackgroundColor)).environment(\.colorScheme, .dark))
        let style: NSWindow.StyleMask = titled ? [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView] : [.borderless]
        let win = OffscreenWindow(contentRect: CGRect(x: -30000, y: -30000, width: size.width, height: size.height),
                                  styleMask: style, backing: .buffered, defer: false)
        win.appearance = NSAppearance(named: .darkAqua)
        win.title = "Cable Tester"
        if titled {
            win.toolbar = NSToolbar(identifier: "snap")
            win.toolbarStyle = .unified
        }
        win.contentView = host
        win.orderFrontRegardless()
        win.setFrameOrigin(CGPoint(x: -30000, y: -30000))
        // Let SwiftUI lay out, run onAppear and settle animations.
        RunLoop.main.run(until: Date().addingTimeInterval(0.8))
        let target = titled ? (win.contentView?.superview ?? host) : host
        target.layoutSubtreeIfNeeded()
        guard let rep = target.bitmapImageRepForCachingDisplay(in: target.bounds) else { return }
        target.cacheDisplay(in: target.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
        win.orderOut(nil)
    }
}
