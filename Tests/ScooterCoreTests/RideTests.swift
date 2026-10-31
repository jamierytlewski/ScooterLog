import Foundation
import Testing
@testable import ScooterCore

struct RideTests {
    let start = Date(timeIntervalSince1970: 1_000)

    func point(_ seconds: Double, meters: Double = 0, speed: Double = 0, accuracy: Double = 5) -> LocationSample {
        LocationSample(latitude: meters / 111_195, longitude: 0,
                       timestamp: start.addingTimeInterval(seconds), accuracy: accuracy, speed: speed)
    }

    @Test func movingStoppedAndElapsed() {
        var ride = Ride(owner: "phone", startedAt: start)
        for sample in [point(0), point(10, meters: 40, speed: 4), point(20, meters: 80, speed: 4),
                       point(30, meters: 81), point(40, meters: 80)] {
            let accepted = ride.append(sample, receivedAt: sample.timestamp)
            #expect(accepted)
        }
        ride.end(at: start.addingTimeInterval(50))
        #expect(abs(ride.distance - 80) < 0.1)
        #expect(ride.movingDuration == 20)
        #expect(ride.stoppedDuration == 20)
        #expect(ride.elapsed(at: start) == 50)
        #expect(ride.unknownDuration(at: start) == 10)
        #expect(abs(ride.averageSpeed(at: start) - 1.6) < 0.01)
        #expect(abs(ride.movingAverageSpeed - 4) < 0.01)
    }

    @Test func rejectsBadSamplesAndJumps() {
        var ride = Ride(owner: "watch", startedAt: start)
        let accepted = ride.append(point(0), receivedAt: start)
        let duplicate = ride.append(point(0), receivedAt: start)
        let beforeStart = ride.append(point(-1), receivedAt: start)
        let inaccurate = ride.append(point(1, accuracy: 80), receivedAt: start.addingTimeInterval(1))
        let jump = ride.append(point(1, meters: 100), receivedAt: start.addingTimeInterval(1))
        let stale = ride.append(point(1), receivedAt: start.addingTimeInterval(30))
        #expect(accepted)
        #expect(!duplicate && !beforeStart && !inaccurate && !jump && !stale)
        #expect(ride.samples.count == 1)
    }

    @Test func gapsAreUnknownAndJitterDoesNotAddDistance() {
        var ride = Ride(owner: "phone", startedAt: start)
        for sample in [point(0), point(5, meters: 2), point(10, meters: -2), point(50, meters: 90, speed: 3)] {
            let accepted = ride.append(sample, receivedAt: sample.timestamp)
            #expect(accepted)
        }
        #expect(ride.distance == 0)
        #expect(ride.stoppedDuration == 10)
        #expect(ride.unknownDuration(at: start.addingTimeInterval(50)) == 40)
    }

    @Test func hysteresisAndUnknownSpeed() {
        var ride = Ride(owner: "phone", startedAt: start)
        for sample in [point(0), point(5, meters: 10, speed: 2),
                       point(10, meters: 15, speed: 1), point(15, meters: 17, speed: 0.4),
                       point(20, meters: 18, speed: 0.3), point(25, meters: 20, speed: -1)] {
            let accepted = ride.append(sample, receivedAt: sample.timestamp)
            #expect(accepted)
        }
        #expect(ride.movingDuration == 10)
        #expect(ride.stoppedDuration == 10)
        #expect(ride.unknownDuration(at: start.addingTimeInterval(25)) == 5)
        #expect(ride.currentSpeed(at: start.addingTimeInterval(40)) == nil)
        #expect(ride.currentSpeed(at: start.addingTimeInterval(25)) == nil)
    }

    @Test func duplicateStartsFinishesAndImports() {
        var archive = RideArchive()
        let first = archive.start(owner: "phone", at: start)
        let duplicate = archive.start(owner: "phone", at: start.addingTimeInterval(10))
        #expect(duplicate.id == first.id)
        let ended = archive.finish(at: start.addingTimeInterval(20))!
        archive.importCompleted(ended)
        let secondFinish = archive.finish(at: start)
        #expect(secondFinish == nil)
        #expect(archive.completed.count == 1)
        #expect(archive.active == nil)
    }

    @Test func zeroDurationAndRoundTrip() throws {
        let ride = Ride(owner: "phone", startedAt: start)
        #expect(ride.averageSpeed(at: start) == 0)
        #expect(ride.movingAverageSpeed == 0)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("rides.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let archive = RideArchive(active: ride)
        try RideDisk.save(archive, to: url)
        #expect(try RideDisk.load(from: url) == archive)
        try Data("invalid".utf8).write(to: url)
        #expect(throws: (any Error).self) { try RideDisk.load(from: url) }
    }

    @Test func sustainedSlowMovementAndBriefSpeedDip() {
        var ride = Ride(owner: "phone", startedAt: start)
        for sample in [point(0), point(1, meters: 2, speed: 2), point(2, meters: 3, speed: 1),
                       point(3, meters: 4, speed: 0.2), point(4, meters: 5, speed: 1),
                       point(5, meters: 6, speed: 1)] {
            let accepted = ride.append(sample, receivedAt: sample.timestamp)
            #expect(accepted)
        }

        #expect(abs(ride.distance - 6) < 0.01)
        #expect(ride.movingDuration == 5)
        #expect(ride.stoppedDuration == 0)
    }

    @Test func separateCheckpointsAndCrashRecovery() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = RideRepository(directory: directory)
        var ride = Ride(owner: "watch", startedAt: start)
        try repository.checkpoint(ride)
        #expect(try repository.load().active == ride)
        ride.end(at: start.addingTimeInterval(10))
        try repository.saveCompleted(ride)
        let recovered = try repository.load()
        #expect(recovered.active == nil)
        #expect(recovered.completed == [ride])
        try repository.checkpoint(nil)
        #expect(try repository.load() == recovered)
    }

    @Test func milesAndMphAreConsistent() {
        #expect(RideUnits.distance(1_609.344) == "1.00 mi")
        #expect(RideUnits.speed(1_609.344 / 3600) == "1.0 mph")
        #expect(RideUnits.speed(nil) == "-- mph")
    }

    @Test func finishedRideRejectsFurtherSamples() {
        var ride = Ride(owner: "phone", startedAt: start)
        ride.end(at: start.addingTimeInterval(10))
        let accepted = ride.append(point(11, meters: 20, speed: 2), receivedAt: start.addingTimeInterval(11))
        ride.end(at: start.addingTimeInterval(20))
        #expect(!accepted)
        #expect(ride.elapsed(at: start.addingTimeInterval(30)) == 10)
    }

    @Test func confirmedStationaryPauseVersusUnknownGap() {
        var confirmed = Ride(owner: "watch", startedAt: start)
        var unknown = Ride(owner: "phone", startedAt: start)
        _ = confirmed.append(point(0), receivedAt: start)
        _ = unknown.append(point(0), receivedAt: start)
        confirmed.confirmStationary(at: start)
        #expect(confirmed.stoppedTime(at: start.addingTimeInterval(60)) == 60)
        #expect(confirmed.unknownDuration(at: start.addingTimeInterval(60)) == 0)
        _ = confirmed.append(point(60, speed: 2), receivedAt: start.addingTimeInterval(60))
        _ = unknown.append(point(60, speed: 2), receivedAt: start.addingTimeInterval(60))
        confirmed.end(at: start.addingTimeInterval(60))
        unknown.end(at: start.addingTimeInterval(60))
        #expect(confirmed.stoppedDuration == 60)
        #expect(unknown.stoppedDuration == 0)
        #expect(unknown.unknownDuration(at: start.addingTimeInterval(60)) == 60)
        #expect(confirmed.distance == 0 && unknown.distance == 0)
    }

    @Test func endingDuringConfirmedPauseAndInterrupting() {
        var ride = Ride(owner: "watch", startedAt: start)
        ride.confirmStationary(at: start)
        ride.end(at: start.addingTimeInterval(60))
        #expect(ride.stoppedDuration == 60)
        #expect(ride.unknownDuration(at: start.addingTimeInterval(100)) == 0)
        var interrupted = Ride(owner: "phone", startedAt: start)
        interrupted.confirmStationary(at: start)
        interrupted.finishStationary(at: start.addingTimeInterval(20))
        interrupted.interrupt(at: start.addingTimeInterval(20))
        interrupted.end(at: start.addingTimeInterval(60))
        #expect(interrupted.stoppedDuration == 20)
        #expect(interrupted.unknownDuration(at: start) == 40)
    }

    @Test func recoveryDoesNotExtendStationaryConfirmation() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = RideRepository(directory: directory)
        var ride = Ride(owner: "watch", startedAt: start)
        ride.confirmStationary(at: start)
        try repository.checkpoint(ride)
        let recovered = try #require(repository.load().active)
        #expect(recovered.stationarySince == nil)
        #expect(recovered.stoppedDuration == 0)
    }

    @Test func shortRecoveryGapDoesNotInventDistanceOrMotion() {
        var ride = Ride(owner: "phone", startedAt: start)
        _ = ride.append(point(0, speed: 2), receivedAt: start)
        ride.interrupt(at: start.addingTimeInterval(3))
        _ = ride.append(point(5, meters: 10, speed: 2), receivedAt: start.addingTimeInterval(5))
        _ = ride.append(point(6, meters: 12, speed: 2), receivedAt: start.addingTimeInterval(6))
        #expect(ride.movingDuration == 1)
        #expect(abs(ride.distance - 2) < 0.01)
        #expect(ride.unknownDuration(at: start.addingTimeInterval(6)) == 5)
    }

    @Test func rejectedResumeFixDoesNotExtendConfirmedStop() {
        var ride = Ride(owner: "watch", startedAt: start)
        _ = ride.append(point(0), receivedAt: start)
        ride.confirmStationary(at: start)
        let resumedAt = start.addingTimeInterval(60)
        // The stream's non-stationary transition precedes location validation.
        ride.finishStationary(at: resumedAt)
        ride.interrupt(at: resumedAt)
        let rejected = ride.append(point(60, meters: 20, speed: 2, accuracy: 80), receivedAt: resumedAt)
        #expect(!rejected)
        #expect(ride.stationarySince == nil)
        #expect(ride.stoppedTime(at: start.addingTimeInterval(120)) == 60)
        #expect(ride.unknownDuration(at: start.addingTimeInterval(120)) == 60)
        let accepted = ride.append(point(120, meters: 100, speed: 2), receivedAt: start.addingTimeInterval(120))
        #expect(accepted)
        ride.end(at: start.addingTimeInterval(120))
        #expect(ride.stoppedDuration == 60)
        #expect(ride.unknownDuration(at: start) == 60)
        #expect(ride.movingDuration == 0)
        #expect(ride.distance == 0)
    }
}
