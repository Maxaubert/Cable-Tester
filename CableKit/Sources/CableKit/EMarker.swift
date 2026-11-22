import Foundation

/// What a cable's e-marker chip says about itself (USB PD Discover Identity on SOP').
/// See docs/emarker.md for the bit layout.
public struct CableIdentity: Codable, Hashable, Sendable {
    public var vendorID: Int
    public var productID: Int
    public var isActive: Bool
    public var maxCurrentAmps: Int        // 3 or 5
    public var maxVolts: Int              // 20, 30, 40 or 50
    public var eprCapable: Bool
    public var speedCode: Int             // bits 2:0 of the Cable VDO
    public var latencyCode: Int           // bits 16:13
    public var cableVDO: UInt32

    public init(vendorID: Int, productID: Int, isActive: Bool, maxCurrentAmps: Int, maxVolts: Int,
                eprCapable: Bool, speedCode: Int, latencyCode: Int, cableVDO: UInt32) {
        self.vendorID = vendorID; self.productID = productID; self.isActive = isActive
        self.maxCurrentAmps = maxCurrentAmps; self.maxVolts = maxVolts; self.eprCapable = eprCapable
        self.speedCode = speedCode; self.latencyCode = latencyCode; self.cableVDO = cableVDO
    }

    /// Decodes the VDO list exactly as macOS stores it (4-byte little-endian blobs).
    /// `productType` 3 = passive cable, 4 = active cable.
    public static func decode(vdos: [Data], vendorID: Int, productID: Int, productType: Int) -> CableIdentity? {
        guard productType == 3 || productType == 4, vdos.count >= 4 else { return nil }
        let cable = Self.u32(vdos[3])
        let current: Int = switch (cable >> 5) & 0b11 { case 0b10: 5; default: 3 }
        let volts: Int = switch (cable >> 9) & 0b11 { case 0b01: 30; case 0b10: 40; case 0b11: 50; default: 20 }
        return CableIdentity(
            vendorID: vendorID, productID: productID, isActive: productType == 4,
            maxCurrentAmps: current, maxVolts: volts,
            eprCapable: (cable >> 17) & 1 == 1,
            speedCode: Int(cable & 0b111),
            latencyCode: Int((cable >> 13) & 0b1111),
            cableVDO: cable)
    }

    static func u32(_ d: Data) -> UInt32 {
        var v: UInt32 = 0
        for (i, b) in d.prefix(4).enumerated() { v |= UInt32(b) << (8 * i) }
        return v
    }

    /// 240 W for EPR cables, 100 W for 5 A, otherwise 60 W.
    public var watts: Int {
        if eprCapable && maxVolts >= 50 && maxCurrentAmps == 5 { return 240 }
        return maxCurrentAmps == 5 ? 100 : 60
    }

    public var generation: DataGeneration {
        switch speedCode {
        case 0b000: .usb2
        case 0b001, 0b010: .usb3
        case 0b011: .usb4
        default: .usb4v2
        }
    }

    /// The fastest link the cable is built for.
    public var ratedSpeed: DataSpeed {
        switch speedCode {
        case 0b000: .mbps(480)
        case 0b001: .gbps(5)
        case 0b010: .gbps(20)
        case 0b011: .gbps(40)
        default: .gbps(80)
        }
    }

    /// Rough length from the signal latency field (passive cables: about 1 m per 10 ns step).
    public var approxLengthMetres: Double? {
        guard !isActive else { return nil }
        switch latencyCode {
        case 1: return 1
        case 2: return 2
        case 3: return 3
        case 4: return 4
        case 5: return 5
        case 6: return 6
        case 7: return 7
        default: return nil
        }
    }

    public var vendorName: String? { VendorNames.name(for: vendorID) }

    /// Identifies a cable model (not a single cable: there is no serial number).
    public var fingerprint: String {
        String(format: "%04x:%04x:%08x", vendorID, productID, cableVDO)
    }
}

/// USB-IF vendor IDs that show up on cables. Unknown IDs stay as hex.
public enum VendorNames {
    static let table: [Int: String] = [
        0x05AC: "Apple", 0x291A: "Anker", 0x2B1D: "UGREEN", 0x050D: "Belkin", 0x2109: "VIA Labs",
        0x1D5C: "Fresco", 0x04E8: "Samsung", 0x18D1: "Google", 0x8087: "Intel", 0x2E8A: "Raspberry Pi",
        0x0BDA: "Realtek", 0x17EF: "Lenovo", 0x413C: "Dell", 0x03F0: "HP", 0x2D01: "Baseus",
        0x1532: "Razer", 0x1E7D: "Roccat", 0x0B05: "ASUS", 0x2717: "Xiaomi", 0x05E3: "Genesys",
    ]

    public static func name(for id: Int) -> String? {
        guard id != 0 else { return nil }
        return table[id]
    }
}
