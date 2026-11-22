import CableKit
import SwiftUI

enum HistoryFilter: String, CaseIterable, Identifiable {
    case all = "All", w240 = "240 W", w100 = "100 W", w60 = "60 W", thunderbolt = "Thunderbolt"
    var id: String { rawValue }

    func matches(_ r: CableRecord) -> Bool {
        switch self {
        case .all: true
        case .w240: r.values.watts == 240
        case .w100: r.values.watts == 100
        case .w60: r.values.watts == 60
        case .thunderbolt: r.values.thunderbolt
        }
    }
}

/// Sort keys for the table (optionals sort first as "unknown").
extension CableRecord {
    var sortTie: Int { tie.map { TieColor.allCases.firstIndex(of: $0)! } ?? -1 }
    var sortWatts: Int { values.watts ?? -1 }
    var sortData: Int { (values.generation.map { DataGeneration.allCases.firstIndex(of: $0)! } ?? -1) * 2 + (values.thunderbolt ? 1 : 0) }
    var sortSpeed: Double { values.speed?.bitsPerSecond ?? -1 }
    var sortVendor: String { values.vendor ?? "" }
    var sortLength: Double { values.lengthMetres ?? -1 }
}

struct HistoryView: View {
    @Environment(CableStore.self) private var store
    @State private var search = ""
    @State private var filter = HistoryFilter.all
    @Binding var selection: Set<CableRecord.ID>
    @State private var sortOrder = [KeyPathComparator(\CableRecord.tested, order: .reverse)]
    @State private var shown = false

    private var rows: [CableRecord] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        return store.records
            .filter { filter.matches($0) }
            .filter { r in
                q.isEmpty || r.label.lowercased().contains(q) || (r.values.vendor ?? "").lowercased().contains(q)
                    || (r.tie?.rawValue ?? "").contains(q) || r.numberText.contains(q)
            }
            .sorted(using: sortOrder)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("History").font(.system(size: 28, weight: .bold)).padding(.horizontal, 24).padding(.top, 18)
                .cascade(0, shown: shown, base: 0.18)
            HStack(spacing: 14) {
                TextField("Search", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 320)
                Spacer()
                Picker("Filter", selection: $filter) {
                    ForEach(HistoryFilter.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 440)
            }
            .padding(.horizontal, 24).padding(.vertical, 14)
            .cascade(1, shown: shown, base: 0.18)

            Table(rows, selection: $selection, sortOrder: $sortOrder) {
                TableColumn("#", value: \.number) { r in Text(r.numberText).monospacedDigit() }
                    .width(36)
                TableColumn("Tie", value: \.sortTie) { r in TieCell(record: r) }
                    .width(44)
                TableColumn("Power", value: \.sortWatts) { r in PowerCell(record: r) }
                    .width(min: 70, ideal: 80)
                TableColumn("Data", value: \.sortData) { r in DataCell(record: r) }
                    .width(min: 90, ideal: 110)
                TableColumn("Speed", value: \.sortSpeed) { r in SpeedCell(record: r) }
                    .width(min: 80, ideal: 92)
                TableColumn("Vendor", value: \.sortVendor) { r in VendorCell(record: r) }
                    .width(min: 80, ideal: 110)
                TableColumn("Length", value: \.sortLength) { r in LengthCell(record: r) }
                    .width(min: 70, ideal: 80)
                TableColumn("Tested", value: \.tested) { r in
                    Text(r.tested, format: .dateTime.day().month(.abbreviated).hour().minute()).foregroundStyle(.secondary)
                }
                .width(min: 110, ideal: 130)
            }
            .contextMenu(forSelectionType: CableRecord.ID.self) { ids in
                if let id = ids.first, let r = store.records.first(where: { $0.id == id }) {
                    Button("Copy Label") { LabelActions.copy(r.label) }
                    Button("Print Label…") { LabelActions.print(r.label) }
                    if !r.editedFields.isEmpty {
                        Button("Restore Measured Values") { var c = r; c.values = c.measured; store.update(c) }
                    }
                    Divider()
                    Button("Delete", role: .destructive) { for i in ids { store.delete(i) } }
                }
            }
            .onDeleteCommand { for i in selection { store.delete(i) } }
            .scrollContentBackground(.hidden)
            .background(Palette.background)
            .offset(y: shown || reduceMotion ? 0 : 10)
            .animation(.spring(response: 0.5, dampingFraction: 0.9).delay(shown ? 0.27 : 0), value: shown)
            // Rows appear one by one: a black band per row fades away, top to bottom.
            .overlay(alignment: .top) { if !reduceMotion { RowCurtain(shown: shown, base: 0.27) } }

            Divider()
            Text("\(rows.count) \(rows.count == 1 ? "cable" : "cables")")
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .padding(.horizontal, 24).padding(.vertical, 8)
        }
        .onAppear { shown = true }
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
}

/// Black bands the height of a table row that fade away one after another, so the native table's rows
/// look like they cascade in.
struct RowCurtain: View {
    var shown: Bool
    var base: Double
    var rowHeight: CGFloat = 26

    var body: some View {
        GeometryReader { g in
            VStack(spacing: 0) {
                ForEach(0..<(Int(g.size.height / rowHeight) + 1), id: \.self) { i in
                    Palette.background.frame(height: rowHeight)
                        .opacity(shown ? 0 : 1)
                        .animation(.easeOut(duration: 0.3).delay(shown ? base + Double(i) * 0.045 : 0), value: shown)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: Cells. Every cell edits in place; there are no locks.

private struct AddText: View {
    var body: some View { Text("Add").italic().foregroundStyle(.tertiary) }
}

struct TieCell: View {
    @Environment(CableStore.self) private var store
    var record: CableRecord
    var body: some View {
        Menu {
            ForEach(TieColor.allCases, id: \.self) { t in
                Button { set(t) } label: { Label { Text(t.name) } icon: { GlyphImages.dot(Palette.tie(t), key: t.rawValue) } }
            }
            Divider()
            Button("None") { set(nil) }
        } label: {
            if let t = record.tie { GlyphImages.dot(Palette.tie(t), key: t.rawValue) } else { GlyphImages.dot(.gray.opacity(0.3), key: "none") }
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .accessibilityLabel("Tie color \(record.tie?.name ?? "none")")
    }
    private func set(_ t: TieColor?) { var r = record; r.tie = t; store.update(r) }
}

/// A small dot after a value the user changed; its tooltip gives the measured value.
struct EditedMark: View {
    var measured: String?
    var body: some View {
        Circle().fill(Palette.thunderbolt.opacity(0.8)).frame(width: 5, height: 5)
            .help("Edited. Measured: \(measured ?? "nothing"). Right-click the row to restore.")
            .accessibilityLabel("Edited")
    }
}

struct PowerCell: View {
    @Environment(CableStore.self) private var store
    var record: CableRecord
    var body: some View {
        InlineTextCell(text: record.values.watts.map { "\($0) W" } ?? "",
                       edited: record.editedFields.contains("watts") ? (record.measured.watts.map { "\($0) W" } ?? "nothing") : nil,
                       message: "Enter watts from 1 to 240", validate: { Watts.parse($0) != nil }) { t in
            var r = record; r.values.watts = Watts.parse(t); store.update(r)
        }
    }
}

struct DataCell: View {
    @Environment(CableStore.self) private var store
    var record: CableRecord
    var body: some View {
        HStack(spacing: 4) {
            if record.editedFields.contains("data") {
                EditedMark(measured: record.measured.generation.map { $0.name + (record.measured.thunderbolt ? " (Thunderbolt)" : "") })
            }
            menu
        }
    }

    @ViewBuilder private var menu: some View {
        Menu {
            ForEach(DataGeneration.allCases, id: \.self) { g in
                Button { set(g) } label: { if record.values.generation == g { Label(g.name, systemImage: "checkmark") } else { Text(g.name) } }
            }
            Divider()
            Toggle("Thunderbolt", isOn: Binding(get: { record.values.thunderbolt }, set: { v in
                var r = record; r.values.thunderbolt = v; if v && r.values.generation == nil { r.values.generation = .usb4 }; store.update(r)
            }))
            Button("Unknown") { set(nil) }
        } label: {
            if record.values.generation != nil {
                DataName(generation: record.values.generation, thunderbolt: record.values.thunderbolt, glyphSize: 12)
                    .foregroundStyle(.primary)
            } else { AddText() }
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .tint(.primary)
    }
    private func set(_ g: DataGeneration?) {
        var r = record; r.values.generation = g; if g == nil { r.values.thunderbolt = false }; store.update(r)
    }
}

/// A cell that looks like text and becomes a field when clicked. Invalid input keeps the field open and
/// shows the message in a popover that floats over the rows below (rows never grow).
struct InlineTextCell: View {
    var text: String
    var placeholderAdd = true
    var suffix: String? = nil
    var color: Color? = nil
    /// The measured value, when the user changed it.
    var edited: String? = nil
    var message: String
    var validate: (String) -> Bool
    var commit: (String) -> Void

    @State private var draft = ""
    @State private var invalid = false
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 4) {
            if let edited, !focused { EditedMark(measured: edited) }
            TextField("", text: $draft, prompt: placeholderAdd ? Text("Add").italic() : nil)
                .textFieldStyle(.plain)
                .monospacedDigit()
                .foregroundStyle(color ?? .primary)
                .focused($focused)
                .onSubmit { apply(leaving: false) }
                .onChange(of: focused) { _, f in if !f { apply(leaving: true) } }
            if let suffix, !draft.isEmpty { Text(suffix).foregroundStyle(.secondary) }
        }
        .padding(.horizontal, 4).padding(.vertical, 1)
        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(invalid ? Color.red : (focused ? Palette.thunderbolt : .clear), lineWidth: 1.2))
        .popover(isPresented: $invalid, arrowEdge: .bottom) {
            Text(message).font(.system(size: 12)).padding(.horizontal, 10).padding(.vertical, 6)
        }
        .onAppear { draft = text }
        .onChange(of: text) { _, t in if !focused { draft = t } }
    }

    /// Enter with bad input keeps the field open and shows why. Clicking away with bad input puts the
    /// saved value back, so the cell never shows something that was not saved.
    private func apply(leaving: Bool) {
        let t = draft.trimmingCharacters(in: .whitespaces)
        if t.isEmpty || validate(t) {
            invalid = false
            if t != text { commit(t) }
        } else if leaving {
            invalid = false
            draft = text
        } else {
            invalid = true
            focused = true
        }
    }
}

struct SpeedCell: View {
    @Environment(CableStore.self) private var store
    var record: CableRecord
    var body: some View {
        InlineTextCell(text: record.values.speed?.formatted ?? "",
                       edited: record.editedFields.contains("speed") ? (record.measured.speed?.formatted ?? "nothing") : nil,
                       message: "Enter a speed like 40 Gb/s or 480 Mb/s",
                       validate: { DataSpeed.parse(cell: $0) != nil }) { t in
            var r = record; r.values.speed = DataSpeed.parse(cell: t); store.update(r)
        }
    }
}

struct VendorCell: View {
    @Environment(CableStore.self) private var store
    var record: CableRecord
    var body: some View {
        InlineTextCell(text: record.values.vendor ?? "",
                       edited: record.editedFields.contains("vendor") ? (record.measured.vendor ?? "nothing") : nil,
                       message: "", validate: { _ in true }) { t in
            var r = record; r.values.vendor = t.isEmpty ? nil : t; store.update(r)
        }
    }
}

struct LengthCell: View {
    @Environment(CableStore.self) private var store
    var record: CableRecord
    var body: some View {
        InlineTextCell(text: record.values.lengthMetres.map(Length.format) ?? "",
                       edited: record.editedFields.contains("length") ? (record.measured.lengthMetres.map(Length.format) ?? "nothing") : nil,
                       message: "Enter metres, like 0.13", validate: { Length.parse($0) != nil }) { t in
            var r = record; r.values.lengthMetres = Length.parse(t); store.update(r)
        }
    }
}
