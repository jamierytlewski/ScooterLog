import Foundation

public struct RideGuidance: Codable, Equatable, Sendable {
    public var rideID: UUID
    public var destination: String
    public var instruction: String
    public var nextInstruction: String?
    public var distanceToManeuver: Double?
    public var step: Int
    public var stepCount: Int
    public var locationTimestamp: Date?
    public var error: String?
    public var isRerouting: Bool
    public var hasArrived: Bool

    public init(rideID: UUID, destination: String, instruction: String, nextInstruction: String? = nil,
                distanceToManeuver: Double? = nil, step: Int, stepCount: Int, locationTimestamp: Date? = nil,
                error: String? = nil, isRerouting: Bool = false, hasArrived: Bool = false) {
        self.rideID = rideID
        self.destination = destination
        self.instruction = instruction
        self.nextInstruction = nextInstruction
        self.distanceToManeuver = distanceToManeuver
        self.step = step
        self.stepCount = stepCount
        self.locationTimestamp = locationTimestamp
        self.error = error
        self.isRerouting = isRerouting
        self.hasArrived = hasArrived
    }

    public func hasFreshLocation(at now: Date) -> Bool {
        guard let locationTimestamp else { return false }
        return (-2...15).contains(now.timeIntervalSince(locationTimestamp))
    }
}

public struct PeerSnapshot: Codable, Sendable {
    public var ride: Ride?
    public var sentAt: Date
    public var recording: Bool
    public var guidance: RideGuidance?

    public init(ride: Ride?, sentAt: Date, recording: Bool, guidance: RideGuidance? = nil) {
        self.ride = ride
        self.sentAt = sentAt
        self.recording = recording
        self.guidance = guidance
    }

    public var activeGuidance: RideGuidance? {
        guard let ride, ride.endedAt == nil, guidance?.rideID == ride.id else { return nil }
        return guidance
    }
}
