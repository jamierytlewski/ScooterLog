import Foundation
import Testing
@testable import ScooterCore

struct RideWeatherTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func dry(_ temperature: Double = 15) -> WeatherSample {
        WeatherSample(date: now, precipitation: .none, chance: 0, intensity: 0, temperature: temperature)
    }

    func hour(_ offset: Double, _ kind: WeatherPrecipitation = .none, chance: Double = 0,
              intensity: Double = 0, temperature: Double = 15) -> WeatherSample {
        WeatherSample(date: now.addingTimeInterval(offset * 3600), precipitation: kind, chance: chance,
                      intensity: intensity, temperature: temperature)
    }

    @Test func dryMildWeatherIsGood() {
        let result = RideWeather.assess(WeatherReport(current: dry(), hours: [hour(1), hour(2)]), now: now)
        #expect(result.verdict == .good)
        #expect(result.reasons.isEmpty)
    }

    @Test func lightRainNowIsCautionAndHeavyRainIsAvoid() {
        var light = dry()
        light.precipitation = .rain
        light.intensity = 0.5
        #expect(RideWeather.assess(WeatherReport(current: light), now: now).verdict == .caution)
        light.intensity = 4
        #expect(RideWeather.assess(WeatherReport(current: light), now: now).verdict == .avoid)
    }

    @Test(arguments: [WeatherPrecipitation.snow, .sleet, .hail, .freezingRain, .mixed])
    func anyFrozenPrecipitationNowIsAvoid(kind: WeatherPrecipitation) {
        var current = dry(4)
        current.precipitation = kind
        current.intensity = 0.2
        #expect(RideWeather.assess(WeatherReport(current: current), now: now).verdict == .avoid)
    }

    @Test func rainExpectedSoonIsCaution() {
        let report = WeatherReport(current: dry(), hours: [hour(2, .rain, chance: 0.6, intensity: 1)])
        let result = RideWeather.assess(report, now: now)
        #expect(result.verdict == .caution)
        #expect(result.reasons.first == .expected(.rain, at: now.addingTimeInterval(7200), chance: 0.6))
    }

    @Test func unlikelyOrDistantRainIsIgnored() {
        let report = WeatherReport(current: dry(), hours: [hour(1, .rain, chance: 0.1), hour(5, .rain, chance: 0.9)])
        #expect(RideWeather.assess(report, now: now).verdict == .good)
    }

    @Test func likelySnowAheadIsAvoid() {
        let report = WeatherReport(current: dry(5), hours: [hour(1, .snow, chance: 0.7, temperature: 5)])
        #expect(RideWeather.assess(report, now: now).verdict == .avoid)
    }

    @Test func minuteForecastReportsImminentRain() {
        let minutes = [WeatherSample(date: now.addingTimeInterval(12 * 60), precipitation: .rain, chance: 0.8, intensity: 0.4)]
        let result = RideWeather.assess(WeatherReport(current: dry(), minutes: minutes), now: now)
        #expect(result.reasons == [.startingSoon(.rain, minutes: 12)])
    }

    @Test func recentRainBelowFreezingMeansIce() {
        let report = WeatherReport(current: dry(-1), hours: [hour(-2, .rain, chance: 1, intensity: 1, temperature: 1)])
        let result = RideWeather.assess(report, now: now)
        #expect(result.verdict == .avoid)
        #expect(result.reasons.contains(.iceLikely))
    }

    @Test func dryNearFreezingIsCaution() {
        let result = RideWeather.assess(WeatherReport(current: dry(1.5)), now: now)
        #expect(result.reasons == [.nearFreezing(1.5)])
        #expect(result.verdict == .caution)
    }

    @Test func recentRainAboveFreezingWarnsOfWetRoads() {
        let report = WeatherReport(current: dry(), hours: [hour(-1, .rain, chance: 1, intensity: 1)])
        #expect(RideWeather.assess(report, now: now).reasons == [.recentRain])
    }

    @Test func thunderstormsAndGustsAreFlagged() {
        #expect(RideWeather.assess(WeatherReport(current: dry(), thunderstorm: true), now: now).verdict == .avoid)
        let gusty = RideWeather.assess(WeatherReport(current: dry(), gust: 15), now: now)
        #expect(gusty.verdict == .caution)
        #expect(gusty.reasons == [.gusty(15)])
    }

    @Test func mostSevereReasonLeads() {
        var current = dry()
        current.precipitation = .rain
        current.intensity = 0.5
        let result = RideWeather.assess(WeatherReport(current: current, thunderstorm: true, gust: 20), now: now)
        #expect(result.reasons.first == .thunderstorm)
        #expect(result.summary == "Thunderstorms nearby")
    }
}
