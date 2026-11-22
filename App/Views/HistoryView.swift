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

            Divider()
            Text("\(rows.count) \(rows.count == 1 ? "cable" : "cables")")
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .padding(.horizontal, 24).padding(.vertical, 8)
        }
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

struct PowerCell: View {
    @Environment(CableStore.self) private var store
    var record: CableRecord
    var body: some View {
        Menu {
            ForEach(wattTiers, id: \.self) { w in Button("\(w) W") { set(w) } }
            Divider()
            Button("Unknown") { set(nil) }
        } label: {
            if let w = record.values.watts { Text("\(w) W").foregroundStyle(Palette.power).monospacedDigit() } else { AddText() }
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
    }
    private func set(_ w: Int?) { var r = record; r.values.watts = w; store.update(r) }
}

struct DataCell: View {
    @Environment(CableStore.self) private var store
    var record: CableRecord
    var body: some View {
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
            } else { AddText() }
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
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
    var message: String
    var validate: (String) -> Bool
    var commit: (String) -> Void

    @State private var draft = ""
    @State private var invalid = false
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 3) {
            TextField("", text: $draft, prompt: placeholderAdd ? Text("Add").italic() : nil)
                .textFieldStyle(.plain)
                .monospacedDigit()
                .focused($focused)
                .onSubmit(apply)
                .onChange(of: focused) { _, f in if !f { apply() } }
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

    private func apply() {
        let t = draft.trimmingCharacters(in: .whitespaces)
        if t.isEmpty || validate(t) {
            invalid = false
            if t != text { commit(t) }
        } else {
            invalid = true
        }
    }
}

struct SpeedCell: View {
    @Environment(CableStore.self) private var store
    var record: CableRecord
    var body: some View {
        InlineTextCell(text: record.values.speed?.formatted ?? "", message: "Enter a speed like 40 Gb/s or 480 Mb/s",
                       validate: { DataSpeed.parse(cell: $0) != nil }) { t in
            var r = record; r.values.speed = DataSpeed.parse(cell: t); store.update(r)
        }
    }
}

struct VendorCell: View {
    @Environment(CableStore.self) private var store
    var record: CableRecord
    var body: some View {
        InlineTextCell(text: record.values.vendor ?? "", message: "", validate: { _ in true }) { t in
            var r = record; r.values.vendor = t.isEmpty ? nil : t; store.update(r)
        }
    }
}

struct LengthCell: View {
    @Environment(CableStore.self) private var store
    var record: CableRecord
    var body: some View {
        InlineTextCell(text: record.values.lengthMetres.map(Length.format) ?? "",
                       message: "Enter metres, like 0.13", validate: { Length.parse($0) != nil }) { t in
            var r = record; r.values.lengthMetres = Length.parse(t); store.update(r)
        }
    }
}
