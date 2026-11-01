import Foundation
import Testing
@testable import ScooterCore

struct RideDeletionTests {
    let start = Date(timeIntervalSince1970: 1_000)

    func completedRide(_ offset: Double) -> Ride {
        var ride = Ride(owner: "phone", startedAt: start.addingTimeInterval(offset))
        ride.end(at: start.addingTimeInterval(offset + 10))
        return ride
    }

    func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    @Test func deletingRemovesTheRideAndBlocksReimport() {
        let keep = completedRide(0)
        let remove = completedRide(100)
        var archive = RideArchive(completed: [remove, keep])
        let added = archive.delete([remove.id])
        #expect(added == [remove.id])
        #expect(archive.completed == [keep])
        #expect(archive.isDeleted(remove.id))
        #expect(!archive.isDeleted(keep.id))

        archive.importCompleted(remove)
        #expect(archive.completed == [keep])
    }

    @Test func batchDeletionKeepsNewestFirstOrder() {
        let rides = [completedRide(0), completedRide(100), completedRide(200), completedRide(300)]
        var archive = RideArchive()
        rides.forEach { archive.importCompleted($0) }
        #expect(archive.completed.map(\.id) == rides.reversed().map(\.id))

        archive.delete([rides[1].id, rides[3].id])
        #expect(archive.completed.map(\.id) == [rides[2].id, rides[0].id])
        #expect(archive.deleted == [rides[1].id, rides[3].id])
    }

    @Test func deletingTwiceIsIdempotentAndUnknownIdsAreRemembered() {
        let ride = completedRide(0)
        var archive = RideArchive(completed: [ride])
        #expect(archive.delete([ride.id]) == [ride.id])
        #expect(archive.delete([ride.id]).isEmpty)

        // A ride still in transit from the companion must not appear after it was deleted elsewhere.
        let inTransit = completedRide(50)
        #expect(archive.delete([inTransit.id]) == [inTransit.id])
        archive.importCompleted(inTransit)
        #expect(archive.completed.isEmpty)
    }

    @Test func activeRideCannotBeDeleted() {
        var archive = RideArchive()
        let active = archive.start(owner: "phone", at: start)
        #expect(archive.delete([active.id]).isEmpty)
        #expect(archive.active?.id == active.id)
        #expect(archive.deleted.isEmpty)

        let finished = archive.finish(at: start.addingTimeInterval(20))
        #expect(finished?.id == active.id)
        #expect(archive.completed.map(\.id) == [active.id])
    }

    @Test func tombstonesAreNotPartOfTheArchiveFormat() throws {
        let ride = completedRide(0)
        var archive = RideArchive(completed: [ride])
        archive.delete([UUID()])
        let data = try JSONEncoder().encode(archive)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["completed"] != nil)
        #expect(object["deleted"] == nil)
        let decoded = try JSONDecoder().decode(RideArchive.self, from: data)
        #expect(decoded.completed == [ride])
        #expect(decoded.deleted.isEmpty)
    }

    @Test func deletionsPersistAcrossLoads() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = RideRepository(directory: directory)
        let keep = completedRide(0)
        let remove = completedRide(100)
        try repository.saveCompleted(keep)
        try repository.saveCompleted(remove)
        #expect(try repository.load().deleted.isEmpty)

        try repository.saveDeleted([remove.id])
        try repository.removeCompleted([remove.id])
        let loaded = try repository.load()
        #expect(loaded.completed == [keep])
        #expect(loaded.deleted == [remove.id])

        // Later deletions add to earlier ones instead of replacing them.
        try repository.saveDeleted([keep.id])
        #expect(try repository.load().deleted == [keep.id, remove.id])
    }

    @Test func interruptedDeleteIsFinishedOnNextLoad() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = RideRepository(directory: directory)
        let ride = completedRide(0)
        try repository.saveCompleted(ride)
        let file = directory.appendingPathComponent("History").appendingPathComponent("\(ride.id.uuidString).json")
        #expect(FileManager.default.fileExists(atPath: file.path))

        // Simulates a crash after the tombstone was written but before the ride file was removed.
        try repository.saveDeleted([ride.id])
        let loaded = try repository.load()
        #expect(loaded.completed.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test func staleCheckpointOfDeletedRideIsDropped() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = RideRepository(directory: directory)
        // Ending a ride saves it first and clears the checkpoint second, so the checkpoint can outlive it.
        let ride = Ride(owner: "phone", startedAt: start)
        try repository.checkpoint(ride)
        #expect(try repository.load().active?.id == ride.id)

        try repository.saveDeleted([ride.id])
        #expect(try repository.load().active == nil)
    }

    @Test func removingFilesToleratesMissingOnesAndLeavesOthersAlone() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = RideRepository(directory: directory)
        let keep = completedRide(0)
        let remove = completedRide(100)
        try repository.saveCompleted(keep)
        try repository.saveCompleted(remove)

        try repository.removeCompleted([remove.id, UUID()])
        #expect(try repository.load().completed == [keep])
        try repository.removeCompleted([remove.id])
    }

    @Test func corruptTombstoneFileFailsLoudlyAndIsNotOverwritten() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = RideRepository(directory: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("deleted-rides.json")
        try Data("invalid".utf8).write(to: file)

        #expect(throws: (any Error).self) { try repository.load() }
        #expect(throws: (any Error).self) { try repository.saveDeleted([UUID()]) }
        #expect(try Data(contentsOf: file) == Data("invalid".utf8))
    }
}
