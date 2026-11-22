import Foundation

public enum TieColor: String, Codable, CaseIterable, Sendable {
    case red, orange, yellow, green, blue, purple, pink, gray

    public var name: String { rawValue.capitalized }
}

/// One saved cable. Every field the user can see is editable; `measured` keeps what the app read,
/// so an edited value can be put back.
public struct CableRecord: Codable, Identifiable, Hashable, Sendable {
    public struct Values: Codable, Hashable, Sendable {
        public var watts: Int?
        public var generation: DataGeneration?
        public var thunderbolt: Bool
        public var speed: DataSpeed?
        public var vendor: String?
        public var lengthMetres: Double?

        public init(watts: Int? = nil, generation: DataGeneration? = nil, thunderbolt: Bool = false,
                    speed: DataSpeed? = nil, vendor: String? = nil, lengthMetres: Double? = nil) {
            self.watts = watts; self.generation = generation; self.thunderbolt = thunderbolt
            self.speed = speed; self.vendor = vendor; self.lengthMetres = lengthMetres
        }
    }

    public var id: UUID
    public var number: Int
    public var tested: Date
    public var tie: TieColor?
    public var values: Values
    public var measured: Values
    public var fingerprint: String?

    public init(id: UUID = UUID(), number: Int, tested: Date = Date(), tie: TieColor? = nil,
                values: Values, measured: Values? = nil, fingerprint: String? = nil) {
        self.id = id; self.number = number; self.tested = tested; self.tie = tie
        self.values = values; self.measured = measured ?? values; self.fingerprint = fingerprint
    }

    public var label: String { CableLabel.make(number: number, watts: values.watts, generation: values.generation) }
    public var numberText: String { String(format: "%02d", number) }

    /// Fields the user changed from what the app measured.
    public var editedFields: Set<String> {
        var s = Set<String>()
        if values.watts != measured.watts { s.insert("watts") }
        if values.generation != measured.generation || values.thunderbolt != measured.thunderbolt { s.insert("data") }
        if values.speed != measured.speed { s.insert("speed") }
        if values.vendor != measured.vendor { s.insert("vendor") }
        if values.lengthMetres != measured.lengthMetres { s.insert("length") }
        return s
    }

    /// Values to prefill the save sheet from a reading.
    public static func measuredValues(from r: CableResult) -> Values {
        Values(watts: r.watts,
               generation: r.showsData || r.cable != nil ? r.generation : nil,
               thunderbolt: r.thunderbolt,
               speed: r.showsData ? r.shownSpeed : r.ratedSpeed,
               vendor: r.cable?.vendorName,
               lengthMetres: r.cable?.approxLengthMetres)
    }
}

/// CSV import (the prototype's log) and export.
public enum CableCSV {
    public static let header = "number,tie,watts,data,thunderbolt,speed_mbps,vendor,length_m,tested"

    public static func export(_ records: [CableRecord]) -> String {
        let iso = ISO8601DateFormatter()
        var lines = [header]
        for r in records.sorted(by: { $0.number < $1.number }) {
            let v = r.values
            let fields: [String] = [
                String(r.number), r.tie?.rawValue ?? "", v.watts.map(String.init) ?? "",
                v.generation?.name ?? "", v.thunderbolt ? "yes" : "no",
                v.speed.map { DataSpeed.trim($0.bitsPerSecond / 1e6) } ?? "",
                v.vendor ?? "", v.lengthMetres.map { DataSpeed.trim($0) } ?? "", iso.string(from: r.tested),
            ]
            lines.append(fields.map(quote).joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func quote(_ s: String) -> String {
        s.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" }) ? "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : s
    }

    /// Imports the prototype log (`id,date,power,data,max_volts,max_amps_at_20v,watts,link_speed,notes`).
    public static func importPrototypeLog(_ text: String) -> [CableRecord] {
        let rows = parse(text)
        guard let head = rows.first else { return [] }
        func col(_ name: String) -> Int? { head.firstIndex(of: name) }
        guard let idC = col("id"), let powerC = col("power") else { return [] }
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"; df.locale = Locale(identifier: "en_US_POSIX")
        return rows.dropFirst().compactMap { row in
            func at(_ i: Int?) -> String { i.flatMap { $0 < row.count ? row[$0] : nil } ?? "" }
            guard let number = Int(at(idC)) else { return nil }
            let watts = CableCSV.watts(fromPrototypeLabel: at(powerC))
            let data = at(col("data")).uppercased()
            let speed = DataSpeed.parse(description: at(col("link_speed")))
            var gen: DataGeneration? = nil
            var tb = false
            switch data {
            case "TB": gen = .usb4; tb = true
            case "USB2": gen = .usb2
            case "USB3": gen = .usb3
            case let d where d.hasSuffix("G"): gen = .usb4; tb = true
            default: gen = nil
            }
            let values = CableRecord.Values(watts: watts, generation: gen, thunderbolt: tb, speed: speed)
            return CableRecord(number: number, tested: df.date(from: at(col("date"))) ?? Date(), values: values)
        }
    }

    /// "240W" -> 240, "<=60W? (max 15V)" -> 60, "unknown" -> nil.
    static func watts(fromPrototypeLabel label: String) -> Int? {
        let t = label.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("<=60W") { return 60 }
        guard let re = try? NSRegularExpression(pattern: #"^(\d+)\s*W"#),
              let m = re.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)),
              let r = Range(m.range(at: 1), in: t) else { return nil }
        return Int(t[r])
    }

    /// Minimal RFC 4180 parser.
    static func parse(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var it = Array(text).makeIterator()
        var pending: Character? = nil
        while let c = pending ?? it.next() {
            pending = nil
            if inQuotes {
                if c == "\"" {
                    if let n = it.next() {
                        if n == "\"" { field.append("\"") } else { inQuotes = false; pending = n }
                    } else { inQuotes = false }
                } else { field.append(c) }
            } else {
                switch c {
                case "\"": inQuotes = true
                case ",": row.append(field); field = ""
                case "\n", "\r\n": row.append(field); field = ""; rows.append(row); row = []
                case "\r": break
                default: field.append(c)
                }
            }
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        return rows.filter { !($0.count == 1 && $0[0].isEmpty) }
    }
}
