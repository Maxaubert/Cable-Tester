import AppKit
import CableKit
import SwiftUI

/// Entry point. Besides the normal app there are three headless modes:
///   --probe            print what the ports show right now and exit (hardware check, no window)
///   --snapshot <dir>   render every screen from demo data to PNGs offscreen and exit
///   --demo <state>     run the app on demo data (empty, mac, charger, nochip, cableonly, device, history)
@main
enum Entry {
    static func main() {
        let args = CommandLine.arguments
        if args.contains("--probe") {
            Probe.run()
            return
        }
        if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
            Snapshot.run(to: URL(fileURLWithPath: args[i + 1]))
            return
        }
        CableTesterApp.main()
    }
}

struct CableTesterApp: App {
    @State private var monitor: PortMonitor
    @State private var store: CableStore
    private let startMode: Mode

    init() {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--demo"), i + 1 < args.count, let d = Demo.State(rawValue: args[i + 1]) {
            _monitor = State(initialValue: Demo.monitor(d))
            _store = State(initialValue: CableStore(demo: Demo.records))
            startMode = d == .history ? .history : .now
        } else {
            _monitor = State(initialValue: PortMonitor())
            _store = State(initialValue: CableStore())
            startMode = .now
        }
        NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
    }

    var body: some Scene {
        Window("Cable Tester", id: "main") {
            RootView(mode: startMode)
                .environment(monitor)
                .environment(store)
        }
        .defaultSize(width: 1100, height: 700)
        .windowToolbarStyle(.unified)
        .commands { CommandGroup(replacing: .newItem) {} }
    }
}

/// `--probe`: print the live port readings. Used to check the hardware path without opening a window.
enum Probe {
    static func run() {
        let charger = IORegistryReader.charger()
        print("Charger: \(charger.map { "\($0.name ?? "?") · \($0.offersDescription) · max \($0.maxDescription ?? "—")" } ?? "none")")
        for p in IORegistryReader.ports() {
            var line = "Port \(p.number): \(p.connectionActive ? "connected" : "empty") transports=\(p.transportsActive)"
            if let c = p.cable {
                line += " chip=[\(c.watts) W, \(c.generation.name) \(c.ratedSpeed.formatted), \(c.maxCurrentAmps) A, \(c.maxVolts) V, EPR \(c.eprCapable), vendor \(String(format: "0x%04X", c.vendorID)), ~\(c.approxLengthMetres.map { Length.format($0) } ?? "?")]"
            }
            for l in p.links { line += " link=[\(l.kind.rawValue) \(l.speed?.formatted ?? "?") \(l.deviceName ?? "")]" }
            if let pv = p.partnerVendorID { line += " partner=\(String(format: "0x%04X", pv)) \(p.partnerName ?? "")" }
            print(line)
            if let r = CableResult.make(port: p, charger: charger) {
                let data = r.showsData ? "\(r.thunderbolt ? "[TB] " : "")\(r.generation?.name ?? "?") \(r.shownSpeed?.formatted ?? "")" : "(hidden)"
                print("   -> \(r.watts) W (\(r.wattsSource)) · data \(data) · far end \(r.farEnd)")
                if let n = r.limitNote { print("   -> \(n)") }
            }
        }
    }
}
