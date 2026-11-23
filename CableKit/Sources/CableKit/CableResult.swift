import Foundation

/// What is on the other end of the cable.
public enum FarEnd: Hashable, Sendable {
    case nothing                 // cable plugged in, other end free
    case mac(String)
    case charger(ChargerInfo)
    case device(String)
    case unknown

    public var name: String? {
        switch self {
        case .mac(let n), .device(let n): n
        case .charger(let c): c.name ?? "Charger"
        default: nil
        }
    }
}

/// Where the wattage came from, so the UI can say why.
public enum WattsSource: Hashable, Sendable { case chip, charger, estimate }

/// The answer the app shows for the cable that is plugged in right now.
public struct CableResult: Hashable, Sendable {
    public var port: Int
    public var farEnd: FarEnd
    public var cable: CableIdentity?
    public var watts: Int
    public var wattsSource: WattsSource
    /// nil when there is no way to know (no chip and no data link).
    public var generation: DataGeneration?
    public var thunderbolt: Bool
    public var ratedSpeed: DataSpeed?
    public var liveSpeed: DataSpeed?
    public var liveLink: LiveLink?

    /// Show the data line in the result? On a charger there is no data link, but the cable's chip
    /// still states its rated speed (verified 2026-11-22, MacBook on a charger), so show that.
    public var showsData: Bool {
        if case .charger = farEnd { return cable != nil }
        if case .nothing = farEnd { return cable != nil }
        return generation != nil
    }

    /// The speed shown in the result: the live link when there is one, otherwise the chip's rating.
    public var shownSpeed: DataSpeed? { liveSpeed ?? ratedSpeed }

    /// The data line comes from the chip's rating only, with no live link to confirm it.
    public var dataFromChipOnly: Bool { showsData && liveSpeed == nil && !thunderbolt && cable != nil }

    /// "Limited to 40 Gb/s by Mac mini", when the live link is slower than the cable.
    public var limitNote: String? {
        guard let live = liveSpeed, let rated = ratedSpeed, live < rated else { return nil }
        let who = farEnd.name ?? "the other device"
        return "Cable is rated \(rated.formatted). \(who) limits it to \(live.formatted)."
    }

    public static func make(port p: PortState, charger: ChargerInfo?) -> CableResult? {
        guard p.connectionActive else { return nil }
        let link = p.bestDataLink
        let farEnd: FarEnd
        if p.isMacPartner {
            farEnd = .mac(link?.deviceName.flatMap { $0 == "Macintosh" ? nil : $0 } ?? "Mac")
        } else if let charger, p.partnerVendorID != nil, link == nil {
            farEnd = .charger(charger)
        } else if let name = link?.deviceName {
            farEnd = .device(name)
        } else if p.hasPartner {
            farEnd = .unknown
        } else {
            farEnd = .nothing
        }

        var watts = 60
        var source = WattsSource.estimate
        if let c = p.cable {
            watts = c.watts; source = .chip
        } else if case .charger(let ch) = farEnd, let w = ch.cableWatts {
            watts = w; source = .charger
        }

        let liveSpeed = link?.speed
        var generation = p.cable?.generation
        var liveGen: DataGeneration? = liveSpeed.map(DataGeneration.from(speed:))
        if p.hasThunderboltLink { liveGen = max(.usb4, liveGen ?? .usb4) }
        if let liveGen {
            if generation == nil || p.cable == nil { generation = liveGen }
            // A real link proves at least this generation, even when the chip says less.
            if let g = generation, liveGen > g { generation = liveGen }
        }

        return CableResult(
            port: p.number, farEnd: farEnd, cable: p.cable, watts: watts, wattsSource: source,
            generation: generation, thunderbolt: p.hasThunderboltLink,
            ratedSpeed: p.cable?.ratedSpeed, liveSpeed: liveSpeed, liveLink: link)
    }
}

/// The label written on the cable: "#07 240W USB4".
public enum CableLabel {
    public static func make(number: Int, watts: Int?, generation: DataGeneration?) -> String {
        var parts = [String(format: "#%02d", number)]
        if let watts { parts.append("\(watts)W") }
        if let generation { parts.append(generation.labelName) }
        return parts.joined(separator: " ")
    }
}
