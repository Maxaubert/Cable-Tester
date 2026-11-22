import CableKit
import SwiftUI

/// The "Now" screen: the plug-in checklist, then the result once both ends are connected.
/// Both checks hold for a moment, the checklist cascades out, and the result cascades in.
struct NowView: View {
    @Environment(PortMonitor.self) private var monitor
    @Environment(CableStore.self) private var store
    @Binding var showInspector: Bool
    @Binding var savingResult: CableResult?
    /// The plug session whose checklist is cascading out.
    @State private var leavingKey: String?
    /// The plug session whose result is on screen.
    @State private var shownKey: String?

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
        guard monitor.result != nil, let key = plugKey, bothEnds else { return false }
        return monitor.isDemo || shownKey == key
    }

    var body: some View {
        HStack(spacing: 0) {
            Group {
                if showingResult, let r = monitor.result {
                    ResultView(result: r, savingResult: $savingResult).id(plugKey)
                } else {
                    PlugChecklistView(port: monitor.focusedPortState, result: monitor.result,
                                      otherConnected: monitor.otherConnectedCount,
                                      leaving: plugKey != nil && leavingKey == plugKey)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .task(id: bothEnds ? plugKey : nil) {
                guard bothEnds, let key = plugKey else { shownKey = nil; leavingKey = nil; return }
                // Both checkmarks stay on screen for a moment, then the checklist cascades out.
                try? await Task.sleep(for: .milliseconds(900))
                guard !Task.isCancelled else { return }
                leavingKey = key
                try? await Task.sleep(for: .milliseconds(380))
                guard !Task.isCancelled else { return }
                shownKey = key
            }

            if showInspector {
                Divider()
                ScrollView {
                    CascadeOnAppear { shown in
                        Group {
                            if showingResult, let r = monitor.result { InspectorView(result: r) } else { RecentView() }
                        }
                        .cascade(4, shown: shown)
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

/// "Plug in a cable you want to test": the plug rises and the bolt draws for the Mac end, the bolt
/// fills for the other end, and each step gets a drawn checkmark.
struct PlugChecklistView: View {
    var port: PortState?
    var result: CableResult?
    var otherConnected: Int
    var leaving = false
    @State private var shown = false

    private var macDone: Bool { port?.connectionActive == true }
    private var farDone: Bool {
        guard let r = result else { return false }
        if case .nothing = r.farEnd { return false }
        return true
    }
    private var stage: Int { farDone ? 2 : macDone ? 1 : 0 }

    var body: some View {
        VStack(spacing: 22) {
            BoltPlugIllustration(stage: stage)
                .frame(width: 260, height: 150)
                .leave(0, leaving).cascade(0, shown: shown)
            Text(title).font(.system(size: 30, weight: .bold))
                .contentTransition(.opacity)
                .id(title)
                .leave(1, leaving).cascade(1, shown: shown)

            VStack(alignment: .leading, spacing: 0) {
                StepRow(done: macDone, active: !macDone, title: "One end into this Mac", detail: macDetail)
                Divider().padding(.leading, 54)
                StepRow(done: farDone, active: macDone && !farDone,
                        title: "Other end into a charger, Mac or device", detail: farDetail)
            }
            .frame(width: 440)
            .background(Palette.groupFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Palette.groupStroke))
            .leave(2, leaving).cascade(2, shown: shown)

            footer.frame(maxWidth: 440)
                .leave(3, leaving).cascade(3, shown: shown)
        }
        .padding(40)
        .onAppear { shown = true }
    }

    private var title: String {
        if !macDone { return "Plug in a cable you want to test" }
        if !farDone { return "Now plug in the other end" }
        return "Reading the cable…"
    }

    private var macDetail: String {
        guard macDone, let port else { return "Any USB-C port" }
        // The chip is only readable once the far end is connected (docs/emarker.md).
        return "Port \(port.number)"
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
        if !macDone, otherConnected > 0 {
            Text(otherConnected == 1
                 ? "A cable that was already connected is ignored. Unplug and replug it to test it."
                 : "\(otherConnected) cables that were already connected are ignored. Unplug and replug one to test it.")
                .font(.system(size: 12)).foregroundStyle(.tertiary).multilineTextAlignment(.center)
        } else {
            Color.clear.frame(height: 1)
        }
    }
}

extension View {
    /// The checklist leaving: top to bottom, each part fades and lifts away.
    func leave(_ index: Int, _ leaving: Bool) -> some View {
        opacity(leaving ? 0 : 1)
            .offset(y: leaving ? -14 : 0)
            .animation(leaving ? .easeIn(duration: 0.26).delay(Double(index) * 0.06) : nil, value: leaving)
    }
}

/// One line of the checklist: an empty ring, a pulsing lime ring for the current step, or the drawn check.
struct StepRow: View {
    var done: Bool
    var active: Bool
    var title: String
    var detail: String
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().strokeBorder(active ? Palette.lime.opacity(pulse ? 1 : 0.4) : Color.white.opacity(0.25), lineWidth: 2)
                    .frame(width: 22, height: 22)
                    .opacity(done ? 0 : 1)
                DrawnCheck(done: done, size: 24)
            }
            .frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 15, weight: .medium))
                    .foregroundStyle(done || active ? .primary : .secondary)
                Text(detail).font(.system(size: 12)).foregroundStyle(.secondary)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.opacity)
            }
            .animation(.easeOut(duration: 0.25), value: done)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .onAppear { withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) { pulse = true } }
        .accessibilityElement(children: .combine)
        .accessibilityValue(done ? "Done" : active ? "Waiting" : "Not yet")
    }
}

/// A USB-C plug seen from the front under the app icon's bolt. Stage 1 (Mac end in): the plug rises and the
/// bolt's outline draws in lime. Stage 2 (other end in): the bolt fills, glows and pops.
struct BoltPlugIllustration: View {
    var stage: Int
    @State private var pop = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let steel = LinearGradient(colors: [Color(white: 0.43), Color(white: 0.9), Color(white: 0.47)],
                                       startPoint: .leading, endPoint: .trailing)

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                BoltShape().stroke(Color.white.opacity(0.16), style: StrokeStyle(lineWidth: 2, lineJoin: .round))
                BoltShape().fill(Palette.lime)
                    .opacity(stage >= 2 ? 1 : 0)
                    .animation(.easeOut(duration: 0.3), value: stage)
                BoltShape().trim(from: 0, to: stage >= 1 ? 1 : 0)
                    .stroke(Palette.lime, style: StrokeStyle(lineWidth: 2.6, lineJoin: .round))
                    .animation(stage >= 1 ? .easeOut(duration: 0.7).delay(0.4) : .linear(duration: 0), value: stage)
            }
            .frame(width: 40, height: 62)
            .scaleEffect(pop ? 1.14 : 1)
            .shadow(color: Palette.lime.opacity(stage >= 2 ? 0.7 : 0), radius: 12)
            .animation(.easeOut(duration: 0.3), value: stage)

            VStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(steel)
                    .frame(width: 54, height: 32)
                    .overlay(Capsule().fill(Color(white: 0.1)).frame(width: 32, height: 6).offset(y: -2))
                RoundedRectangle(cornerRadius: 2).fill(stage >= 1 ? Palette.lime : Color(white: 0.13))
                    .frame(width: 66, height: 6)
                    .animation(.easeOut(duration: 0.3).delay(0.3), value: stage)
                UnevenRoundedRectangle(topLeadingRadius: 6, topTrailingRadius: 6).fill(Color(white: 0.16))
                    .frame(width: 66, height: 46)
            }
            .offset(y: stage >= 1 || reduceMotion ? 0 : 18)
            .opacity(stage >= 1 ? 1 : 0.8)
            .animation(.spring(response: 0.6, dampingFraction: 0.62), value: stage)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .mask(LinearGradient(stops: [.init(color: .black, location: 0.8), .init(color: .clear, location: 1)],
                             startPoint: .top, endPoint: .bottom))
        .onChange(of: stage) { old, new in
            guard new == 2, old < 2, !reduceMotion else { return }
            withAnimation(.spring(response: 0.18, dampingFraction: 0.7)) { pop = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.5)) { pop = false }
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
    @State private var shown = false

    /// The number this plug session was saved as, if it was.
    private var savedNumber: Int? {
        guard let s = store.lastSaved, s.at > (monitor.pluggedAt ?? .distantPast) else { return nil }
        return s.number
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            statusLine
                .padding(.bottom, 18)
                .cascade(0, shown: shown, base: 0.04)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                HStack(spacing: 0) {
                    CountUpText(value: result.watts, delay: 0.3)
                    Text(" W")
                }
                .font(.system(size: 112, weight: .bold))
                .foregroundStyle(Palette.lime)
                .minimumScaleFactor(0.5).lineLimit(1)
                if result.wattsSource == .estimate {
                    Text("est.").font(.system(size: 20, weight: .medium)).foregroundStyle(.secondary)
                        .baselineOffset(64)
                        .help("No cable chip read. Cables without a chip are limited to 3 A, so 60 W.")
                }
            }
            .cascade(1, shown: shown, base: 0.04)

            Group {
                if result.showsData {
                    HStack(spacing: 10) {
                        DataName(generation: result.generation, thunderbolt: result.thunderbolt, glyphSize: 30)
                            .foregroundStyle(.primary)
                        if let speed = result.shownSpeed {
                            Text("·").foregroundStyle(.secondary)
                            Text(speed.formatted).monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                    .font(.system(size: 38, weight: .regular))
                    .padding(.top, 2)
                } else if case .charger = result.farEnd {
                    Text("Plug it into another Mac to see data speed.")
                        .font(.system(size: 17)).foregroundStyle(.secondary).padding(.top, 6)
                }
            }
            .cascade(2, shown: shown, base: 0.04)

            notes.padding(.top, 20)
                .cascade(3, shown: shown, base: 0.04)

            HStack(spacing: 10) {
                ForEach(chips, id: \.self) { Chip(text: $0) }
            }
            .padding(.top, 20)
            .cascade(4, shown: shown, base: 0.04)

            HStack(spacing: 12) {
                saveButton
                Button {
                    LabelActions.copy(CableLabel.make(number: savedNumber ?? store.nextNumber, watts: result.watts,
                                                      generation: result.showsData ? result.generation : result.cable?.generation))
                } label: { Image(systemName: "doc.on.doc").font(.system(size: 15)).frame(width: 22, height: 22) }
                .buttonStyle(.bordered).controlSize(.large)
                .help("Copy label")
                .accessibilityLabel("Copy label")
            }
            .padding(.top, 30)
            .cascade(5, shown: shown, base: 0.04)
        }
        .padding(.horizontal, 48)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .onAppear { shown = true }
    }

    /// "Save as #08", then "✓ Saved #08" once the save sheet has saved this cable.
    private var saveButton: some View {
        let saved = savedNumber
        return Button {
            if saved == nil { savingResult = result }
        } label: {
            ZStack {
                Text("Save as #\(String(format: "%02d", store.nextNumber))")
                    .opacity(saved == nil ? 1 : 0)
                Label("Saved #\(String(format: "%02d", saved ?? 0))", systemImage: "checkmark")
                    .opacity(saved == nil ? 0 : 1)
                    .scaleEffect(saved == nil ? 0.6 : 1)
            }
            .fixedSize()
        }
        .buttonStyle(LimeButtonStyle(fill: saved == nil ? Palette.lime : Palette.limeSaved))
        .keyboardShortcut("s", modifiers: .command)
        .animation(.spring(response: 0.45, dampingFraction: 0.7), value: saved)
        .accessibilityLabel(saved == nil ? "Save as number \(store.nextNumber)" : "Saved as number \(saved!)")
    }

    @ViewBuilder private var statusLine: some View {
        switch result.farEnd {
        case .charger(let c):
            Label { Text("Charging · \(c.name ?? "USB-C charger")") } icon: { Image(systemName: "bolt.fill").foregroundStyle(Palette.lime) }
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
