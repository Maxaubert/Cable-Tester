import Foundation

/// macOS reports some names in lower case ("pd charger"). Show abbreviations and wattages the way
/// they are printed on the hardware ("PD charger", "65W"); words already in upper or mixed case stay.
public enum DisplayName {
    static let abbreviations: [String: String] = [
        "pd": "PD", "pps": "PPS", "epr": "EPR", "spr": "SPR", "usb": "USB", "usb-c": "USB-C", "usb-a": "USB-A",
        "usb4": "USB4", "ac": "AC", "dc": "DC", "gan": "GaN", "qc": "QC", "pc": "PC", "hdmi": "HDMI",
        "dp": "DP", "ssd": "SSD", "nvme": "NVMe", "hdd": "HDD", "sd": "SD", "tb": "TB", "tb3": "TB3",
        "tb4": "TB4", "tb5": "TB5", "kvm": "KVM", "led": "LED", "lan": "LAN", "hid": "HID", "id": "ID",
    ]

    public static func tidy(_ raw: String) -> String {
        let words = raw.split(separator: " ", omittingEmptySubsequences: false).map { w -> String in
            let word = String(w)
            guard word == word.lowercased() else { return word }  // already has capitals: leave it
            if let fixed = abbreviations[word] { return fixed }
            // "65w", "140w", "2.5gbe" style units
            if let m = word.wholeMatch(of: /(\d+(?:\.\d+)?)(w|kw|v|a|gb|gbe)/) {
                let unit = ["w": "W", "kw": "kW", "v": "V", "a": "A", "gb": "GB", "gbe": "GbE"][String(m.2)]!
                return m.1 + unit
            }
            return word
        }
        var out = words.joined(separator: " ")
        // Capitalise a plain lower-case first word ("charger" -> "Charger"), never "iPad" or "eGPU".
        let firstWord = raw.split(separator: " ").first.map(String.init) ?? ""
        if firstWord == firstWord.lowercased(), let first = out.first, first.isLowercase {
            out = first.uppercased() + out.dropFirst()
        }
        return out
    }
}
