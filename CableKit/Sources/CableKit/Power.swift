import Foundation

/// One fixed-voltage offer from a USB-PD charger, as macOS lists it in `UsbHvcMenu`.
public struct PowerOffer: Codable, Hashable, Sendable {
    public var millivolts: Int
    public var milliamps: Int
    public init(millivolts: Int, milliamps: Int) { self.millivolts = millivolts; self.milliamps = milliamps }

    public var volts: Double { Double(millivolts) / 1000 }
    public var amps: Double { Double(milliamps) / 1000 }
}

/// What a charger connected to this Mac offers. The charger checks the cable's chip before it offers
/// 5 A or 28 V, so the offer list rates the cable even when the Mac cannot read the chip itself.
public struct ChargerInfo: Codable, Hashable, Sendable {
    public var name: String?
    public var offers: [PowerOffer]
    public var negotiatedWatts: Int?

    public init(name: String?, offers: [PowerOffer], negotiatedWatts: Int?) {
        self.name = name; self.offers = offers.filter { $0.millivolts > 0 && $0.millivolts < 65535 && $0.milliamps > 0 && $0.milliamps < 65535 }
        self.negotiatedWatts = negotiatedWatts
    }

    /// Reads `AdapterDetails` from `AppleSmartBattery`.
    public init?(adapterDetails d: [String: Any]) {
        let menu = (d["UsbHvcMenu"] as? [[String: Any]]) ?? []
        let offers = menu.map {
            PowerOffer(millivolts: ($0["MaxVoltage"] as? Int) ?? 0, milliamps: ($0["MaxCurrent"] as? Int) ?? 0)
        }
        let name = ((d["Name"] as? String) ?? (d["Description"] as? String)).map(DisplayName.tidy)
        self.init(name: name, offers: offers, negotiatedWatts: d["Watts"] as? Int)
        if self.offers.isEmpty && negotiatedWatts == nil { return nil }
    }

    public var maxOffer: PowerOffer? { offers.max { Double($0.millivolts * $0.milliamps) < Double($1.millivolts * $1.milliamps) } }
    public var maxWatts: Int { Int((maxOffer.map { $0.volts * $0.amps } ?? 0).rounded()) }

    /// The cable tier this charger's offers prove. Never higher than the charger can do.
    public var cableWatts: Int? {
        let maxV = offers.map(\.millivolts).max() ?? 0
        let amps20 = offers.filter { $0.millivolts == 20000 }.map(\.milliamps).max() ?? 0
        if maxV > 20000 || (negotiatedWatts ?? 0) > 100 { return 240 }
        if amps20 >= 5000 { return 100 }
        if amps20 >= 3000 || !offers.isEmpty { return 60 }
        return nil
    }

    /// "28 V × 5 A · 140 W"
    public var maxDescription: String? {
        guard let o = maxOffer else { return nil }
        return "\(DataSpeed.trim(o.volts)) V × \(DataSpeed.trim(o.amps)) A · \(maxWatts) W"
    }

    /// "5 V · 9 V · 15 V · 20 V · 28 V"
    public var offersDescription: String {
        offers.map(\.millivolts).sorted().map { "\(DataSpeed.trim(Double($0) / 1000)) V" }.joined(separator: " · ")
    }
}
