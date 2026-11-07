import Foundation

public enum RideUnitSystem: String, CaseIterable, Codable, Sendable {
    case imperial, metric

    public static let preferenceKey = "rideUnitSystem"
    public static let appGroup = "group.com.jamierytlewski.scooterlog"

    public static var selected: Self {
        let value = UserDefaults(suiteName: appGroup)?.string(forKey: preferenceKey)
        return value.flatMap(Self.init(rawValue:)) ?? .imperial
    }

    public var distanceSymbol: String { self == .metric ? "km" : "mi" }
    public var speedSymbol: String { self == .metric ? "km/h" : "mph" }
    public var metersPerUnit: Double { self == .metric ? 1_000 : RideUnits.metersPerMile }
}

public enum RideUnits {
    public static let metersPerMile = 1_609.344

    public static func speed(_ metersPerSecond: Double?, units: RideUnitSystem = .selected) -> String {
        metersPerSecond.map { String(format: "%.1f %@", $0 * 3600 / units.metersPerUnit, units.speedSymbol) }
            ?? "-- \(units.speedSymbol)"
    }

    public static func distance(_ meters: Double, units: RideUnitSystem = .selected) -> String {
        String(format: "%.2f %@", meters / units.metersPerUnit, units.distanceSymbol)
    }
}
