import CableKit
import SwiftUI

/// The "Now" screen: what is plugged in, or the empty state.
struct NowView: View {
    @Environment(PortMonitor.self) private var monitor
    @Environment(CableStore.self) private var store
    @Binding var showInspector: Bool
    @Binding var savingResult: CableResult?

    var body: some View {
        HStack(spacing: 0) {
            Group {
                if let r = monitor.result {
                    if case .nothing = r.farEnd, r.cable == nil {
                        CableOnlyView(port: r.port)
                    } else {
                        ResultView(result: r, savingResult: $savingResult)
                    }
                } else {
                    EmptyStateView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if showInspector {
                Divider()
                ScrollView {
                    Group {
                        if let r = monitor.result { InspectorView(result: r) } else { RecentView() }
                    }
                    .padding(22)
                }
                .frame(width: 330)
                .transition(.move(edge: .trailing))
            }
        }
    }
}

// MARK: Empty

struct EmptyStateView: View {
    @State private var pulse = false

    var body: some View {
        VStack(spacing: 22) {
            PlugIllustration(pulse: pulse)
                .frame(width: 300, height: 150)
            VStack(spacing: 8) {
                Text("Plug in a cable").font(.system(size: 30, weight: .bold))
                Text("A charger tests power. Another Mac or any USB-C device reads the cable's chip too.")
                    .font(.system(size: 14)).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).frame(maxWidth: 360)
            }
        }
        .padding(40)
        .onAppear { withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { pulse = true } }
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

// MARK: Cable only (other end free)

struct CableOnlyView: View {
    var port: Int
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Cable detected on port \(port)", systemImage: "cable.connector.horizontal")
                .font(.system(size: 15)).foregroundStyle(.secondary)
            Text("Plug in the other end").font(.system(size: 34, weight: .bold))
            Text("Into a charger, a Mac or any USB-C device. The Mac can only read the cable when something is on the other end.")
                .font(.system(size: 15)).foregroundStyle(.secondary).frame(maxWidth: 440, alignment: .leading)
        }
        .padding(48)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
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

            if result.showsData, let speed = result.shownSpeed {
                HStack(spacing: 10) {
                    DataName(generation: result.generation, thunderbolt: result.thunderbolt, glyphSize: 30)
                    Text("·").foregroundStyle(.secondary)
                    Text(speed.formatted).monospacedDigit()
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
            if let same = store.sameModel(as: result.cable?.fingerprint) {
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
