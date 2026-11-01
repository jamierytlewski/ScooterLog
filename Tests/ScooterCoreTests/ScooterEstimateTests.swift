import Testing
@testable import ScooterCore

struct ScooterEstimateTests {
    @Test func fullSpeedBenchmarkUsesTheProvidedF3Specs() throws {
        let estimate = try #require(ScooterEstimate(distanceMeters: 25 * RideUnits.metersPerMile, speedMPH: 20))
        #expect(abs(estimate.noStopDuration - 4500) < 0.0001)
        #expect(abs(estimate.energyWattHours.upperBound - 477) < 0.0001)
        #expect(abs(estimate.batteryPercent.upperBound - 100) < 0.0001)
        #expect(abs(estimate.energyWattHours.lowerBound - 477 * 25 / 43.5) < 0.0001)
    }

    @Test func maximumRangeBenchmarkAndSlowerPlanningSpeed() throws {
        let distance = 43.5 * RideUnits.metersPerMile
        let estimate = try #require(ScooterEstimate(distanceMeters: distance, speedMPH: 9))
        #expect(abs(estimate.energyWattHours.lowerBound - 477) < 0.0001)
        #expect(abs(estimate.batteryPercent.lowerBound - 100) < 0.0001)
        #expect(abs(estimate.noStopDuration - 17_400) < 0.0001)
        let faster = try #require(ScooterEstimate(distanceMeters: distance, speedMPH: 20))
        #expect(estimate.energyWattHours == faster.energyWattHours, "Do not invent a speed/energy interpolation")
        #expect(estimate.batteryPercent.upperBound > 100, "Do not hide routes longer than rated range")
    }

    @Test func zeroAndInvalidInputs() throws {
        let zero = try #require(ScooterEstimate(distanceMeters: 0, speedMPH: 20))
        #expect(zero.noStopDuration == 0)
        #expect(zero.energyWattHours == 0...0)
        #expect(zero.batteryPercent == 0...0)
        for distance in [-1.0, .nan, .infinity] {
            #expect(ScooterEstimate(distanceMeters: distance, speedMPH: 20) == nil)
        }
        for speed in [-1.0, 0, 21, .nan, .infinity] {
            #expect(ScooterEstimate(distanceMeters: 1000, speedMPH: speed) == nil)
        }
        #expect(ScooterEstimate(distanceMeters: .greatestFiniteMagnitude, speedMPH: .leastNonzeroMagnitude) == nil)
    }
}
