import CableKit
import SwiftUI

/// Shared editing state for a cable's values, used by the save sheet.
struct CableDraft {
    var wattsText: String
    var generation: DataGeneration?
    var thunderbolt: Bool
    var speedText: String
    var speedUnit: DataSpeed.Unit
    var vendor: String
    var lengthText: String
    var tie: TieColor?

    init(values v: CableRecord.Values, tie: TieColor?) {
        wattsText = v.watts.map(String.init) ?? ""; generation = v.generation; thunderbolt = v.thunderbolt
        speedUnit = v.speed?.naturalUnit ?? .gbps
        speedText = v.speed.map { DataSpeed.trim($0.value(in: $0.naturalUnit)) } ?? ""
        vendor = v.vendor ?? ""
        lengthText = Length.editText(v.lengthMetres)
        self.tie = tie
    }

    var lengthValid: Bool { lengthText.trimmingCharacters(in: .whitespaces).isEmpty || Length.parse(lengthText) != nil }
    var speedValid: Bool { speedText.trimmingCharacters(in: .whitespaces).isEmpty || DataSpeed.parse(typed: speedText, unit: speedUnit) != nil }
    var wattsValid: Bool { wattsText.trimmingCharacters(in: .whitespaces).isEmpty || Watts.parse(wattsText) != nil }
    var isValid: Bool { lengthValid && speedValid && wattsValid }

    var values: CableRecord.Values {
        CableRecord.Values(
            watts: Watts.parse(wattsText), generation: generation, thunderbolt: generation != nil && thunderbolt,
            speed: DataSpeed.parse(typed: speedText, unit: speedUnit),
            vendor: vendor.trimmingCharacters(in: .whitespaces).isEmpty ? nil : vendor.trimmingCharacters(in: .whitespaces),
            lengthMetres: Length.parse(lengthText))
    }
}

let wattTiers = [15, 60, 100, 140, 240]

struct SaveSheet: View {
    @Environment(CableStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let result: CableResult
    @State private var draft: CableDraft
    private let measured: CableRecord.Values

    init(result: CableResult, initialLength: String? = nil) {
        self.result = result
        let m = CableRecord.measuredValues(from: result)
        measured = m
        var d = CableDraft(values: m, tie: nil)
        if let initialLength { d.lengthText = initialLength }
        _draft = State(initialValue: d)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Save cable #\(String(format: "%02d", store.nextNumber))")
                .font(.system(size: 22, weight: .bold))
            Text(result.cable != nil ? "Filled in from the cable. Change anything that looks wrong."
                 : "This cable has no chip, so a few things are unknown. Empty fields stay blank.")
                .font(.system(size: 13)).foregroundStyle(.secondary).padding(.top, 4)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 0) {
                row("Power", empty: draft.wattsText.isEmpty) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            TextField("e.g. 100", text: $draft.wattsText).textFieldStyle(.roundedBorder).frame(width: 80)
                            Text("W").foregroundStyle(.secondary)
                            Menu {
                                ForEach(wattTiers, id: \.self) { w in Button("\(w) W") { draft.wattsText = String(w) } }
                            } label: { Image(systemName: "chevron.up.chevron.down") }
                            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                            .help("Common ratings")
                        }
                        if !draft.wattsValid {
                            Text("Enter watts from 1 to 240").font(.system(size: 11)).foregroundStyle(.red)
                        }
                    }
                }
                row("Data", empty: draft.generation == nil) {
                    HStack(spacing: 14) {
                        Picker("Data", selection: $draft.generation) {
                            Text("Unknown").tag(DataGeneration?.none)
                            ForEach(DataGeneration.allCases, id: \.self) { Text($0.name).tag(DataGeneration?.some($0)) }
                        }.labelsHidden().fixedSize()
                        Toggle("Thunderbolt", isOn: $draft.thunderbolt).disabled(draft.generation == nil)
                    }
                }
                row("Speed", empty: draft.speedText.isEmpty) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            TextField("e.g. 40", text: $draft.speedText).textFieldStyle(.roundedBorder).frame(width: 110)
                            Picker("Unit", selection: $draft.speedUnit) {
                                ForEach(DataSpeed.Unit.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                            }.labelsHidden().fixedSize()
                        }
                        if !draft.speedValid {
                            Text("Enter a speed like 40 or 0.48").font(.system(size: 11)).foregroundStyle(.red)
                        }
                    }
                }
                row("Tie color", empty: draft.tie == nil) { TieSwatches(selection: $draft.tie) }
                row("Length", empty: draft.lengthText.isEmpty) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            TextField("e.g. 0.13", text: $draft.lengthText).textFieldStyle(.roundedBorder).frame(width: 110)
                            Text("m").foregroundStyle(.secondary)
                        }
                        if !draft.lengthValid {
                            Text("Enter a length in metres, like 0.13 or 2").font(.system(size: 11)).foregroundStyle(.red)
                        }
                    }
                }
                row("Vendor", empty: draft.vendor.isEmpty, last: true) {
                    TextField("e.g. Anker", text: $draft.vendor).textFieldStyle(.roundedBorder).frame(width: 220)
                }
            }
            .padding(.top, 18)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction).controlSize(.large)
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction).controlSize(.large)
                    .disabled(!draft.isValid)
            }
            .padding(.top, 20)
        }
        .padding(26)
        .frame(width: 520)
    }

    @ViewBuilder
    private func row<C: View>(_ title: String, empty: Bool, last: Bool = false, @ViewBuilder content: () -> C) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(title).font(.system(size: 14)).frame(width: 80, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Palette.thunderbolt.opacity(empty ? 0.5 : 0), lineWidth: 1)
        )
        .padding(.vertical, 2)
        if !last { Divider().padding(.horizontal, 10) }
    }

    private func save() {
        guard draft.isValid else { return }
        store.add(CableRecord(number: store.nextNumber, tie: draft.tie, values: draft.values,
                              measured: measured, fingerprint: result.cable?.fingerprint))
        dismiss()
    }
}
