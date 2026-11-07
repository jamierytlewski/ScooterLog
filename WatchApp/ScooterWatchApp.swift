import SwiftUI

@main
struct ScooterWatchApp: App {
    @StateObject private var controller = RideController.shared

    init() {
        StartRideControlIntent.handler = {
            let controller = RideController.shared
            await controller.waitForForeground()
            guard controller.displayedRide == nil else { return }
            controller.perform { try controller.start() }
        }
    }

    var body: some Scene {
        WindowGroup {
            #if DEBUG && targetEnvironment(simulator)
            if let screen = ProcessInfo.processInfo.environment["SCOOTERLOG_CAPTURE_SCREEN"] {
                NavigationStack {
                    switch screen {
                    case "history":
                        HistoryView(controller: controller)
                    case "route", "heat-map":
                        if let ride = controller.archive.completed.first {
                            RideDetail(ride: ride, controller: controller)
                        } else {
                            ContentUnavailableView("No demo rides", systemImage: "map")
                        }
                    case "places":
                        SavedPlacesView(controller: controller)
                    default:
                        ContentUnavailableView("Unknown capture screen", systemImage: "exclamationmark.triangle")
                    }
                }
                .tint(RideTheme.selected.color)
            } else {
                RideDashboard(controller: controller)
            }
            #else
            RideDashboard(controller: controller)
            #endif
        }
    }
}
