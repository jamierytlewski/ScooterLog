import Foundation

public enum RideUnits {
    public static let metersPerMile = 1_609.344

    public static func speed(_ metersPerSecond: Double?) -> String {
        metersPerSecond.map { String(format: "%.1f mph", $0 * 3600 / metersPerMile) } ?? "-- mph"
    }

    public static func distance(_ meters: Double) -> String {
        String(format: "%.2f mi", meters / metersPerMile)
    }
}
