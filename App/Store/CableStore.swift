import AppKit
import CableKit
import Foundation
import Observation

/// The saved cables, persisted as JSON in Application Support.
@MainActor @Observable
final class CableStore {
    private(set) var library: CableLibrary
    private let url: URL?
    var lastError: String?

    var records: [CableRecord] { library.records }
    var nextNumber: Int { library.nextNumber }

    static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Cable Tester/cables.json")
    }

    /// The prototype's CSV log, imported once on first run.
    static let prototypeLog = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Documents/Claude/zz-Misc/cable-tester/cables.csv")

    init(url: URL = CableStore.defaultURL) {
        self.url = url
        library = CableLibrary.load(from: url)
        if !library.importedPrototypeLog {
            if let text = try? String(contentsOf: Self.prototypeLog, encoding: .utf8) {
                library.importPrototype(CableCSV.importPrototypeLog(text))
            } else {
                library.importedPrototypeLog = true
            }
            persist()
        }
    }

    /// In-memory store for demo mode and screenshots.
    init(demo records: [CableRecord]) {
        url = nil
        library = CableLibrary(records: records)
    }

    func sameModel(as fingerprint: String?) -> CableRecord? { library.sameModel(as: fingerprint) }

    func add(_ r: CableRecord) { library.add(r); persist() }
    func update(_ r: CableRecord) { library.update(r); persist() }
    func delete(_ id: UUID) { library.delete(id: id); persist() }

    private func persist() {
        guard let url else { return }
        do { try library.save(to: url) } catch { lastError = error.localizedDescription }
    }

    func exportCSV() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "cables.csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        guard panel.runModal() == .OK, let dest = panel.url else { return }
        do { try CableCSV.export(records).write(to: dest, atomically: true, encoding: .utf8) }
        catch { lastError = error.localizedDescription }
    }
}
