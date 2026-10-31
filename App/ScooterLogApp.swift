import SwiftUI

@main
struct ScooterLogApp: App {
    @StateObject private var controller = RideController.shared

    var body: some Scene {
        WindowGroup { RideDashboard(controller: controller) }
    }
}
