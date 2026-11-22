import Foundation

/// A data rate in bits per second, shown as "480 Mb/s" or "40 Gb/s".
public struct DataSpeed: Codable, Hashable, Comparable, Sendable {
    public var bitsPerSecond: Double

    public init(bitsPerSecond: Double) { self.bitsPerSecond = bitsPerSecond }
    public static func mbps(_ v: Double) -> DataSpeed { .init(bitsPerSecond: v * 1e6) }
    public static func gbps(_ v: Double) -> DataSpeed { .init(bitsPerSecond: v * 1e9) }

    public static func < (a: DataSpeed, b: DataSpeed) -> Bool { a.bitsPerSecond < b.bitsPerSecond }

    public enum Unit: String, CaseIterable, Codable, Sendable { case mbps = "Mb/s", gbps = "Gb/s" }

    /// The unit this speed reads best in.
    public var naturalUnit: Unit { bitsPerSecond >= 1e9 ? .gbps : .mbps }

    public func value(in unit: Unit) -> Double {
        unit == .gbps ? bitsPerSecond / 1e9 : bitsPerSecond / 1e6
    }

    public var formatted: String {
        let u = naturalUnit
        return "\(Self.trim(value(in: u))) \(u.rawValue)"
    }

    public static func trim(_ v: Double) -> String {
        if v.rounded() == v { return String(Int(v)) }
        return String(format: "%g", (v * 100).rounded() / 100)
    }

    /// Reads strings like "12 Mbps (Full Speed)", "40 Gb/s", "10Gbps".
    public static func parse(description: String) -> DataSpeed? {
        let pattern = #"([\d]+(?:[.,]\d+)?)\s*([MG])b(?:ps|/s)"#
        guard let re = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let m = re.firstMatch(in: description, range: NSRange(description.startIndex..., in: description)),
              let numR = Range(m.range(at: 1), in: description),
              let unitR = Range(m.range(at: 2), in: description),
              let num = Double(description[numR].replacingOccurrences(of: ",", with: "."))
        else { return nil }
        return description[unitR].uppercased() == "G" ? .gbps(num) : .mbps(num)
    }

    /// Parses what someone types in a table cell: "40", "40G", "40 Gb/s", "480 Mb/s", "480M", "0,48 Gbps".
    /// A bare number means Gb/s.
    public static func parse(cell: String) -> DataSpeed? {
        var t = cell.lowercased().replacingOccurrences(of: " ", with: "")
        var unit = Unit.gbps
        for (suffix, u) in [("gb/s", Unit.gbps), ("gbps", .gbps), ("mb/s", .mbps), ("mbps", .mbps), ("g", .gbps), ("m", .mbps)]
        where t.hasSuffix(suffix) {
            t.removeLast(suffix.count); unit = u; break
        }
        return parse(typed: t, unit: unit)
    }

    /// Parses a typed value plus a unit. Accepts "40", "0,48", "1.5". Range 1 Mb/s to 200 Gb/s.
    public static func parse(typed: String, unit: Unit) -> DataSpeed? {
        let t = typed.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard let v = Double(t), v > 0 else { return nil }
        let s = unit == .gbps ? DataSpeed.gbps(v) : DataSpeed.mbps(v)
        guard s.bitsPerSecond >= 1e6, s.bitsPerSecond <= 200e9 else { return nil }
        return s
    }
}

/// The USB generation a cable or link belongs to. Shown by its USB name, never "TB".
public enum DataGeneration: String, Codable, CaseIterable, Comparable, Sendable {
    case usb2, usb3, usb4, usb4v2

    public var name: String {
        switch self {
        case .usb2: "USB 2"
        case .usb3: "USB 3"
        case .usb4: "USB 4"
        case .usb4v2: "USB 4 v2"
        }
    }

    /// Short form used on labels: "USB2", "USB4v2".
    public var labelName: String { name.replacingOccurrences(of: " ", with: "") }

    public static func < (a: Self, b: Self) -> Bool {
        allCases.firstIndex(of: a)! < allCases.firstIndex(of: b)!
    }

    /// The generation a link at this speed implies.
    public static func from(speed: DataSpeed) -> DataGeneration {
        switch speed.bitsPerSecond {
        case ..<1e9: .usb2
        case ..<40e9: .usb3
        case ..<80e9: .usb4
        default: .usb4v2
        }
    }
}

/// Cable length in metres, typed by the user.
public enum Length {
    public static let range = 0.01...10.0

    /// Accepts "0.13", "0,13", "2", "1.5 m", "2m". Returns nil for anything else or out of range.
    public static func parse(_ text: String) -> Double? {
        var t = text.trimmingCharacters(in: .whitespaces).lowercased()
        if t.hasSuffix("m") { t = String(t.dropLast()).trimmingCharacters(in: .whitespaces) }
        t = t.replacingOccurrences(of: ",", with: ".")
        guard !t.isEmpty, t.allSatisfy({ $0.isNumber || $0 == "." }),
              t.filter({ $0 == "." }).count <= 1,
              let v = Double(t), range.contains(v) else { return nil }
        return v
    }

    public static func format(_ metres: Double) -> String {
        "\(DataSpeed.trim(metres)) m"
    }

    /// Text for an edit field (no unit).
    public static func editText(_ metres: Double?) -> String {
        metres.map { DataSpeed.trim($0) } ?? ""
    }
}
