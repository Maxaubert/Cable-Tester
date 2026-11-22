import CableKit
import SwiftUI

enum Mode { case now, history }

struct RootView: View {
    @Environment(PortMonitor.self) private var monitor
    @Environment(CableStore.self) private var store
    @State var mode: Mode = .now
    @State var showInspector = true
    @State private var savingResult: CableResult?
    @State private var selection = Set<CableRecord.ID>()

    var body: some View {
        Group {
            switch mode {
            case .now: NowView(showInspector: $showInspector, savingResult: $savingResult)
            case .history: HistoryView(selection: $selection)
            }
        }
        .frame(minWidth: 860, minHeight: 560)
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle("Cable Tester")
        .toolbar {
            ToolbarItem(placement: .navigation) {
                if mode == .now {
                    Button { withAnimation(.snappy) { showInspector.toggle() } } label: { Image(systemName: "sidebar.right") }
                        .help(showInspector ? "Hide details" : "Show details")
                } else {
                    Button { mode = .now } label: { Label("Now", systemImage: "chevron.left") }
                        .labelStyle(.titleAndIcon).help("Back to the plugged-in cable")
                }
            }
            if mode == .history {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button { selectedLabel.map(LabelActions.copy) } label: { Image(systemName: "doc.on.doc") }
                        .help("Copy label").disabled(selectedLabel == nil)
                    Button { selectedLabel.map(LabelActions.print) } label: { Image(systemName: "printer") }
                        .help("Print label").disabled(selectedLabel == nil)
                    Button { store.exportCSV() } label: { Image(systemName: "square.and.arrow.up") }
                        .help("Export CSV")
                }
            } else {
                ToolbarItem(placement: .primaryAction) {
                    Button { mode = .history } label: { Image(systemName: "clock.arrow.circlepath") }
                        .help("History").keyboardShortcut("y", modifiers: .command)
                }
            }
        }
        .sheet(item: $savingResult) { r in SaveSheet(result: r) }
        .alert("Could not save", isPresented: Binding(get: { store.lastError != nil }, set: { if !$0 { store.lastError = nil } })) {
            Button("OK") { store.lastError = nil }
        } message: { Text(store.lastError ?? "") }
        .onAppear { monitor.start() }
    }

    private var selectedLabel: String? {
        guard selection.count == 1, let id = selection.first else { return nil }
        return store.records.first { $0.id == id }?.label
    }
}

extension CableResult: @retroactive Identifiable {
    public var id: String { "\(port)-\(watts)-\(String(describing: generation))-\(cable?.fingerprint ?? "")" }
}
