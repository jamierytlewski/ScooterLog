import AppIntents

#if os(iOS)
typealias StartRideProtocol = LiveActivityIntent
#else
typealias StartRideProtocol = AppIntent
#endif

struct StartRideIntent: StartRideProtocol {
    static let title: LocalizedStringResource = "Start scooter ride"
    static let description = IntentDescription("Open ScooterLog and start GPS recording on this device. Allow location access first.")
    static var supportedModes: IntentModes { .foreground(.immediate) }
    static var allowedExecutionTargets: IntentExecutionTargets { .main }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        await RideController.shared.waitForForeground()
        try RideController.shared.start()
        return .result(dialog: "ScooterLog is recording your ride on this device.")
    }
}

struct EndRideIntent: AppIntent {
    static let title: LocalizedStringResource = "End scooter ride"
    static let description = IntentDescription("End and save the ride owned by this device. A companion-owned ride must be ended on its owner or through the connected app controls.")
    static var allowedExecutionTargets: IntentExecutionTargets { .main }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try RideController.shared.end()
        return .result(dialog: "Your scooter ride has been saved on this device.")
    }
}

struct ScooterShortcuts: AppShortcutsProvider {
    static var shortcutTileColor: ShortcutTileColor { .teal }

    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StartRideIntent(),
                    phrases: ["Start a ride in \(.applicationName)", "I'm riding my scooter with \(.applicationName)"],
                    shortTitle: "Start ride", systemImageName: "scooter")
        AppShortcut(intent: EndRideIntent(),
                    phrases: ["End my ride in \(.applicationName)"],
                    shortTitle: "End ride", systemImageName: "stop.circle")
    }
}
