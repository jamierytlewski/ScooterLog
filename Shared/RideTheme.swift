import SwiftUI

enum RideTheme: String, CaseIterable, Identifiable, Codable {
    case tronBlue = "TronBlue"
    case aresRed = "AresRed"

    static let preferenceKey = "rideTheme"
    static let secondaryText = Color("RideSecondaryText")
    static let canvas = Color("RideCanvas")
    static let panel = Color("RidePanel")
    static let artworkBackground = Color(red: 0.012, green: 0.035, blue: 0.075)

    static var selected: RideTheme {
        UserDefaults.standard.string(forKey: preferenceKey).flatMap(RideTheme.init(rawValue:))
            ?? .tronBlue
    }

    var id: String { rawValue }
    var color: Color { Color(rawValue) }
    var artworkGlow: Color {
        switch self {
        case .tronBlue: Color(red: 0.02, green: 0.48, blue: 0.82)
        case .aresRed: Color(red: 0.82, green: 0.035, blue: 0.20)
        }
    }

    var artworkGradient: LinearGradient {
        LinearGradient(
            colors: [Self.artworkBackground, artworkGlow.opacity(0.36), Self.artworkBackground],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var title: String {
        switch self {
        case .tronBlue: "Tron blue"
        case .aresRed: "Ares red"
        }
    }
}
extension View {
    func ridePanelRow() -> some View {
        #if os(watchOS)
            self.listRowBackground(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(RideTheme.panel)
            )
        #else
            self.listRowBackground(RideTheme.panel)
        #endif
    }

    func rideSurface() -> some View {
        #if os(iOS)
            self
                .scrollContentBackground(.hidden)
                .background(RideTheme.canvas)
        #else
            self
        #endif
    }
}
/// The icon's illustrated trail is brand artwork, never a recorded route.
struct ScooterArtwork: View {
    let theme: RideTheme

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height * 1.35)
            ZStack {
                RideTheme.artworkBackground
                theme.artworkGradient
                RadialGradient(
                    colors: [theme.artworkGlow.opacity(0.42), .clear],
                    center: .topTrailing,
                    startRadius: 0,
                    endRadius: side * 0.8
                )
                Image(theme == .tronBlue ? "ScooterBlue" : "ScooterRed")
                    .resizable()
                    .scaledToFill()
                    .frame(width: side, height: side)
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                    .overlay(theme.artworkGradient.opacity(0.2))
            }
        }
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
struct RidePrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .foregroundStyle(Color("OnRideAccent"))
            .background(.tint, in: Capsule())
            .opacity(isEnabled ? (configuration.isPressed ? 0.78 : 1) : 0.45)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: configuration.isPressed)
    }
}
struct RideToolIcon: View {
    let systemImage: String
    @AppStorage(RideTheme.preferenceKey) private var theme: RideTheme = .tronBlue

    private var side: CGFloat {
        #if os(watchOS)
            32
        #else
            40
        #endif
    }

    var body: some View {
        Image(systemName: systemImage)
            .font(.body.weight(.semibold))
            .foregroundStyle(theme.color)
            .frame(width: side, height: side)
            .background(theme.color.opacity(0.10), in: .rect(cornerRadius: 12))
            .accessibilityHidden(true)
    }
}
