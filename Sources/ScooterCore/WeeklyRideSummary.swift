import Foundation

/// Completed-ride totals for one calendar week.
public struct WeeklyRideSummary: Codable, Equatable, Sendable {
    public var weekStart: Date
    /// Meters ridden on each day of the week, starting with `weekStart`.
    public var dailyDistance: [Double]
    public var rideCount: Int
    public var rideDuration: TimeInterval

    public init(weekStart: Date, dailyDistance: [Double] = Array(repeating: 0, count: 7),
                rideCount: Int = 0, rideDuration: TimeInterval = 0) {
        self.weekStart = weekStart
        self.dailyDistance = dailyDistance
        self.rideCount = rideCount
        self.rideDuration = rideDuration
    }

    public var distance: Double { dailyDistance.reduce(0, +) }

    public var miles: Double { distance / RideUnits.metersPerMile }

    public var milesText: String { String(format: "%.1f", miles) }

    /// Totals completed rides whose start falls in the week containing `now`.
    public static func make(rides: [Ride], now: Date = .now, calendar: Calendar = .current) -> Self {
        let start = weekStart(containing: now, calendar: calendar)
        var summary = WeeklyRideSummary(weekStart: start)
        for ride in rides where ride.endedAt != nil {
            let day = calendar.dateComponents([.day], from: start, to: calendar.startOfDay(for: ride.startedAt)).day ?? -1
            guard (0..<7).contains(day) else { continue }
            summary.dailyDistance[day] += ride.distance
            summary.rideCount += 1
            summary.rideDuration += ride.elapsed(at: ride.endedAt ?? now)
        }
        return summary
    }

    /// The stored summary if it is still for the current week, otherwise an empty one.
    public func current(at now: Date = .now, calendar: Calendar = .current) -> Self {
        let start = Self.weekStart(containing: now, calendar: calendar)
        return start == weekStart ? self : WeeklyRideSummary(weekStart: start)
    }

    public static func weekStart(containing date: Date, calendar: Calendar = .current) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    public static func nextWeek(after date: Date, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .weekOfYear, value: 1, to: weekStart(containing: date, calendar: calendar)) ?? date.addingTimeInterval(7 * 86_400)
    }
}
