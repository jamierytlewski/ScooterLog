import Foundation

public struct LocationSample: Codable, Equatable, Sendable {
    public var latitude: Double
    public var longitude: Double
    public var timestamp: Date
    public var accuracy: Double
    public var speed: Double

    public init(latitude: Double, longitude: Double, timestamp: Date, accuracy: Double, speed: Double) {
        self.latitude = latitude
        self.longitude = longitude
        self.timestamp = timestamp
        self.accuracy = accuracy
        self.speed = speed
    }

    public func distance(to other: Self) -> Double {
        let radians = Double.pi / 180
        let p1 = latitude * radians
        let p2 = other.latitude * radians
        let a = pow(sin((p2 - p1) / 2), 2)
            + cos(p1) * cos(p2) * pow(sin((other.longitude - longitude) * radians / 2), 2)
        return 6_371_000 * 2 * asin(sqrt(min(1, max(0, a))))
    }
}

public struct Ride: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let owner: String
    public let startedAt: Date
    public private(set) var endedAt: Date?
    public private(set) var samples: [LocationSample] = []
    public private(set) var distance: Double = 0
    public private(set) var movingDuration: TimeInterval = 0
    public private(set) var stoppedDuration: TimeInterval = 0
    public private(set) var isMoving = false
    public private(set) var stationarySince: Date?
    /// Older recordings do not retain all pause and motion events needed to reproduce aggregates.
    public private(set) var isTrimmedEstimate: Bool?
    private var accountingBoundary: Date?
    private var pendingStopDuration: TimeInterval = 0
    private var pendingStopDistance: Double = 0
    private var pendingStopSamples = 0

    public init(id: UUID = UUID(), owner: String, startedAt: Date) {
        self.id = id
        self.owner = owner
        self.startedAt = startedAt
    }

    public func elapsed(at now: Date) -> TimeInterval {
        max(0, (endedAt ?? now).timeIntervalSince(startedAt))
    }

    public func unknownDuration(at now: Date) -> TimeInterval {
        max(0, elapsed(at: now) - movingDuration - stoppedTime(at: now))
    }

    public func stoppedTime(at now: Date) -> TimeInterval {
        stoppedDuration + (stationarySince.map { max(0, (endedAt ?? now).timeIntervalSince($0)) } ?? 0)
    }

    public mutating func confirmStationary(at date: Date) {
        guard endedAt == nil, stationarySince == nil else { return }
        stoppedDuration += pendingStopDuration
        clearPendingStop()
        isMoving = false
        stationarySince = max(startedAt, date, accountingBoundary ?? startedAt)
    }

    public mutating func finishStationary(at date: Date) {
        guard let since = stationarySince else { return }
        let end = max(since, date)
        stoppedDuration += end.timeIntervalSince(since)
        stationarySince = nil
        accountingBoundary = end
    }

    /// Recovery/cancellation is not evidence that a paused device remained stationary.
    public mutating func interrupt(at date: Date) {
        stationarySince = nil
        accountingBoundary = max(date, accountingBoundary ?? startedAt)
        isMoving = false
        clearPendingStop()
    }

    public func averageSpeed(at now: Date) -> Double {
        let duration = elapsed(at: now)
        return duration > 0 ? distance / duration : 0
    }

    public var movingAverageSpeed: Double {
        movingDuration > 0 ? distance / movingDuration : 0
    }

    public func preview() -> Ride {
        var copy = self
        copy.samples = Array(samples.suffix(1))
        return copy
    }

    public enum TrimError: Error, Equatable {
        case invalidRange, invalidSample
    }

    /// Builds a separate ride, leaving the original immutable for safe companion and cloud sync.
    public func trimmedCopy(from start: Int, through end: Int) throws -> Ride {
        guard endedAt != nil, start >= 0, end < samples.count, start < end else {
            throw TrimError.invalidRange
        }
        let kept = samples[start...end]
        var copy = Ride(owner: owner, startedAt: samples[start].timestamp)
        for sample in kept {
            guard copy.append(sample, receivedAt: sample.timestamp) else { throw TrimError.invalidSample }
        }
        copy.end(at: samples[end].timestamp)
        // Historical motion and interruption boundaries are not present in the saved samples.
        // Keep all time unknown rather than presenting replayed classifications as fact.
        copy.movingDuration = 0
        copy.stoppedDuration = 0
        copy.isMoving = false
        copy.isTrimmedEstimate = true
        return copy
    }

    public func currentSpeed(at now: Date) -> Double? {
        guard endedAt == nil, let sample = samples.last,
              sample.speed >= 0,
              now.timeIntervalSince(sample.timestamp) >= 0,
              now.timeIntervalSince(sample.timestamp) <= 10 else { return nil }
        return max(0, sample.speed)
    }

    /// Thresholds are deliberately conservative for consumer GPS, not traffic-light detection.
    @discardableResult
    public mutating func append(_ sample: LocationSample, receivedAt now: Date) -> Bool {
        guard endedAt == nil,
              sample.latitude.isFinite, sample.longitude.isFinite,
              abs(sample.latitude) <= 90, abs(sample.longitude) <= 180,
              sample.accuracy.isFinite, (0...25).contains(sample.accuracy),
              sample.speed.isFinite, sample.speed <= 20,
              sample.timestamp >= startedAt,
              (-2...10).contains(now.timeIntervalSince(sample.timestamp)) else { return false }
        guard let previous = samples.last else {
            finishStationary(at: sample.timestamp)
            samples.append(sample)
            return true
        }
        let dt = sample.timestamp.timeIntervalSince(previous.timestamp)
        guard dt > 0 else { return false }
        let displacement = previous.distance(to: sample)
        // A physically impossible jump is rejected even when Core Location reports a low speed.
        guard displacement / dt <= 20 else { return false }
        finishStationary(at: sample.timestamp)
        let crossedBoundary = accountingBoundary.map { $0 > previous.timestamp } ?? false
        let interval = crossedBoundary ? 0 : dt
        if dt <= 15 && interval > 0 {
            let speed = max(0, sample.speed)
            // Unknown speed is not evidence that the rider has stopped.
            if sample.speed >= 0, previous.speed >= 0 {
                if isMoving && speed < 0.6 {
                    pendingStopDuration += interval
                    pendingStopDistance += displacement
                    pendingStopSamples += 1
                    if pendingStopSamples >= 2 && pendingStopDuration >= 3 {
                        stoppedDuration += pendingStopDuration
                        isMoving = false
                        clearPendingStop()
                    }
                } else if (isMoving && speed >= 0.6) || speed >= 1.5 {
                    movingDuration += interval + pendingStopDuration
                    distance += displacement + pendingStopDistance
                    clearPendingStop()
                    isMoving = true
                } else {
                    stoppedDuration += interval
                }
            } else {
                clearPendingStop()
                isMoving = false
            }
        } else {
            clearPendingStop()
            isMoving = false
        }
        samples.append(sample)
        return true
    }

    public mutating func end(at date: Date) {
        guard endedAt == nil else { return }
        let end = max(startedAt, date, samples.last?.timestamp ?? startedAt)
        finishStationary(at: end)
        endedAt = end
    }

    private mutating func clearPendingStop() {
        pendingStopDuration = 0
        pendingStopDistance = 0
        pendingStopSamples = 0
    }
}

public struct RideArchive: Codable, Equatable, Sendable {
    public var active: Ride?
    public var completed: [Ride]
    public var recordingRequested: Bool?
    /// Ids of rides the user deleted. Remembered so an older copy arriving from the companion
    /// or iCloud cannot bring a deleted ride back. Persisted separately by `RideRepository`.
    public internal(set) var deleted: Set<UUID> = []

    private enum CodingKeys: String, CodingKey { case active, completed, recordingRequested }

    public init(active: Ride? = nil, completed: [Ride] = [], recordingRequested: Bool? = nil) {
        self.active = active
        self.completed = completed
        self.recordingRequested = recordingRequested
    }

    public func shouldResumeRecording(on owner: String) -> Bool {
        recordingRequested == true && active?.owner == owner && active?.endedAt == nil
    }

    @discardableResult
    public mutating func start(owner: String, at date: Date) -> Ride {
        if let active { return active }
        let ride = Ride(owner: owner, startedAt: date)
        active = ride
        return ride
    }

    public mutating func finish(at date: Date) -> Ride? {
        guard var ride = active else { return nil }
        ride.end(at: date)
        importCompleted(ride)
        active = nil
        recordingRequested = nil
        return ride
    }

    public mutating func importCompleted(_ ride: Ride) {
        guard ride.endedAt != nil, !deleted.contains(ride.id) else { return }
        completed.removeAll { $0.id == ride.id }
        completed.append(ride)
        completed.sort { $0.startedAt > $1.startedAt }
    }

    public func isDeleted(_ id: UUID) -> Bool { deleted.contains(id) }

    /// Removes completed rides and remembers their ids. Ids that are not stored yet are remembered
    /// too, so a ride still in transit from the companion is rejected when it arrives. The active
    /// ride is never deleted; end it instead. Returns the ids that were newly marked deleted.
    @discardableResult
    public mutating func delete(_ ids: Set<UUID>) -> Set<UUID> {
        var removable = ids
        if let activeID = active?.id { removable.remove(activeID) }
        let added = removable.subtracting(deleted)
        completed.removeAll { removable.contains($0.id) }
        deleted.formUnion(added)
        return added
    }
}

public struct RideHistoryPage: Codable, Equatable, Sendable {
    public static let capacity = 64
    public let rideIDs: [UUID]
    public let hasMore: Bool

    public init(rides: [Ride], after: UUID? = nil) {
        var ids = Set(rides.filter { $0.endedAt != nil }.map(\.id))
            .sorted { $0.uuidString < $1.uuidString }
        if let after { ids.removeAll { $0.uuidString <= after.uuidString } }
        rideIDs = Array(ids.prefix(Self.capacity))
        hasMore = ids.count > Self.capacity
    }

    public func isValid(after: UUID? = nil) -> Bool {
        let ids = rideIDs.map(\.uuidString)
        let cursor = after?.uuidString ?? ""
        return ids.count <= Self.capacity && ids == ids.sorted() && Set(ids).count == ids.count
            && ids.allSatisfy { $0 > cursor } && (!hasMore || !ids.isEmpty)
    }
}

public enum RideDisk {
    public static func load(from url: URL) throws -> RideArchive {
        guard FileManager.default.fileExists(atPath: url.path) else { return RideArchive() }
        return try JSONDecoder().decode(RideArchive.self, from: Data(contentsOf: url))
    }

    public static func save(_ archive: RideArchive, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(archive).write(to: url, options: .atomic)
    }
}
