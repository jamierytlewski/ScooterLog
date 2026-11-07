import Foundation
import ScooterCore
import Testing

struct RideCompanionTests {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func recordingIntentSurvivesCheckpointAndEndWinsOverCrash() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = RideRepository(directory: directory)
        var ride = Ride(owner: "iPhone", startedAt: start)
        try repository.checkpoint(ride, recordingRequested: true)
        var recovered = try repository.load()
        #expect(recovered.recordingRequested == true)
        #expect(recovered.shouldResumeRecording(on: "iPhone"))
        #expect(!recovered.shouldResumeRecording(on: "Apple Watch"))
        #expect(recovered.active?.id == ride.id)
        #expect(recovered.completed.isEmpty)

        try repository.checkpoint(ride, recordingRequested: false)
        #expect(try repository.load().recordingRequested == false)
        try repository.checkpoint(ride, recordingRequested: true)
        ride.end(at: start.addingTimeInterval(30))
        try repository.saveCompleted(ride)
        recovered = try repository.load()
        #expect(recovered.active == nil)
        #expect(recovered.recordingRequested == nil)
        #expect(!recovered.shouldResumeRecording(on: "iPhone"))
        #expect(recovered.completed == [ride])
    }

    @Test func oldCheckpointsStayPaused() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = RideRepository(directory: directory)
        try repository.checkpoint(Ride(owner: "iPhone", startedAt: start))
        #expect(try repository.load().recordingRequested == nil)
    }

    @Test func historyReconciliationPagesAreBoundedCompleteAndPortable() throws {
        var rides: [Ride] = []
        for index in 0..<150 {
            let id = try #require(UUID(uuidString: String(format: "00000000-0000-0000-0000-%012X", index)))
            var ride = Ride(id: id, owner: "Phone", startedAt: start)
            ride.end(at: start.addingTimeInterval(60))
            rides.append(ride)
        }
        let active = Ride(owner: "Phone", startedAt: start)
        let input = Array(rides.reversed()) + [active, rides[0]]
        var cursor: UUID?
        var received: [UUID] = []
        var sizes: [Int] = []
        repeat {
            let page = RideHistoryPage(rides: input, after: cursor)
            #expect(page.isValid(after: cursor))
            #expect(try JSONDecoder().decode(RideHistoryPage.self, from: JSONEncoder().encode(page)) == page)
            #expect(page.rideIDs.count <= RideHistoryPage.capacity)
            received.append(contentsOf: page.rideIDs)
            sizes.append(page.rideIDs.count)
            if !page.hasMore { break }
            guard let last = page.rideIDs.last else {
                Issue.record("A non-final inventory page must contain a cursor")
                return
            }
            cursor = last
        } while true
        #expect(received == rides.map(\.id))
        #expect(sizes == [64, 64, 22])
        #expect(!received.contains(active.id))
        let finalPage = RideHistoryPage(rides: rides, after: rides[149].id)
        #expect(finalPage.rideIDs.isEmpty)
        #expect(!RideHistoryPage(rides: []).hasMore)
    }

    @Test func reconciliationInventoryDoesNotResurrectDeletedRides() throws {
        var ride = Ride(owner: "Phone", startedAt: start)
        ride.end(at: start.addingTimeInterval(60))
        var archive = RideArchive()
        archive.importCompleted(ride)
        #expect(RideHistoryPage(rides: archive.completed).rideIDs == [ride.id])
        archive.delete([ride.id])
        #expect(RideHistoryPage(rides: archive.completed).rideIDs.isEmpty)
        archive.importCompleted(ride)
        #expect(RideHistoryPage(rides: archive.completed).rideIDs.isEmpty)
    }

    @Test func malformedHistoryPagesCannotLoopOrSkipBehindTheCursor() throws {
        let low = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let high = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
        func page(_ ids: [UUID], hasMore: Bool = false) throws -> RideHistoryPage {
            let data = try JSONSerialization.data(withJSONObject: [
                "rideIDs": ids.map(\.uuidString), "hasMore": hasMore
            ])
            return try JSONDecoder().decode(RideHistoryPage.self, from: data)
        }
        #expect(try page([low, high]).isValid())
        #expect(try !page([high, low]).isValid())
        #expect(try !page([low, low]).isValid())
        #expect(try !page([], hasMore: true).isValid())
        #expect(try !page([low]).isValid(after: low))
        #expect(try !page([low]).isValid(after: high))
        #expect(try page([high]).isValid(after: low))
        #expect(try !page(Array(repeating: low, count: 65)).isValid())
    }

    @Test func oldSnapshotsDecodeWithoutGuidance() throws {
        let snapshot = PeerSnapshot(ride: Ride(owner: "iPhone", startedAt: start), sentAt: start, recording: true)
        let data = try JSONEncoder().encode(snapshot)
        #expect(!String(decoding: data, as: UTF8.self).contains("guidance"))
        let decoded = try JSONDecoder().decode(PeerSnapshot.self, from: data)
        #expect(decoded.activeGuidance == nil)
        #expect(decoded.ride == snapshot.ride)
        #expect(decoded.recording)
    }

    @Test func guidanceBelongsOnlyToItsActiveRide() throws {
        let ride = Ride(owner: "iPhone", startedAt: start)
        let guidance = RideGuidance(rideID: ride.id, destination: "Park", instruction: "Turn left",
                                    distanceToManeuver: 100, step: 1, stepCount: 3, locationTimestamp: start)
        var snapshot = PeerSnapshot(ride: ride, sentAt: start, recording: true, guidance: guidance)
        let decoded = try JSONDecoder().decode(PeerSnapshot.self, from: JSONEncoder().encode(snapshot))
        #expect(decoded.activeGuidance == guidance)
        #expect(decoded.ride == ride, "Viewing companion guidance never changes ride ownership or ends recording")
        #expect(decoded.recording)
        snapshot.guidance?.rideID = UUID()
        #expect(snapshot.activeGuidance == nil)
        snapshot.guidance = guidance
        snapshot.ride?.end(at: start.addingTimeInterval(30))
        #expect(snapshot.activeGuidance == nil)
        snapshot.ride = nil
        #expect(snapshot.activeGuidance == nil)
    }

    @Test func guidanceFreshnessUsesGPSNotDeliveryTime() {
        let guidance = RideGuidance(rideID: UUID(), destination: "Park", instruction: "Turn left",
                                    step: 1, stepCount: 3, locationTimestamp: start)
        #expect(guidance.hasFreshLocation(at: start.addingTimeInterval(15)))
        #expect(!guidance.hasFreshLocation(at: start.addingTimeInterval(16)))
        #expect(!guidance.hasFreshLocation(at: start.addingTimeInterval(-3)))
        let missing = RideGuidance(rideID: UUID(), destination: "Park", instruction: "Turn left", step: 1, stepCount: 3)
        #expect(!missing.hasFreshLocation(at: start))
    }
}
