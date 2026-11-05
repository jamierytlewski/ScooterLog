import SwiftUI
import WidgetKit

/// Smart Stack widgets, complications and the Control Center button for Apple Watch.
@main
struct ScooterWatchWidgets: WidgetBundle {
    var body: some Widget {
        RideWeatherWidget()
        WeeklyGoalWidget()
        WeeklyMilesWidget()
        RideStreakWidget()
        LastRideWidget()
        StartRideControl()
    }
}
