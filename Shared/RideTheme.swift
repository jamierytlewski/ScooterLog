import SwiftUI

enum RideTheme: String, CaseIterable, Identifiable, Codable {
    case tronBlue = "TronBlue"
    case aresRed = "AresRed"

    static let preferenceKey = "rideTheme"
    static let secondaryText = Color("RideSecondaryText")

    static var selected: RideTheme {
        UserDefaults.standard.string(forKey: preferenceKey).flatMap(RideTheme.init(rawValue:)) ?? .tronBlue
    }

    var id: String { rawValue }
    var color: Color { Color(rawValue) }

    var title: String {
        switch self {
        case .tronBlue: "Tron blue"
        case .aresRed: "Ares red"
        }
    }
}
