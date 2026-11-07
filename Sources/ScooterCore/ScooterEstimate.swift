import Foundation

public struct ScooterProfile: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var maximumSpeedMPH: Double
    public var batteryWattHours: Double
    public var maximumRangeMiles: Double
    public var fullSpeedRangeMiles: Double

    public init(id: UUID = UUID(), name: String, maximumSpeedMPH: Double, batteryWattHours: Double,
                maximumRangeMiles: Double, fullSpeedRangeMiles: Double) {
        self.id = id
        self.name = name
        self.maximumSpeedMPH = maximumSpeedMPH
        self.batteryWattHours = batteryWattHours
        self.maximumRangeMiles = maximumRangeMiles
        self.fullSpeedRangeMiles = fullSpeedRangeMiles
    }

    public var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && maximumSpeedMPH.isFinite && (1...100).contains(maximumSpeedMPH)
            && batteryWattHours.isFinite && (1...20_000).contains(batteryWattHours)
            && maximumRangeMiles.isFinite && (0.1...1_000).contains(maximumRangeMiles)
            && fullSpeedRangeMiles.isFinite && (0.1...maximumRangeMiles).contains(fullSpeedRangeMiles)
    }

    public static let f3 = ScooterProfile(
        id: UUID(uuidString: "5F4F7CD7-2023-433B-AC74-7AFC5D3F9B21")!,
        name: "Segway F3", maximumSpeedMPH: 20, batteryWattHours: 477,
        maximumRangeMiles: 43.5, fullSpeedRangeMiles: 25
    )
}

/// Rated-range benchmarks, not a prediction of remaining battery or real-world consumption.
public struct ScooterEstimate: Equatable, Sendable {
    public static let maximumSpeedMPH = 20.0
    public static let batteryWattHours = 477.0
    public static let maximumRangeMiles = 43.5
    public static let fullSpeedRangeMiles = 25.0

    public let noStopDuration: TimeInterval
    public let energyWattHours: ClosedRange<Double>
    public let batteryPercent: ClosedRange<Double>

    public init?(distanceMeters: Double, speedMPH: Double, profile: ScooterProfile = .f3) {
        guard distanceMeters.isFinite, distanceMeters >= 0,
              profile.isValid,
              speedMPH.isFinite, speedMPH > 0, speedMPH <= profile.maximumSpeedMPH else { return nil }
        let miles = distanceMeters / RideUnits.metersPerMile
        let duration = miles / speedMPH * 3600
        let low = miles / profile.maximumRangeMiles
        let high = miles / profile.fullSpeedRangeMiles
        guard duration.isFinite, (high * profile.batteryWattHours).isFinite else { return nil }
        noStopDuration = duration
        energyWattHours = (low * profile.batteryWattHours)...(high * profile.batteryWattHours)
        batteryPercent = (low * 100)...(high * 100)
    }
}
