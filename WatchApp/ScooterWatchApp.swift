import SwiftUI

@main
struct ScooterWatchApp: App {
    @StateObject private var controller = RideController.shared

    var body: some Scene {
        WindowGroup { RideDashboard(controller: controller) }
    }
}
