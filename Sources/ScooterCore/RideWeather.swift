import Foundation

/// Provider-neutral precipitation type. `freezingRain` covers freezing rain and freezing drizzle.
public enum WeatherPrecipitation: String, Sendable, Hashable {
    case none, rain, snow, sleet, hail, freezingRain, mixed

    /// Snow, sleet, hail, freezing rain, and wintry mixes all mean possible ice on the deck or road.
    public var isFrozen: Bool { self != .none && self != .rain }

    var noun: String {
        switch self {
        case .none: "Precipitation"
        case .rain: "Rain"
        case .snow: "Snow"
        case .sleet: "Sleet"
        case .hail: "Hail"
        case .freezingRain: "Freezing rain"
        case .mixed: "Wintry mix"
        }
    }
}

/// One point in time. Intensity is liquid-equivalent millimeters per hour; temperature is Celsius.
public struct WeatherSample: Sendable, Hashable {
    public var date: Date
    public var precipitation: WeatherPrecipitation
    public var chance: Double
    public var intensity: Double
    public var temperature: Double?

    public init(date: Date, precipitation: WeatherPrecipitation, chance: Double, intensity: Double, temperature: Double? = nil) {
        self.date = date
        self.precipitation = precipitation
        self.chance = chance
        self.intensity = intensity
        self.temperature = temperature
    }

    var isWet: Bool { precipitation != .none && intensity > 0 }
}

public struct WeatherReport: Sendable, Hashable {
    public var current: WeatherSample
    public var thunderstorm: Bool
    /// Meters per second.
    public var gust: Double?
    /// Next-hour minute forecast. Empty where unavailable.
    public var minutes: [WeatherSample]
    /// Hourly samples, ideally including the previous few hours so recent precipitation can flag ice.
    public var hours: [WeatherSample]

    public init(current: WeatherSample, thunderstorm: Bool = false, gust: Double? = nil,
                minutes: [WeatherSample] = [], hours: [WeatherSample] = []) {
        self.current = current
        self.thunderstorm = thunderstorm
        self.gust = gust
        self.minutes = minutes
        self.hours = hours
    }
}

public enum RideWeatherVerdict: Int, Codable, Sendable, Comparable {
    case good, caution, avoid

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    public var title: String {
        switch self {
        case .good: "Good scooter weather"
        case .caution: "Ride with caution"
        case .avoid: "Not recommended"
        }
    }
}

public enum RideWeatherReason: Sendable, Hashable {
    case thunderstorm
    case precipitatingNow(WeatherPrecipitation, heavy: Bool)
    case iceLikely
    case nearFreezing(Double)
    case recentRain
    case startingSoon(WeatherPrecipitation, minutes: Int)
    case expected(WeatherPrecipitation, at: Date, chance: Double)
    case gusty(Double)

    public var verdict: RideWeatherVerdict {
        switch self {
        case .thunderstorm, .iceLikely: .avoid
        case let .precipitatingNow(kind, heavy): kind.isFrozen || heavy ? .avoid : .caution
        case let .expected(kind, _, chance): kind.isFrozen && chance >= RideWeather.likely ? .avoid : .caution
        case .nearFreezing, .recentRain, .startingSoon, .gusty: .caution
        }
    }

    public var text: String {
        switch self {
        case .thunderstorm:
            "Thunderstorms nearby"
        case let .precipitatingNow(kind, heavy):
            "\(heavy && kind == .rain ? "Heavy rain" : kind.noun) now"
        case .iceLikely:
            "Freezing temperatures with precipitation: ice likely"
        case let .nearFreezing(celsius):
            "\(RideWeather.temperature(celsius)): watch for icy patches"
        case .recentRain:
            "Recent rain: roads may still be wet"
        case let .startingSoon(kind, minutes):
            "\(kind.noun) starting in about \(max(1, minutes)) min"
        case let .expected(kind, date, chance):
            "\(kind.noun) \(Int((chance * 100).rounded()))% around \(date.formatted(date: .omitted, time: .shortened))"
        case let .gusty(speed):
            "Gusts to \(Int((speed * 3600 / RideUnits.metersPerMile).rounded())) mph"
        }
    }
}

public struct RideWeatherAssessment: Sendable, Hashable {
    public var verdict: RideWeatherVerdict
    public var reasons: [RideWeatherReason]
    public var temperature: Double?

    public var summary: String {
        reasons.first?.text ?? "No precipitation expected in the next \(RideWeather.lookAheadHours) hours"
    }
}

public enum RideWeather {
    public static let lookAheadHours = 3
    static let likely = 0.5
    static let possible = 0.3
    static let heavyRain = 2.5
    static let freezing = 0.0
    static let nearFreezing = 2.0
    static let gusty = 13.0

    public static func assess(_ report: WeatherReport, now: Date = .now) -> RideWeatherAssessment {
        var reasons: [RideWeatherReason] = []
        let current = report.current
        let temperature = current.temperature
        let ahead = report.hours.filter { $0.date > now && $0.date <= now.addingTimeInterval(Double(lookAheadHours) * 3600) }
        let recent = report.hours.filter { $0.date <= now && $0.date >= now.addingTimeInterval(-6 * 3600) }
        let soon = report.minutes.filter { $0.date > now && $0.date <= now.addingTimeInterval(3600) }

        if report.thunderstorm { reasons.append(.thunderstorm) }
        if current.isWet {
            reasons.append(.precipitatingNow(current.precipitation, heavy: current.intensity >= heavyRain))
        }

        let coldest = ([temperature] + ahead.map(\.temperature)).compactMap { $0 }.min()
        let wetNearby = current.isWet
            || recent.contains(where: \.isWet)
            || ahead.contains { $0.precipitation != .none && $0.chance >= possible }
        if let coldest, coldest <= freezing + 1, wetNearby || ahead.contains(where: { $0.precipitation.isFrozen && $0.chance >= possible }) {
            reasons.append(.iceLikely)
        } else if let temperature, temperature <= nearFreezing {
            reasons.append(.nearFreezing(temperature))
        }

        if !current.isWet {
            if let start = soon.first(where: { $0.isWet && $0.chance >= likely }) {
                reasons.append(.startingSoon(start.precipitation, minutes: Int(start.date.timeIntervalSince(now) / 60)))
            } else if let next = ahead.first(where: { $0.precipitation != .none && $0.chance >= possible }) {
                reasons.append(.expected(next.precipitation, at: next.date, chance: next.chance))
            }
            if recent.suffix(2).contains(where: \.isWet), !reasons.contains(.iceLikely) {
                reasons.append(.recentRain)
            }
        }

        if let gust = report.gust, gust >= gusty { reasons.append(.gusty(gust)) }

        reasons.sort { $0.verdict > $1.verdict }
        return RideWeatherAssessment(verdict: reasons.map(\.verdict).max() ?? .good, reasons: reasons, temperature: temperature)
    }

    public static func temperature(_ celsius: Double) -> String {
        Measurement(value: celsius, unit: UnitTemperature.celsius)
            .formatted(.measurement(width: .abbreviated, usage: .weather, numberFormatStyle: .number.precision(.fractionLength(0))))
    }
}
