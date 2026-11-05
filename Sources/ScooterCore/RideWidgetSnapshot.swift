import Foundation

/// Everything the Home Screen, Lock Screen, Smart Stack and complication widgets show.
/// Written by the app into its App Group and read by the widget extension on the same device.
public struct RideWidgetSnapshot: Codable, Equatable, Sendable {
    public static let appGroup = "group.com.jamierytlewski.scooterlog"
    public static let storageKey = "rideWidgetSnapshot"
    public static let goalKey = "weeklyGoalMiles"
    public static let defaultGoalMiles = 20.0
    public static let goalRange = 5.0...200.0

    public struct LastRide: Codable, Equatable, Sendable {
        public var startedAt: Date
        public var endedAt: Date
        public var distance: Double
        public var movingDuration: TimeInterval
        /// Moving average speed in meters per second.
        public var averageSpeed: Double

        public init(startedAt: Date, endedAt: Date, distance: Double, movingDuration: TimeInterval, averageSpeed: Double) {
            self.startedAt = startedAt
            self.endedAt = endedAt
            self.distance = distance
            self.movingDuration = movingDuration
            self.averageSpeed = averageSpeed
        }

        public var duration: TimeInterval { endedAt.timeIntervalSince(startedAt) }
    }

    /// A time the rider usually starts a ride. `weekday` is nil for an hour ridden on many different days.
    public struct Habit: Codable, Equatable, Sendable {
        public var weekday: Int?
        public var hour: Int
        public var count: Int
    }

    public struct Weather: Codable, Equatable, Sendable {
        public var verdict: RideWeatherVerdict
        public var summary: String
        public var temperature: Double?
        public var updated: Date
        /// Rounded to about 1 km so the widget can refresh the forecast without its own location access.
        public var latitude: Double
        public var longitude: Double

        public init(verdict: RideWeatherVerdict, summary: String, temperature: Double?, updated: Date,
                    latitude: Double, longitude: Double) {
            self.verdict = verdict
            self.summary = summary
            self.temperature = temperature
            self.updated = updated
            self.latitude = (latitude * 100).rounded() / 100
            self.longitude = (longitude * 100).rounded() / 100
        }

        public init(_ assessment: RideWeatherAssessment, updated: Date, latitude: Double, longitude: Double) {
            self.init(verdict: assessment.verdict, summary: assessment.summary, temperature: assessment.temperature,
                      updated: updated, latitude: latitude, longitude: longitude)
        }

        public func isFresh(at date: Date) -> Bool { date.timeIntervalSince(updated) < 3 * 3600 }
    }

    public var week: WeeklyRideSummary
    public var weeklyGoalMiles: Double
    /// Consecutive calendar weeks with at least one ride.
    public var weekStreak: Int
    public var streakIncludesCurrentWeek: Bool
    public var monthStart: Date
    public var monthDistance: Double
    public var totalDistance: Double
    public var lastRide: LastRide?
    public var habits: [Habit]
    public var weather: Weather?
    public var theme: String?
    public var rideActive: Bool

    public init(week: WeeklyRideSummary, weeklyGoalMiles: Double = defaultGoalMiles, weekStreak: Int = 0,
                streakIncludesCurrentWeek: Bool = false, monthStart: Date, monthDistance: Double = 0,
                totalDistance: Double = 0, lastRide: LastRide? = nil, habits: [Habit] = [], weather: Weather? = nil,
                theme: String? = nil, rideActive: Bool = false) {
        self.week = week
        self.weeklyGoalMiles = weeklyGoalMiles
        self.weekStreak = weekStreak
        self.streakIncludesCurrentWeek = streakIncludesCurrentWeek
        self.monthStart = monthStart
        self.monthDistance = monthDistance
        self.totalDistance = totalDistance
        self.lastRide = lastRide
        self.habits = habits
        self.weather = weather
        self.theme = theme
        self.rideActive = rideActive
    }

    public static func empty(at now: Date = .now, calendar: Calendar = .current) -> Self {
        RideWidgetSnapshot(week: WeeklyRideSummary(weekStart: WeeklyRideSummary.weekStart(containing: now, calendar: calendar)),
                           monthStart: monthStart(containing: now, calendar: calendar))
    }

    public static func make(rides: [Ride], rideActive: Bool = false, goalMiles: Double = defaultGoalMiles,
                            weather: Weather? = nil, theme: String? = nil, now: Date = .now,
                            calendar: Calendar = .current) -> Self {
        let completed = rides.filter { $0.endedAt != nil }
        let month = monthStart(containing: now, calendar: calendar)
        let thisWeek = WeeklyRideSummary.weekStart(containing: now, calendar: calendar)
        let ridden = Set(completed.map { WeeklyRideSummary.weekStart(containing: $0.startedAt, calendar: calendar) })
        let includesCurrent = ridden.contains(thisWeek)
        var cursor = includesCurrent ? thisWeek : calendar.date(byAdding: .weekOfYear, value: -1, to: thisWeek) ?? thisWeek
        var streak = 0
        while ridden.contains(cursor) {
            streak += 1
            guard let previous = calendar.date(byAdding: .weekOfYear, value: -1, to: cursor) else { break }
            cursor = previous
        }
        let last = completed.max { ($0.endedAt ?? $0.startedAt) < ($1.endedAt ?? $1.startedAt) }
        return RideWidgetSnapshot(
            week: WeeklyRideSummary.make(rides: completed, now: now, calendar: calendar),
            weeklyGoalMiles: min(max(goalMiles, goalRange.lowerBound), goalRange.upperBound),
            weekStreak: streak,
            streakIncludesCurrentWeek: includesCurrent,
            monthStart: month,
            monthDistance: completed.filter { $0.startedAt >= month && $0.startedAt <= now }.reduce(0) { $0 + $1.distance },
            totalDistance: completed.reduce(0) { $0 + $1.distance },
            lastRide: last.map {
                LastRide(startedAt: $0.startedAt, endedAt: $0.endedAt ?? $0.startedAt, distance: $0.distance,
                         movingDuration: $0.movingDuration, averageSpeed: $0.movingAverageSpeed)
            },
            habits: habits(from: completed, now: now, calendar: calendar),
            weather: weather,
            theme: theme,
            rideActive: rideActive
        )
    }

    /// The snapshot as it should read at `date`, rolling over stale week and month totals.
    public func current(at date: Date, calendar: Calendar = .current) -> Self {
        var copy = self
        let thisWeek = WeeklyRideSummary.weekStart(containing: date, calendar: calendar)
        if thisWeek != week.weekStart {
            let weeks = calendar.dateComponents([.weekOfYear], from: week.weekStart, to: thisWeek).weekOfYear ?? 2
            copy.weekStreak = weeks == 1 && streakIncludesCurrentWeek ? weekStreak : 0
            copy.streakIncludesCurrentWeek = false
            copy.week = week.current(at: date, calendar: calendar)
        }
        let month = Self.monthStart(containing: date, calendar: calendar)
        if month != monthStart {
            copy.monthStart = month
            copy.monthDistance = 0
        }
        return copy
    }

    public var goalProgress: Double { weeklyGoalMiles > 0 ? min(week.miles / weeklyGoalMiles, 1) : 0 }

    public var goalMet: Bool { week.miles >= weeklyGoalMiles }

    public var milesToGoal: Double { max(0, weeklyGoalMiles - week.miles) }

    static func monthStart(containing date: Date, calendar: Calendar) -> Date {
        calendar.dateInterval(of: .month, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    /// Start times repeated in the last eight weeks: the same weekday and hour at least twice,
    /// or the same hour on at least three days.
    static func habits(from rides: [Ride], now: Date, calendar: Calendar) -> [Habit] {
        let since = now.addingTimeInterval(-56 * 86_400)
        let recent = rides.filter { $0.startedAt >= since && $0.startedAt <= now }
        var slots: [Int: [Int: Int]] = [:]
        var hours: [Int: Set<Date>] = [:]
        for ride in recent {
            let parts = calendar.dateComponents([.weekday, .hour], from: ride.startedAt)
            guard let weekday = parts.weekday, let hour = parts.hour else { continue }
            slots[weekday, default: [:]][hour, default: 0] += 1
            hours[hour, default: []].insert(calendar.startOfDay(for: ride.startedAt))
        }
        var result: [Habit] = []
        for (weekday, byHour) in slots {
            for (hour, count) in byHour where count >= 2 {
                result.append(Habit(weekday: weekday, hour: hour, count: count))
            }
        }
        for (hour, days) in hours where days.count >= 3 {
            result.append(Habit(weekday: nil, hour: hour, count: days.count))
        }
        return result.sorted { ($0.weekday ?? 0, $0.hour) < ($1.weekday ?? 0, $1.hour) }
    }
}

/// Widgets ScooterLog offers. Raw values are the WidgetKit kinds.
public enum RideWidgetKind: String, CaseIterable, Sendable {
    case weeklyMiles = "WeeklyMiles"
    case weeklyGoal = "WeeklyGoal"
    case streak = "RideStreak"
    case lastRide = "LastRide"
    case weather = "RideWeather"
}

/// Scores from 0 to 1 telling the system when each widget deserves a spot at the top of a Smart Stack.
public enum RideWidgetRelevance {
    /// How strongly `date` falls in one of the rider's usual start times: from 45 minutes before
    /// a usual start until an hour after it.
    public static func habitScore(_ snapshot: RideWidgetSnapshot, at date: Date, calendar: Calendar = .current) -> Double {
        let parts = calendar.dateComponents([.weekday, .hour, .minute], from: date)
        guard let weekday = parts.weekday, let hour = parts.hour, let minute = parts.minute else { return 0 }
        let minuteOfDay = hour * 60 + minute
        var best = 0.0
        for habit in snapshot.habits {
            if let day = habit.weekday, day != weekday { continue }
            let offset = minuteOfDay - habit.hour * 60
            guard offset >= -45 && offset <= 60 else { continue }
            let strength = habit.weekday == nil ? min(0.8, 0.3 + 0.1 * Double(habit.count))
                                                : min(1, 0.5 + 0.15 * Double(habit.count))
            best = max(best, strength)
        }
        return best
    }

    public static func score(_ kind: RideWidgetKind, snapshot stored: RideWidgetSnapshot, at date: Date,
                             calendar: Calendar = .current) -> Double {
        let snapshot = stored.current(at: date, calendar: calendar)
        if snapshot.rideActive { return 0.05 }
        let habit = habitScore(snapshot, at: date, calendar: calendar)
        let weekEnd = WeeklyRideSummary.nextWeek(after: date, calendar: calendar)
        let finalDays = weekEnd.timeIntervalSince(date) <= 2 * 86_400
        let sinceRide = snapshot.lastRide.map { date.timeIntervalSince($0.endedAt) }
        let justRode = sinceRide.map { $0 >= 0 && $0 <= 2 * 3600 } ?? false

        switch kind {
        case .weather:
            guard let weather = snapshot.weather, weather.isFresh(at: date) else { return habit * 0.5 }
            switch weather.verdict {
            case .avoid: return max(0.9, habit)
            case .caution: return max(0.7, habit * 0.9)
            case .good: return habit * 0.8
            }
        case .lastRide:
            guard let sinceRide, sinceRide >= 0 else { return 0.05 }
            if sinceRide <= 2 * 3600 { return 0.9 }
            if sinceRide <= 6 * 3600 { return 0.4 }
            return 0.05
        case .weeklyGoal:
            if snapshot.goalMet { return justRode ? 0.85 : 0.1 }
            if justRode { return 0.6 }
            if finalDays { return max(0.6, habit * 0.6) }
            return habit * 0.4
        case .streak:
            if snapshot.weekStreak > 0 && !snapshot.streakIncludesCurrentWeek {
                return finalDays ? max(0.75, habit) : max(0.3, habit * 0.6)
            }
            return justRode && snapshot.streakIncludesCurrentWeek && snapshot.week.rideCount == 1 ? 0.7 : 0.1
        case .weeklyMiles:
            return justRode ? 0.5 : 0.1 + habit * 0.3
        }
    }

    /// Times at which a widget timeline should add entries so relevance can change during the day:
    /// the next hour boundaries, usual start windows, two and six hours after the last ride and the
    /// start of next week.
    public static func timelineDates(_ snapshot: RideWidgetSnapshot, from now: Date, hours: Int = 12,
                                     calendar: Calendar = .current) -> [Date] {
        var dates: Set<Date> = [now]
        let end = now.addingTimeInterval(Double(hours) * 3600)
        var hour = calendar.dateInterval(of: .hour, for: now)?.end ?? now
        while hour < end {
            dates.insert(hour)
            dates.insert(hour.addingTimeInterval(15 * 60))
            hour = hour.addingTimeInterval(3600)
        }
        if let last = snapshot.lastRide {
            for offset in [2.0, 6.0] { dates.insert(last.endedAt.addingTimeInterval(offset * 3600)) }
        }
        dates.insert(WeeklyRideSummary.nextWeek(after: now, calendar: calendar))
        return dates.filter { $0 >= now && $0 <= end }.sorted()
    }
}
