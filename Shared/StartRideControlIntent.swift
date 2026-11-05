import AppIntents

/// Starts a ride from Control Center, the Lock Screen or the Action button.
/// Compiled into the apps and the widget extensions; because it opens the app, `perform` runs in the
/// app, which installs `handler` at launch.
struct StartRideControlIntent: AppIntent {
    static let title: LocalizedStringResource = "Start ride"
    static let description = IntentDescription("Open ScooterLog and start recording a ride.")
    static let openAppWhenRun = true
    static let isDiscoverable = false

    @MainActor static var handler: (() -> Void)?

    @MainActor
    func perform() async throws -> some IntentResult {
        Self.handler?()
        return .result()
    }
}
