import Foundation
import Testing
@testable import CableKit

func fixture(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "plist", subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
}

func le(_ v: UInt32) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }

@Suite struct EMarkerTests {
    @Test func decodesRealNoNameCable() throws {
        // Real VDOs from the no-name cable, 2026-11-22: 00000018 00000000 00000000 404e0a00.
        let vdos = [Data([0, 0, 0, 0x18]), Data(count: 4), Data(count: 4), Data([0x40, 0x4e, 0x0a, 0x00])]
        let c = try #require(CableIdentity.decode(vdos: vdos, vendorID: 0, productID: 0, productType: 3))
        #expect(c.cableVDO == 0x000A4E40)
        #expect(c.maxCurrentAmps == 5)
        #expect(c.maxVolts == 50)
        #expect(c.eprCapable)
        #expect(c.watts == 240)
        #expect(c.generation == .usb2)
        #expect(c.ratedSpeed == .mbps(480))
        #expect(c.approxLengthMetres == 2)
        #expect(c.vendorName == nil)
        #expect(c.fingerprint == "0000:0000:000a4e40")
    }

    @Test func ratesHundredAndSixtyWattCables() throws {
        // 5 A, 20 V, USB4 Gen3, latency 1
        let v100: UInt32 = (0b10 << 5) | 0b011 | (1 << 13) | (0b10 << 18)
        let c100 = try #require(CableIdentity.decode(vdos: [Data(count: 4), Data(count: 4), Data(count: 4), le(v100)],
                                                     vendorID: 0x05AC, productID: 0x7314, productType: 3))
        #expect(c100.watts == 100)
        #expect(c100.generation == .usb4)
        #expect(c100.ratedSpeed == .gbps(40))
        #expect(c100.vendorName == "Apple")
        let v60: UInt32 = (0b01 << 5) | 0b001
        let c60 = try #require(CableIdentity.decode(vdos: [Data(count: 4), Data(count: 4), Data(count: 4), le(v60)],
                                                    vendorID: 0, productID: 0, productType: 3))
        #expect(c60.watts == 60)
        #expect(c60.generation == .usb3)
        let v80: UInt32 = (0b10 << 5) | 0b100 | (0b11 << 9) | (1 << 17)
        let c80 = try #require(CableIdentity.decode(vdos: [Data(count: 4), Data(count: 4), Data(count: 4), le(v80)],
                                                    vendorID: 0, productID: 0, productType: 3))
        #expect(c80.generation == .usb4v2)
        #expect(c80.watts == 240)
    }

    @Test func rejectsNonCables() {
        #expect(CableIdentity.decode(vdos: [], vendorID: 0, productID: 0, productType: 3) == nil)
        #expect(CableIdentity.decode(vdos: Array(repeating: Data(count: 4), count: 4), vendorID: 0, productID: 0, productType: 2) == nil)
    }
}

@Suite struct PortTests {
    @Test func parsesRealMacMiniGameBudsReading() throws {
        let ports = try PortState.parseIoregPlist(fixture("macmini-gamebuds-240w"))
        let p1 = try #require(ports.first { $0.number == 1 })
        #expect(p1.connectionActive)
        #expect(p1.cable?.watts == 240)
        #expect(p1.partnerVendorID == nil)
        #expect(p1.partnerName == nil) // the stale "Macintosh" must not leak through
        #expect(p1.links.first?.kind == .usb2)
        #expect(p1.links.first?.speed == .mbps(12))
        #expect(p1.links.first?.deviceName == "Arctis GameBuds")

        let r = try #require(CableResult.make(port: p1, charger: nil))
        #expect(r.farEnd == .device("Arctis GameBuds"))
        #expect(r.watts == 240)
        #expect(r.wattsSource == .chip)
        #expect(r.generation == .usb2)
        #expect(!r.thunderbolt)
        #expect(r.liveSpeed == .mbps(12))
        #expect(r.limitNote == "Cable is rated 480 Mb/s. Arctis GameBuds limits it to 12 Mb/s.")

        let p4 = try #require(ports.first { $0.number == 4 })
        #expect(CableResult.make(port: p4, charger: nil) == nil)
    }

    @Test func cableWithNothingAtTheOtherEnd() {
        let p = PortState(number: 1, connectionActive: true, connectionUUID: "x", transportsActive: ["CC"],
                          cable: nil, partnerVendorID: nil, partnerName: nil, links: [])
        let r = CableResult.make(port: p, charger: nil)!
        #expect(r.farEnd == .nothing)
        #expect(r.wattsSource == .estimate)
        #expect(!r.showsData)
    }

    @Test func thunderboltLinkToAMac() {
        let p = PortState(number: 2, connectionActive: true, connectionUUID: "y", transportsActive: ["CC", "CIO"],
                          cable: nil, partnerVendorID: 0x05AC, partnerName: "Macintosh",
                          links: [LiveLink(kind: .cio, speed: .gbps(40), deviceName: nil)])
        let r = CableResult.make(port: p, charger: nil)!
        #expect(r.farEnd == .mac("Mac"))
        #expect(r.thunderbolt)
        #expect(r.generation == .usb4)
        #expect(r.showsData)
        #expect(r.wattsSource == .estimate)

        // Speed not reported yet, plus a tunnelled USB 3 link: still Thunderbolt, still USB 4.
        let q = PortState(number: 2, connectionActive: true, connectionUUID: "y", transportsActive: ["CC", "CIO", "USB3"],
                          cable: nil, partnerVendorID: nil, partnerName: nil,
                          links: [LiveLink(kind: .usb3, speed: .gbps(10), deviceName: "Dock"), LiveLink(kind: .cio, speed: nil, deviceName: nil)])
        let rq = CableResult.make(port: q, charger: nil)!
        #expect(rq.thunderbolt)
        #expect(rq.generation == .usb4)
        #expect(rq.showsData)
    }

    @Test func chargerShowsChipSpeed() throws {
        // Real reading: MacBook Pro on a 100 W charger, no-name 240 W USB 2 cable (2026-11-23).
        let ports = try PortState.parseIoregPlist(fixture("macbook-charger-240w-chip"))
        let p = try #require(ports.first { $0.cable != nil })
        let ch = ChargerInfo(name: "pd charger", offers: [
            .init(millivolts: 5000, milliamps: 3000), .init(millivolts: 20000, milliamps: 5000)], negotiatedWatts: 94)
        let r = try #require(CableResult.make(port: p, charger: ch))
        guard case .charger = r.farEnd else { Issue.record("far end \(r.farEnd)"); return }
        #expect(r.watts == 240)
        #expect(r.wattsSource == .chip)
        #expect(r.showsData)
        #expect(r.dataFromChipOnly)
        #expect(r.generation == .usb2)
        #expect(r.shownSpeed == .mbps(480))
        #expect(r.limitNote == nil)
    }

    @Test func chargerWithoutChipHidesData() {
        let ch = ChargerInfo(name: "Apple 140W", offers: [
            .init(millivolts: 5000, milliamps: 3000), .init(millivolts: 20000, milliamps: 5000),
            .init(millivolts: 28000, milliamps: 5000)], negotiatedWatts: 140)
        let p = PortState(number: 1, connectionActive: true, connectionUUID: "z", transportsActive: ["CC"],
                          cable: nil, partnerVendorID: 0x05AC, partnerName: nil, links: [])
        let r = CableResult.make(port: p, charger: ch)!
        #expect(r.watts == 240)
        #expect(r.wattsSource == .charger)
        #expect(!r.showsData)
        #expect(ch.maxDescription == "28 V × 5 A · 140 W")
        #expect(ch.offersDescription == "5 V · 20 V · 28 V")
    }
}

@Suite struct PowerTests {
    @Test func chargerNamesAreTidied() {
        #expect(DisplayName.tidy("pd charger") == "PD charger")
        #expect(DisplayName.tidy("usb-c pd 65w gan charger") == "USB-C PD 65W GaN charger")
        #expect(DisplayName.tidy("Apple 140W USB-C Power Adapter") == "Apple 140W USB-C Power Adapter")
        #expect(DisplayName.tidy("Arctis GameBuds") == "Arctis GameBuds")
        #expect(DisplayName.tidy("nvme ssd") == "NVMe SSD")
        #expect(DisplayName.tidy("iPad") == "iPad")
        #expect(DisplayName.tidy("iPhone 17 Pro") == "iPhone 17 Pro")
        let c = ChargerInfo(adapterDetails: ["Description": "pd charger", "Watts": 94])
        #expect(c?.name == "PD charger")
    }

    @Test func chargerTiers() {
        func info(_ o: [(Int, Int)], _ w: Int?) -> ChargerInfo {
            ChargerInfo(name: nil, offers: o.map { PowerOffer(millivolts: $0.0, milliamps: $0.1) }, negotiatedWatts: w)
        }
        #expect(info([(5000, 3000), (20000, 5000)], 100).cableWatts == 100)
        #expect(info([(5000, 3000), (20000, 3000)], 60).cableWatts == 60)
        #expect(info([(20000, 5000), (28000, 5000)], 140).cableWatts == 240)
        #expect(info([(65535, 65535), (0, 0)], nil).offers.isEmpty)
    }

    @Test func adapterDetailsParsing() throws {
        let d: [String: Any] = ["Watts": 100, "Name": "USB-C Charger",
                                "UsbHvcMenu": [["MaxVoltage": 20000, "MaxCurrent": 5000], ["MaxVoltage": 65535, "MaxCurrent": 65535]]]
        let c = try #require(ChargerInfo(adapterDetails: d))
        #expect(c.offers.count == 1)
        #expect(c.cableWatts == 100)
    }
}

@Suite struct InputTests {
    @Test(arguments: [("0.13", 0.13), ("0,13", 0.13), ("2", 2.0), ("1.5 m", 1.5), ("2m", 2.0), (" 0.5 ", 0.5)])
    func validLengths(text: String, value: Double) { #expect(Length.parse(text) == value) }

    @Test(arguments: ["two", "0,13m x", "", "0", "11", "1.2.3", "-1", "1e2"])
    func invalidLengths(text: String) { #expect(Length.parse(text) == nil) }

    @Test func speeds() {
        #expect(DataSpeed.parse(description: "12 Mbps (Full Speed)") == .mbps(12))
        #expect(DataSpeed.parse(description: "480 Mbps (High Speed)") == .mbps(480))
        #expect(DataSpeed.parse(description: "40 Gb/s") == .gbps(40))
        #expect(DataSpeed.parse(description: "None") == nil)
        #expect(DataSpeed.parse(typed: "40", unit: .gbps) == .gbps(40))
        #expect(DataSpeed.parse(typed: "0,48", unit: .gbps) == .mbps(480))
        #expect(DataSpeed.parse(typed: "x", unit: .gbps) == nil)
        #expect(DataSpeed.gbps(40).formatted == "40 Gb/s")
        #expect(DataSpeed.mbps(480).formatted == "480 Mb/s")
        #expect(DataSpeed.gbps(2.5).formatted == "2.5 Gb/s")
        #expect(DataSpeed.parse(cell: "40") == .gbps(40))
        #expect(DataSpeed.parse(cell: "40G") == .gbps(40))
        #expect(DataSpeed.parse(cell: "480 Mb/s") == .mbps(480))
        #expect(DataSpeed.parse(cell: "480M") == .mbps(480))
        #expect(DataSpeed.parse(cell: "0,48 Gbps") == .mbps(480))
        #expect(DataSpeed.parse(cell: "fast") == nil)
    }

    @Test func watts() {
        #expect(Watts.parse("240") == 240)
        #expect(Watts.parse("65 W") == 65)
        #expect(Watts.parse("45w") == 45)
        #expect(Watts.parse("0") == nil)
        #expect(Watts.parse("300") == nil)
        #expect(Watts.parse("lots") == nil)
    }

    @Test func labels() {
        #expect(CableLabel.make(number: 7, watts: 240, generation: .usb4) == "#07 240W USB4")
        #expect(CableLabel.make(number: 12, watts: 60, generation: nil) == "#12 60W")
        #expect(CableLabel.make(number: 3, watts: 240, generation: .usb4v2) == "#03 240W USB4v2")
    }
}

@Suite struct LibraryTests {
    @Test func numberingAndModelMatch() {
        var lib = CableLibrary()
        #expect(lib.nextNumber == 1)
        lib.add(CableRecord(number: 3, values: .init(watts: 240), fingerprint: "a"))
        lib.add(CableRecord(number: 5, values: .init(watts: 240), fingerprint: "a"))
        #expect(lib.nextNumber == 6)
        #expect(lib.sameModel(as: "a")?.number == 3)
        #expect(lib.sameModel(as: "b") == nil)
        #expect(lib.sameModel(as: "a", before: .distantPast) == nil)
        // Deleting the highest number never hands it out again.
        lib.delete(id: lib.records.first { $0.number == 5 }!.id)
        #expect(lib.nextNumber == 6)
    }

    @Test func editedFieldsAndRoundTrip() throws {
        var r = CableRecord(number: 1, values: .init(watts: 60, generation: .usb2, speed: .mbps(480)))
        r.values.lengthMetres = 0.13
        r.values.watts = 100
        #expect(r.editedFields == ["watts", "length"])
        var lib = CableLibrary(records: [r])
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("cables-\(UUID()).json")
        try lib.save(to: url)
        guard case .loaded(let back) = CableLibrary.load(from: url) else { Issue.record("not loaded"); return }
        #expect(back.records == lib.records)
        try Data("{broken".utf8).write(to: url)
        guard case .unreadable = CableLibrary.load(from: url) else { Issue.record("damaged file must not load"); return }
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("none-\(UUID()).json")
        guard case .missing = CableLibrary.load(from: missing) else { Issue.record("missing"); return }
        lib.delete(id: r.id)
        #expect(lib.records.isEmpty)
    }

    @Test func importsPrototypeLogAndExports() {
        let log = """
        id,date,power,data,max_volts,max_amps_at_20v,watts,link_speed,notes
        1,2026-11-22,100W,USB2,20.0,5.0,96,USB 2 link only,"blue, braided"
        2,2026-11-22,60W,,20.0,3.0,60,skipped,
        3,2026-11-22,240W,TB,28.0,5.0,140,40 Gb/s,
        4,2026-11-22,<=60W? (max 15V),USB2,15.0,0.0,45,USB 2 link only,
        5,2026-11-22,unknown,,,,,,
        """
        let recs = CableCSV.importPrototypeLog(log)
        #expect(recs.count == 5)
        #expect(recs[3].values.watts == 60)
        #expect(recs[4].values.watts == nil)
        #expect(recs[0].values.watts == 100 && recs[0].values.generation == .usb2)
        #expect(recs[1].values.generation == nil)
        #expect(recs[2].values.thunderbolt && recs[2].values.speed == .gbps(40))
        let csv = CableCSV.export(recs)
        #expect(csv.hasPrefix(CableCSV.header))
        #expect(csv.contains("3,,240,USB 4,yes,40000,"))
    }
}
