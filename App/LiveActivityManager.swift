import ActivityKit
import Foundation
import ScooterCore

@MainActor
final class LiveActivityManager {
    private func content(_ ride: Ride, isPaused: Bool = false) -> ActivityContent<RideActivityAttributes.ContentState> {
        ActivityContent(state: .init(distance: ride.distance, speed: ride.currentSpeed(at: .now),
                                     stopped: ride.stoppedTime(at: .now), updatedAt: ride.samples.last?.timestamp ?? ride.startedAt,
                                     endedAt: ride.endedAt, theme: RideTheme.selected, isPaused: isPaused),
                        staleDate: (ride.samples.last?.timestamp ?? ride.startedAt).addingTimeInterval(15))
    }

    func start(_ ride: Ride, onError: (String) -> Void) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        guard !Activity<RideActivityAttributes>.activities.contains(where: { $0.attributes.rideID == ride.id }) else {
            update(ride, isPaused: false)
            return
        }
        do {
            _ = try Activity.request(attributes: RideActivityAttributes(rideID: ride.id, startedAt: ride.startedAt, owner: ride.owner),
                                     content: content(ride, isPaused: false), pushType: nil)
        } catch { onError("Ride is recording, but Live Activity could not start: \(error.localizedDescription)") }
    }

    func update(_ ride: Ride, isPaused: Bool = false) {
        let content = content(ride, isPaused: isPaused)
        Task {
            for activity in Activity<RideActivityAttributes>.activities where activity.attributes.rideID == ride.id {
                await activity.update(content)
            }
        }
    }

    func end(_ ride: Ride) {
        let content = content(ride, isPaused: false)
        Task {
            for activity in Activity<RideActivityAttributes>.activities where activity.attributes.rideID == ride.id {
                await activity.end(content, dismissalPolicy: .after(.now.addingTimeInterval(60)))
            }
        }
    }

    func endAll() {
        Task {
            for activity in Activity<RideActivityAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }
}
