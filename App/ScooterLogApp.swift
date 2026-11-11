import SwiftUI
import UIKit

@main
struct ScooterLogApp: App {
    @UIApplicationDelegateAdaptor(ScooterAppDelegate.self) private var appDelegate
    @StateObject private var controller = RideController.shared
    @StateObject private var icons = ThemeIconController()
    @AppStorage(RideTheme.preferenceKey) private var theme: RideTheme = .tronBlue
    @Environment(\.scenePhase) private var scenePhase

    init() {
        StartRideControlIntent.handler = { HomeScreenActions.shared.startRequested = true }
        PauseRideIntent.handler = { RideController.shared.pause() }
        ScooterShortcuts.updateAppShortcutParameters()
    }

    var body: some Scene {
        WindowGroup {
            RideDashboard(controller: controller)
                .onChange(of: theme, initial: false) { _, _ in updateIcon() }
                .onChange(of: scenePhase, initial: false) { _, phase in
                    if phase == .active { updateIcon() }
                }
        }
    }

    private func updateIcon() {
        guard scenePhase == .active else { return }
        icons.match(theme, onError: controller.report)
    }
}
@MainActor
final class ThemeIconController: ObservableObject {
    private var requestedTheme: RideTheme?
    private var task: Task<Void, Never>?

    func match(_ theme: RideTheme, onError: @escaping (String) -> Void) {
        requestedTheme = theme
        guard task == nil else { return }
        task = Task {
            defer { task = nil }
            while let choice = requestedTheme {
                requestedTheme = nil
                let name: String? = choice == .aresRed ? "AppIconAres" : nil
                guard UIApplication.shared.alternateIconName != name else { continue }
                guard UIApplication.shared.supportsAlternateIcons else {
                    onError(
                        "This device cannot change app icons. Your selected colors still apply inside ScooterLog."
                    )
                    return
                }
                do {
                    try await UIApplication.shared.setAlternateIconName(name)
                } catch {
                    onError(
                        "The app icon couldn't be changed: \(error.localizedDescription) Your selected colors still apply. Reopen ScooterLog to retry."
                    )
                }
            }
        }
    }
}
@MainActor
final class HomeScreenActions: ObservableObject {
    static let shared = HomeScreenActions()
    static let startType = "com.scooterlog.startRide"
    @Published var startRequested = false

    func receive(_ item: UIApplicationShortcutItem) -> Bool {
        guard item.type == Self.startType else { return false }
        startRequested = true
        return true
    }
}
final class ScooterAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = ScooterSceneDelegate.self
        return configuration
    }
}
final class ScooterSceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(
        _ scene: UIScene, willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        if let item = connectionOptions.shortcutItem {
            _ = HomeScreenActions.shared.receive(item)
        }
    }

    func windowScene(
        _ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        completionHandler(HomeScreenActions.shared.receive(shortcutItem))
    }
}
