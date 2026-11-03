import Foundation
import ScooterCore
import Testing

struct RideExportTests {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    private func ride(owner: String = "iPhone") -> Ride {
        var ride = Ride(owner: owner, startedAt: start)
        for (index, speed) in [2.0, 3.0, 3.0, 5.0, -1.0].enumerated() {
            let time = start.addingTimeInterval(Double(index * 5))
            _ = ride.append(LocationSample(latitude: 40 + Double(index) * 0.0001, longitude: -73,
                                           timestamp: time, accuracy: 5, speed: speed), receivedAt: time)
        }
        let afterGap = start.addingTimeInterval(50)
        _ = ride.append(LocationSample(latitude: 40.0005, longitude: -73, timestamp: afterGap, accuracy: 5, speed: 2),
                        receivedAt: afterGap)
        let final = start.addingTimeInterval(55)
        _ = ride.append(LocationSample(latitude: 40.0006, longitude: -73, timestamp: final, accuracy: 5, speed: 2),
                        receivedAt: final)
        ride.end(at: start.addingTimeInterval(60))
        return ride
    }

    @Test func jsonIsPortableAndExcludesActiveRides() throws {
        struct Export: Decodable {
            let schemaVersion: Int
            let distanceUnit: String
            let speedUnit: String
            let rides: [Ride]
        }
        let completed = ride()
        let active = Ride(owner: "Apple Watch", startedAt: start)
        let data = try RideExport.json([active, completed], exportedAt: start)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Export.self, from: data)
        #expect(decoded.schemaVersion == 1)
        #expect(decoded.distanceUnit == "meters")
        #expect(decoded.speedUnit == "meters per second")
        #expect(decoded.rides == [completed])
        #expect(String(decoding: data, as: UTF8.self).contains("2023-11-14T22:13:20Z"))
    }

    @Test func gpxContainsAllTracksSpeedsAndSeparatedGaps() throws {
        let rides = [ride(owner: "Phone & <Watch>"), ride(owner: "Apple Watch")]
        let xml = RideExport.gpx(rides, exportedAt: start)
        let document = try XMLDocument(xmlString: xml)
        let tracks = try document.nodes(forXPath: "//*[local-name()='trk']")
        let segments = try document.nodes(forXPath: "//*[local-name()='trkseg']")
        let points = try document.nodes(forXPath: "//*[local-name()='trkpt']")
        let speeds = try document.nodes(forXPath: "//*[local-name()='speed']")
        #expect(tracks.count == 2)
        #expect(segments.count == 4)
        #expect(points.count == 14)
        #expect(speeds.count == 12, "Unknown speeds are omitted rather than exported as negative speed")
        #expect(xml.contains("Phone &amp; &lt;Watch&gt;"))
        #expect(xml.contains("<scooterlog:speed>3.0</scooterlog:speed>"))
        #expect(xml.contains(#"xmlns="http://www.topografix.com/GPX/1/1""#))
    }

    @Test func speedBandsHaveFixedMPHBoundariesAndUnknownSpeed() {
        func speed(_ mph: Double) -> Double { mph * RideUnits.metersPerMile / 3600 }
        #expect(RideSpeedBand(speed: speed(0)) == .slow)
        #expect(RideSpeedBand(speed: speed(4.99)) == .slow)
        #expect(RideSpeedBand(speed: speed(5)) == .cruising)
        #expect(RideSpeedBand(speed: speed(10)) == .brisk)
        #expect(RideSpeedBand(speed: speed(15)) == .fast)
        #expect(RideSpeedBand(speed: -1) == .unknown)
        #expect(RideSpeedBand(speed: .nan) == .unknown)
    }

    @Test func speedMapGroupsAdjacentColoursButDoesNotBridgeGPSGaps() {
        let ride = ride()
        #expect(ride.routeSegments.map(\.count) == [5, 2])
        #expect(ride.speedSegments.map(\.band) == [.cruising, .brisk, .unknown, .slow])
        #expect(ride.speedSegments.map { $0.samples.count } == [3, 2, 2, 2])
        #expect(ride.speedSegments.allSatisfy { segment in
            zip(segment.samples, segment.samples.dropFirst()).allSatisfy {
                $1.timestamp.timeIntervalSince($0.timestamp) <= 15
            }
        })
    }

    @Test func exportWritesBothFormats() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let urls = try RideExport.write([ride()], to: directory)
        #expect(urls.map(\.pathExtension) == ["json", "gpx"])
        #expect(try Data(contentsOf: urls[0]).count > 0)
        #expect(try XMLDocument(contentsOf: urls[1]).rootElement()?.name == "gpx")
    }
}
