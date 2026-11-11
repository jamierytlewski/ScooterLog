import ActivityKit
import AppIntents
import Foundation

struct RideActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var distance: Double
        var speed: Double?
        var stopped: Double
        var updatedAt: Date
        var endedAt: Date?
        var theme: RideTheme?
        var isPaused: Bool = false

        init(distance: Double, speed: Double? = nil, stopped: Double = 0, updatedAt: Date = .now, endedAt: Date? = nil, theme: RideTheme? = nil, isPaused: Bool = false) {
            self.distance = distance
            self.speed = speed
            self.stopped = stopped
            self.updatedAt = updatedAt
            self.endedAt = endedAt
            self.theme = theme
            self.isPaused = isPaused
        }
    }
    var rideID: UUID
    var startedAt: Date
    var owner: String
}

struct PauseRideIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Pause ride"
    static let description = IntentDescription("Pauses the active scooter ride recording.")
    static var allowedExecutionTargets: IntentExecutionTargets { .main }
    static let isDiscoverable = false

    @MainActor static var handler: (() -> Void)?

    @MainActor
    func perform() async throws -> some IntentResult {
        Self.handler?()
        return .result()
    }
}
