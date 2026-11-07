import AppIntents

/// Starts a ride from Control Center, the Lock Screen or the Action button.
/// Compiled into the apps and the widget extensions; because it opens the app, `perform` runs in the
/// app, which installs `handler` at launch.
struct StartRideControlIntent: AppIntent {
    static let title: LocalizedStringResource = "Start ride"
    static let description = IntentDescription("Open ScooterLog and start recording a ride.")
    static var supportedModes: IntentModes { .foreground(.immediate) }
    static var allowedExecutionTargets: IntentExecutionTargets { .main }
    static let isDiscoverable = false

    @MainActor static var handler: (() async -> Void)?

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let handler = Self.handler else { throw StartRideControlIntentError.handlerUnavailable }
        await handler()
        return .result()
    }
}

private enum StartRideControlIntentError: Error, CustomLocalizedStringResourceConvertible {
    case handlerUnavailable

    var localizedStringResource: LocalizedStringResource {
        "ScooterLog couldn't start a ride. Open the app and try again."
    }
}
