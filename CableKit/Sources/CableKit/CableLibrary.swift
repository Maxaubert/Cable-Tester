import Foundation

/// The saved cables, stored as JSON.
public struct CableLibrary: Codable, Sendable {
    public var records: [CableRecord] = []
    public var importedPrototypeLog = false
    /// Highest number ever handed out. Never lowered on delete, so a printed label is never reused.
    public var highestNumber = 0

    public init(records: [CableRecord] = []) {
        self.records = records
        highestNumber = records.map(\.number).max() ?? 0
    }

    enum CodingKeys: String, CodingKey { case records, importedPrototypeLog, highestNumber }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        records = try c.decode([CableRecord].self, forKey: .records)
        importedPrototypeLog = try c.decodeIfPresent(Bool.self, forKey: .importedPrototypeLog) ?? true
        highestNumber = max(try c.decodeIfPresent(Int.self, forKey: .highestNumber) ?? 0, records.map(\.number).max() ?? 0)
    }

    public var nextNumber: Int { max(highestNumber, records.map(\.number).max() ?? 0) + 1 }

    /// The earliest saved cable of the same model (same chip identity) tested before `date`, if any.
    public func sameModel(as fingerprint: String?, before date: Date = .distantFuture) -> CableRecord? {
        guard let fingerprint else { return nil }
        return records.filter { $0.fingerprint == fingerprint && $0.tested < date }.min { $0.number < $1.number }
    }

    public mutating func add(_ r: CableRecord) {
        records.append(r)
        highestNumber = max(highestNumber, r.number)
    }

    public mutating func update(_ r: CableRecord) {
        if let i = records.firstIndex(where: { $0.id == r.id }) { records[i] = r }
    }

    public mutating func delete(id: UUID) { records.removeAll { $0.id == id } }

    /// Adds prototype-log cables whose numbers are not taken yet.
    public mutating func importPrototype(_ imported: [CableRecord]) {
        let taken = Set(records.map(\.number))
        records.append(contentsOf: imported.filter { !taken.contains($0.number) })
        highestNumber = max(highestNumber, records.map(\.number).max() ?? 0)
        importedPrototypeLog = true
    }

    public enum LoadResult {
        case missing
        case loaded(CableLibrary)
        case unreadable(Error)
    }

    /// Tells a missing file (first run) apart from one that cannot be read, so a damaged file is never
    /// silently replaced.
    public static func load(from url: URL) -> LoadResult {
        guard FileManager.default.fileExists(atPath: url.path) else { return .missing }
        do {
            let data = try Data(contentsOf: url)
            return .loaded(try JSONDecoder().decode(CableLibrary.self, from: data))
        } catch {
            return .unreadable(error)
        }
    }

    public func save(to url: URL) throws {
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try enc.encode(self).write(to: url, options: .atomic)
    }
}
