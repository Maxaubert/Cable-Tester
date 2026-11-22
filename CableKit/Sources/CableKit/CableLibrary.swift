import Foundation

/// The saved cables, stored as JSON.
public struct CableLibrary: Codable, Sendable {
    public var records: [CableRecord] = []
    public var importedPrototypeLog = false

    public init(records: [CableRecord] = []) { self.records = records }

    public var nextNumber: Int { (records.map(\.number).max() ?? 0) + 1 }

    /// The earliest saved cable of the same model (same chip identity), if any.
    public func sameModel(as fingerprint: String?) -> CableRecord? {
        guard let fingerprint else { return nil }
        return records.filter { $0.fingerprint == fingerprint }.min { $0.number < $1.number }
    }

    public mutating func add(_ r: CableRecord) { records.append(r) }

    public mutating func update(_ r: CableRecord) {
        if let i = records.firstIndex(where: { $0.id == r.id }) { records[i] = r }
    }

    public mutating func delete(id: UUID) { records.removeAll { $0.id == id } }

    /// Adds prototype-log cables whose numbers are not taken yet.
    public mutating func importPrototype(_ imported: [CableRecord]) {
        let taken = Set(records.map(\.number))
        records.append(contentsOf: imported.filter { !taken.contains($0.number) })
        importedPrototypeLog = true
    }

    public static func load(from url: URL) -> CableLibrary {
        guard let data = try? Data(contentsOf: url) else { return CableLibrary() }
        let dec = JSONDecoder()
        return (try? dec.decode(CableLibrary.self, from: data)) ?? CableLibrary()
    }

    public func save(to url: URL) throws {
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try enc.encode(self).write(to: url, options: .atomic)
    }
}
