import ActivityKit
import Foundation

struct RideActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var distance: Double
        var speed: Double?
        var stopped: Double
        var updatedAt: Date
        var endedAt: Date?
    }
    var rideID: UUID
    var startedAt: Date
    var owner: String
}
