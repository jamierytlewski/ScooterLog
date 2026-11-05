import CoreLocation
import ScooterCore
import WeatherKit

/// Converts a WeatherKit forecast into the `WeatherReport` that ScooterCore assesses.
/// Shared by the apps and the widget extensions.
enum RideWeatherService {
    static func report(for location: CLLocation) async throws -> WeatherReport {
        let now = Date.now
        let (current, minutes, hours) = try await WeatherService.shared.weather(
            for: location,
            including: .current, .minute,
            .hourly(startDate: now.addingTimeInterval(-6 * 3600), endDate: now.addingTimeInterval(4 * 3600))
        )
        let upcoming = hours.forecast.filter { $0.date > now && $0.date <= now.addingTimeInterval(3 * 3600) }
        let currentKind = kind(for: current.condition, precipitation: nil)
        let currentIntensity = millimetersPerHour(current.precipitationIntensity)
        return WeatherReport(
            current: WeatherSample(date: current.date, precipitation: currentKind,
                                   chance: currentKind == .none ? 0 : 1,
                                   intensity: currentKind == .none ? 0 : max(currentIntensity, 0.1),
                                   temperature: current.temperature.converted(to: .celsius).value),
            thunderstorm: current.condition.isStorm
                || upcoming.contains { $0.condition.isStorm && $0.precipitationChance >= 0.3 },
            gust: current.wind.gust?.converted(to: .metersPerSecond).value,
            minutes: minutes?.forecast.map {
                WeatherSample(date: $0.date, precipitation: kind(for: nil, precipitation: $0.precipitation),
                              chance: $0.precipitationChance, intensity: millimetersPerHour($0.precipitationIntensity))
            } ?? [],
            hours: hours.forecast.map {
                WeatherSample(date: $0.date, precipitation: kind(for: $0.condition, precipitation: $0.precipitation),
                              chance: $0.precipitationChance,
                              intensity: $0.precipitationAmount.converted(to: .millimeters).value,
                              temperature: $0.temperature.converted(to: .celsius).value)
            }
        )
    }

    private static func millimetersPerHour(_ rate: Measurement<UnitSpeed>) -> Double {
        rate.converted(to: .metersPerSecond).value * 3_600_000
    }

    private static func kind(for condition: WeatherCondition?, precipitation: Precipitation?) -> WeatherPrecipitation {
        switch condition {
        case .freezingRain, .freezingDrizzle: return .freezingRain
        case .wintryMix: return .mixed
        case .sleet: return .sleet
        case .hail: return .hail
        case .snow, .heavySnow, .flurries, .sunFlurries, .blizzard, .blowingSnow: return .snow
        case .rain, .heavyRain, .drizzle, .sunShowers, .isolatedThunderstorms, .scatteredThunderstorms,
             .thunderstorms, .strongStorms, .tropicalStorm, .hurricane:
            if precipitation == nil || precipitation == WeatherKit.Precipitation.none { return .rain }
        default: break
        }
        switch precipitation {
        case .rain: return .rain
        case .snow: return .snow
        case .sleet: return .sleet
        case .hail: return .hail
        case .mixed: return .mixed
        default: return .none
        }
    }
}

private extension WeatherCondition {
    var isStorm: Bool {
        switch self {
        case .isolatedThunderstorms, .scatteredThunderstorms, .thunderstorms, .strongStorms, .tropicalStorm, .hurricane: true
        default: false
        }
    }
}
