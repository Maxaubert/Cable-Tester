import Foundation

/// One live transport on a port (USB 2, USB 3, CIO = Thunderbolt/USB 4, DisplayPort).
public struct LiveLink: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable { case usb2, usb3, cio, displayPort }
    public var kind: Kind
    public var speed: DataSpeed?
    public var deviceName: String?

    public init(kind: Kind, speed: DataSpeed?, deviceName: String?) {
        self.kind = kind; self.speed = speed; self.deviceName = deviceName
    }
}

/// Everything macOS shows about one USB-C port, parsed from the IORegistry subtree of the port
/// (class `AppleHPMInterfaceType10`, the same shape `ioreg -a -r -c AppleHPMInterfaceType10 -l` prints).
public struct PortState: Codable, Hashable, Sendable {
    public var number: Int
    public var connectionActive: Bool
    public var connectionUUID: String?
    public var transportsActive: [String]
    public var cable: CableIdentity?
    /// A USB-PD partner answered on SOP (a Mac, a charger, a dock).
    public var partnerVendorID: Int?
    public var partnerName: String?
    public var links: [LiveLink]

    public init(number: Int, connectionActive: Bool, connectionUUID: String?, transportsActive: [String],
                cable: CableIdentity?, partnerVendorID: Int?, partnerName: String?, links: [LiveLink]) {
        self.number = number; self.connectionActive = connectionActive; self.connectionUUID = connectionUUID
        self.transportsActive = transportsActive; self.cable = cable; self.partnerVendorID = partnerVendorID
        self.partnerName = partnerName; self.links = links
    }

    public var hasPartner: Bool { partnerVendorID != nil || !links.isEmpty }
    public var isMacPartner: Bool {
        links.contains { $0.kind == .cio } || (partnerVendorID == 0x05AC && partnerName == "Macintosh")
    }

    /// Fastest live data link, if any (DisplayPort ignored).
    public var bestDataLink: LiveLink? {
        links.filter { $0.kind != .displayPort }.max { ($0.speed ?? .mbps(0)) < ($1.speed ?? .mbps(0)) }
    }

    // MARK: Parsing

    /// Parses one port node (a dictionary with `IORegistryEntryChildren`).
    public static func parse(_ node: [String: Any]) -> PortState? {
        guard let number = node["PortNumber"] as? Int ?? (node["IORegistryEntryLocation"] as? String).flatMap(Int.init)
        else { return nil }
        var cable: CableIdentity?
        var partnerVID: Int?
        var links: [LiveLink] = []

        for child in Self.children(node) {
            let cls = child["IOObjectClass"] as? String ?? ""
            let meta = child["Metadata"] as? [String: Any] ?? [:]
            if cls == "IOPortTransportStateCC" {
                for comp in Self.children(child) {
                    let ccls = comp["IOObjectClass"] as? String ?? ""
                    let cmeta = comp["Metadata"] as? [String: Any] ?? [:]
                    if ccls.hasSuffix("SOPp") {
                        cable = CableIdentity.decode(
                            vdos: (cmeta["VDOs"] as? [Data]) ?? [],
                            vendorID: cmeta["Vendor ID"] as? Int ?? 0,
                            productID: cmeta["Product ID"] as? Int ?? 0,
                            productType: cmeta["Product Type"] as? Int ?? 0)
                    } else if ccls.hasSuffix("USBPDSOP") {
                        partnerVID = cmeta["Vendor ID"] as? Int ?? comp["Vendor ID"] as? Int
                    }
                }
            } else if cls.hasPrefix("IOPortTransportState"), child["Active"] as? Bool == true {
                let kind: LiveLink.Kind? = switch cls {
                case "IOPortTransportStateUSB2": .usb2
                case "IOPortTransportStateUSB3": .usb3
                case "IOPortTransportStateCIO": .cio
                case "IOPortTransportStateDisplayPort": .displayPort
                default: nil
                }
                if let kind {
                    let speed = (child["DataRateDescription"] as? String).flatMap(DataSpeed.parse(description:))
                        ?? (child["LinkSpeedDescription"] as? String).flatMap(DataSpeed.parse(description:))
                    let device = meta["Product"] as? String ?? child["Product"] as? String
                    links.append(LiveLink(kind: kind, speed: speed, deviceName: device))
                }
            }
        }
        let active = node["ConnectionActive"] as? Bool ?? false
        return PortState(
            number: number, connectionActive: active,
            connectionUUID: node["ConnectionUUID"] as? String,
            transportsActive: node["TransportsActive"] as? [String] ?? [],
            cable: active ? cable : nil,
            partnerVendorID: active ? partnerVID : nil,
            // SOPMfgString on the port keeps the last partner's name, so only trust it with a live partner.
            partnerName: (active && partnerVID != nil) ? node["SOPMfgString"] as? String : nil,
            links: active ? links : [])
    }

    static func children(_ n: [String: Any]) -> [[String: Any]] {
        n["IORegistryEntryChildren"] as? [[String: Any]] ?? []
    }

    /// Parses the plist `ioreg -a -r -c AppleHPMInterfaceType10 -l` prints (used for test fixtures).
    public static func parseIoregPlist(_ data: Data) throws -> [PortState] {
        let obj = try PropertyListSerialization.propertyList(from: data, format: nil)
        return (obj as? [[String: Any]] ?? []).compactMap(parse)
    }
}
