import Foundation

/// F3 rated-range benchmarks, not a prediction of remaining battery or real-world consumption.
public struct ScooterEstimate: Equatable, Sendable {
    public static let maximumSpeedMPH = 20.0
    public static let batteryWattHours = 477.0
    public static let maximumRangeMiles = 43.5
    public static let fullSpeedRangeMiles = 25.0

    public let noStopDuration: TimeInterval
    public let energyWattHours: ClosedRange<Double>
    public let batteryPercent: ClosedRange<Double>

    public init?(distanceMeters: Double, speedMPH: Double) {
        guard distanceMeters.isFinite, distanceMeters >= 0,
              speedMPH.isFinite, speedMPH > 0, speedMPH <= Self.maximumSpeedMPH else { return nil }
        let miles = distanceMeters / RideUnits.metersPerMile
        let duration = miles / speedMPH * 3600
        let low = miles / Self.maximumRangeMiles
        let high = miles / Self.fullSpeedRangeMiles
        guard duration.isFinite, (high * Self.batteryWattHours).isFinite else { return nil }
        noStopDuration = duration
        energyWattHours = (low * Self.batteryWattHours)...(high * Self.batteryWattHours)
        batteryPercent = (low * 100)...(high * 100)
    }
}
