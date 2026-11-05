import Foundation
import ScooterCore
import WidgetKit

/// Reads and writes the widget snapshot in the App Group shared by an app and its widget extension.
enum RideWidgetStore {
    static var defaults: UserDefaults? { UserDefaults(suiteName: RideWidgetSnapshot.appGroup) }

    static func load() -> RideWidgetSnapshot? {
        defaults?.data(forKey: RideWidgetSnapshot.storageKey)
            .flatMap { try? JSONDecoder().decode(RideWidgetSnapshot.self, from: $0) }
    }

    static func save(_ snapshot: RideWidgetSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults?.set(data, forKey: RideWidgetSnapshot.storageKey)
    }

    static var goalMiles: Double {
        let goal = defaults?.double(forKey: RideWidgetSnapshot.goalKey) ?? 0
        return goal > 0 ? goal : RideWidgetSnapshot.defaultGoalMiles
    }
}

/// Keeps the widgets in step with the app's rides, weekly goal, theme and latest forecast.
@MainActor
final class RideWidgetPublisher: ObservableObject {
    private var published: RideWidgetSnapshot?

    func publish(rides: [Ride], rideActive: Bool, goalMiles: Double, weather: RideWidgetSnapshot.Weather?, theme: String) {
        // Keep the last forecast if this launch hasn't fetched one yet.
        let weather = weather ?? published?.weather ?? RideWidgetStore.load()?.weather
        let snapshot = RideWidgetSnapshot.make(rides: rides, rideActive: rideActive, goalMiles: goalMiles,
                                               weather: weather, theme: theme)
        guard snapshot != published else { return }
        published = snapshot
        RideWidgetStore.save(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
