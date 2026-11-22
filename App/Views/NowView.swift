import CableKit
import SwiftUI

/// The "Now" screen: the plug-in checklist, then the result once both ends are connected.
struct NowView: View {
    @Environment(PortMonitor.self) private var monitor
    @Environment(CableStore.self) private var store
    @Binding var showInspector: Bool
    @Binding var savingResult: CableResult?
    /// The plug session whose result is on screen (set a moment after both checks tick).
    @State private var shownKey: String?
    /// The plug session where the user asked to see the chip before the far end was connected.
    @State private var forcedKey: String?

    private var plugKey: String? {
        guard let n = monitor.focusedPort else { return nil }
        return "\(n)-\(monitor.pluggedAt?.timeIntervalSince1970 ?? 0)"
    }

    /// Both ends connected: one in this Mac, the other in a charger, Mac or device.
    private var bothEnds: Bool {
        guard let r = monitor.result else { return false }
        if case .nothing = r.farEnd { return false }
        return true
    }

    private var showingResult: Bool {
        guard monitor.result != nil, let key = plugKey else { return false }
        if forcedKey == key { return true }
        return bothEnds && (monitor.isDemo || shownKey == key)
    }

    var body: some View {
        HStack(spacing: 0) {
            Group {
                if showingResult, let r = monitor.result {
                    ResultView(result: r, savingResult: $savingResult)
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                } else {
                    PlugChecklistView(port: monitor.focusedPortState, result: monitor.result,
                                      otherConnected: monitor.otherConnectedCount) {
                        withAnimation(.snappy) { forcedKey = plugKey }
                    }
                    .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .task(id: bothEnds ? plugKey : nil) {
                guard bothEnds, let key = plugKey else { shownKey = nil; return }
                // Let both checkmarks show for a moment before the result replaces them.
                try? await Task.sleep(for: .milliseconds(900))
                if !Task.isCancelled { withAnimation(.snappy) { shownKey = key } }
            }

            if showInspector {
                Divider()
                ScrollView {
                    Group {
                        if showingResult, let r = monitor.result { InspectorView(result: r) } else { RecentView() }
                    }
                    .padding(22)
                }
                .frame(width: 330)
                .transition(.move(edge: .trailing))
            }
        }
    }
}

// MARK: Plug-in checklist

/// "Plug in a cable you want to test": ticks off each end as it is connected.
struct PlugChecklistView: View {
    var port: PortState?
    var result: CableResult?
    var otherConnected: Int
    var showChipAnyway: () -> Void
    @State private var pulse = false

    private var macDone: Bool { port?.connectionActive == true }
    private var farDone: Bool {
        guard let r = result else { return false }
        if case .nothing = r.farEnd { return false }
        return true
    }

    var body: some View {
        VStack(spacing: 24) {
            PlugIllustration(pulse: pulse)
                .frame(width: 260, height: 130)
            Text(title).font(.system(size: 30, weight: .bold))
                .contentTransition(.opacity)
                .id(title)

            VStack(alignment: .leading, spacing: 0) {
                StepRow(done: macDone, active: !macDone, pulse: pulse,
                        title: "One end into this Mac", detail: macDetail)
                Divider().padding(.leading, 54)
                StepRow(done: farDone, active: macDone && !farDone, pulse: pulse,
                        title: "Other end into a charger, Mac or device", detail: farDetail)
            }
            .frame(width: 440)
            .background(Palette.groupFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Palette.groupStroke))

            footer.frame(maxWidth: 440)
        }
        .padding(40)
        .animation(.snappy, value: macDone)
        .animation(.snappy, value: farDone)
        .onAppear { withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { pulse = true } }
    }

    private var title: String {
        if !macDone { return "Plug in a cable you want to test" }
        if !farDone { return "Now plug in the other end" }
        return "Reading the cable…"
    }

    private var macDetail: String {
        guard macDone, let port else { return "Any USB-C port" }
        return "Port \(port.number)" + (port.cable != nil ? " · cable chip found" : "")
    }

    private var farDetail: String {
        if let r = result, farDone {
            return switch r.farEnd {
            case .charger(let c): c.name ?? "USB-C charger"
            case .unknown: "USB-C device"
            default: r.farEnd.name ?? "Connected"
            }
        }
        return "A charger tests power. A Mac or device also shows data speed."
    }

    @ViewBuilder private var footer: some View {
        if macDone, !farDone, port?.cable != nil {
            Button("Nothing to plug into? Show what the chip says", action: showChipAnyway)
                .buttonStyle(.link).font(.system(size: 13))
        } else if !macDone, otherConnected > 0 {
            Text(otherConnected == 1
                 ? "A cable that was already connected is ignored. Unplug and replug it to test it."
                 : "\(otherConnected) cables that were already connected are ignored. Unplug and replug one to test it.")
                .font(.system(size: 12)).foregroundStyle(.tertiary).multilineTextAlignment(.center)
        }
    }
}

/// One line of the checklist: an empty ring, a pulsing ring for the current step, or a green check.
struct StepRow: View {
    var done: Bool
    var active: Bool
    var pulse: Bool
    var title: String
    var detail: String

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                if done {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(Palette.power)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    Circle().strokeBorder(active ? Palette.thunderbolt.opacity(pulse ? 1 : 0.45) : Color.secondary.opacity(0.4),
                                          lineWidth: 2)
                        .frame(width: 22, height: 22)
                }
            }
            .frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 15, weight: .medium))
                    .foregroundStyle(done || active ? .primary : .secondary)
                Text(detail).font(.system(size: 12)).foregroundStyle(.secondary)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .accessibilityElement(children: .combine)
        .accessibilityValue(done ? "Done" : active ? "Waiting" : "Not yet")
    }
}

/// A USB-C plug heading for a port, with a soft glow at the port.
struct PlugIllustration: View {
    var pulse: Bool

    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            ZStack {
                // cable
                Path { p in p.move(to: CGPoint(x: 0, y: h * 0.5)); p.addLine(to: CGPoint(x: w * 0.30, y: h * 0.5)) }
                    .stroke(Color.secondary.opacity(0.7), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                // plug body
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(Color.secondary.opacity(0.85), lineWidth: 2)
                    .frame(width: w * 0.24, height: h * 0.30)
                    .position(x: w * 0.42, y: h * 0.5)
                // plug tip
                Capsule().strokeBorder(Color.secondary.opacity(0.85), lineWidth: 2)
                    .frame(width: w * 0.09, height: h * 0.16)
                    .position(x: w * 0.585, y: h * 0.5)
                // glow + port on the Mac's side
                Circle().fill(Palette.thunderbolt.opacity(pulse ? 0.22 : 0.08))
                    .frame(width: h * 0.85, height: h * 0.85)
                    .position(x: w * 0.80, y: h * 0.5)
                    .blur(radius: 6)
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.secondary.opacity(0.5), lineWidth: 1.5)
                    .frame(width: w * 0.30, height: h * 0.62)
                    .position(x: w * 0.86, y: h * 0.5)
                Capsule().fill(Palette.thunderbolt.opacity(0.9))
                    .frame(width: w * 0.08, height: h * 0.07)
                    .position(x: w * 0.78, y: h * 0.5)
            }
        }
        .accessibilityHidden(true)
    }
}

struct RecentView: View {
    @Environment(CableStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recent").font(.system(size: 15, weight: .semibold))
            let recent = store.records.sorted { $0.tested > $1.tested }.prefix(6)
            if recent.isEmpty {
                Text("Cables you save show up here.").font(.system(size: 13)).foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(recent.enumerated()), id: \.element.id) { i, r in
                        HStack(spacing: 10) {
                            Circle().fill(r.tie.map(Palette.tie) ?? Color.secondary.opacity(0.3)).frame(width: 9, height: 9)
                            Text(r.label).font(.system(size: 13, weight: .medium)).monospacedDigit()
                            Spacer()
                            Text(r.tested, format: .relative(presentation: .named)).font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 8).padding(.horizontal, 12)
                        if i < recent.count - 1 { Divider().padding(.leading, 12) }
                    }
                }
                .background(Palette.groupFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Palette.groupStroke))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: Result

struct ResultView: View {
    @Environment(PortMonitor.self) private var monitor
    @Environment(CableStore.self) private var store
    var result: CableResult
    @Binding var savingResult: CableResult?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            statusLine
                .padding(.bottom, 18)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(result.watts) W")
                    .font(.system(size: 112, weight: .bold, design: .default))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .minimumScaleFactor(0.5).lineLimit(1)
                if result.wattsSource == .estimate {
                    Text("est.").font(.system(size: 20, weight: .medium)).foregroundStyle(.secondary)
                        .baselineOffset(64)
                        .help("No cable chip read. Cables without a chip are limited to 3 A, so 60 W.")
                }
            }

            if result.showsData {
                HStack(spacing: 10) {
                    DataName(generation: result.generation, thunderbolt: result.thunderbolt, glyphSize: 30)
                    if let speed = result.shownSpeed {
                        Text("·").foregroundStyle(.secondary)
                        Text(speed.formatted).monospacedDigit()
                    }
                }
                .font(.system(size: 38, weight: .regular))
                .foregroundStyle(.secondary)
                .padding(.top, 2)
            } else if case .charger = result.farEnd {
                Text("Plug it into another Mac to see data speed.")
                    .font(.system(size: 17)).foregroundStyle(.secondary).padding(.top, 6)
            }

            notes.padding(.top, 20)

            HStack(spacing: 10) {
                ForEach(chips, id: \.self) { Chip(text: $0) }
            }
            .padding(.top, 20)

            HStack(spacing: 12) {
                Button {
                    savingResult = result
                } label: {
                    Text("Save as #\(String(format: "%02d", store.nextNumber))")
                        .font(.system(size: 15, weight: .semibold)).padding(.horizontal, 10).padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .keyboardShortcut("s", modifiers: .command)

                Button {
                    LabelActions.copy(CableLabel.make(number: store.nextNumber, watts: result.watts,
                                                      generation: result.showsData ? result.generation : result.cable?.generation))
                } label: { Image(systemName: "doc.on.doc").font(.system(size: 15)).frame(width: 22, height: 22) }
                .buttonStyle(.bordered).controlSize(.large)
                .help("Copy label")
                .accessibilityLabel("Copy label")
            }
            .padding(.top, 30)
        }
        .padding(.horizontal, 48)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .animation(.snappy, value: result)
    }

    @ViewBuilder private var statusLine: some View {
        switch result.farEnd {
        case .charger(let c):
            Label { Text("Charging · \(c.name ?? "USB-C charger")") } icon: { Image(systemName: "bolt.fill").foregroundStyle(Palette.power) }
                .font(.system(size: 15)).foregroundStyle(.secondary)
        default:
            if let at = monitor.pluggedAt {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text("Plugged in \(at, format: .relative(presentation: .numeric))").font(.system(size: 15)).foregroundStyle(.secondary)
                }
            } else {
                Text("Plugged in").font(.system(size: 15)).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var notes: some View {
        VStack(alignment: .leading, spacing: 10) {
            if result.cable == nil, result.wattsSource == .estimate {
                Label {
                    Text("No e-marker chip. Cables without one are limited to 3 A, so 60 W.")
                } icon: { Image(systemName: "info.circle").foregroundStyle(Palette.amber) }
                    .font(.system(size: 13))
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(Palette.amber.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Palette.amber.opacity(0.25)))
                    .frame(maxWidth: 460, alignment: .leading)
            }
            if result.showsData, let note = result.limitNote {
                Text(note).font(.system(size: 13)).foregroundStyle(.secondary)
            }
            if let same = store.sameModel(as: result.cable?.fingerprint, before: monitor.pluggedAt ?? .distantFuture) {
                Label("Same model as #\(same.numberText) (\(CableLabel.make(number: same.number, watts: same.values.watts, generation: same.values.generation).split(separator: " ").dropFirst().joined(separator: " ")))", systemImage: "clock.arrow.circlepath")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
            }
        }
    }

    private var chips: [String] {
        var c: [String] = []
        if let cable = result.cable {
            if cable.eprCapable { c.append("EPR") }
            c.append("\(cable.maxCurrentAmps) A")
            if cable.isActive { c.append("Active") }
        } else {
            c.append("No chip")
            c.append("3 A")
        }
        return c
    }
}

// MARK: Inspector

struct InspectorView: View {
    var result: CableResult

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            InfoGroup(title: "Cable e-marker", rows: chipRows, emptyText: "Not present")
            switch result.farEnd {
            case .charger(let c):
                InfoGroup(title: "Charger", rows: [
                    ("Adapter", c.name ?? "USB-C charger"),
                    ("Offers", c.offersDescription),
                    ("Max", c.maxDescription ?? "—"),
                    ("Negotiated", c.negotiatedWatts.map { "\($0) W" } ?? "—"),
                ])
            default:
                InfoGroup(title: "Live connection", rows: liveRows)
            }
            Text("Port \(result.port)").font(.system(size: 12)).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var chipRows: [(String, String)] {
        guard let c = result.cable else { return [] }
        return [
            ("Vendor ID", String(format: "0x%04X", c.vendorID) + (c.vendorName.map { " (\($0))" } ?? "")),
            ("Product ID", String(format: "0x%04X", c.productID)),
            ("Cable type", c.isActive ? "Active" : "Passive"),
            ("Max VBUS", "\(c.maxVolts) V"),
            ("Max current", "\(c.maxCurrentAmps) A"),
            ("Speed", "\(c.generation.name) · \(c.ratedSpeed.formatted)"),
            ("Length", c.approxLengthMetres.map { "~\(Length.format($0))" } ?? "—"),
        ]
    }

    private var liveRows: [(String, String)] {
        var rows: [(String, String)] = []
        let far: String = switch result.farEnd {
        case .nothing: "Nothing"
        case .unknown: "USB-C device"
        default: result.farEnd.name ?? "—"
        }
        rows.append(("Far end", far))
        if let l = result.liveLink {
            let kind: String = switch l.kind {
            case .cio: "USB 4 (Thunderbolt capable)"
            case .usb3: "USB 3"
            case .usb2: "USB 2 only"
            case .displayPort: "DisplayPort"
            }
            rows.append(("Link", kind))
            rows.append(("Negotiated", l.speed?.formatted ?? "—"))
        } else {
            rows.append(("Link", "None"))
        }
        return rows
    }
}
