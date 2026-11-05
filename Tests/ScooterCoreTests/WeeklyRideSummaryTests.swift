import Foundation
import Testing
@testable import ScooterCore

struct WeeklyRideSummaryTests {
    var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Detroit")!
        calendar.firstWeekday = 2
        return calendar
    }()

    /// Wednesday, Nov 4 2026, 12:00 local.
    var now: Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: 12))! }

    func ride(day: Int, hour: Int = 8, meters: Double, finished: Bool = true) -> Ride {
        let start = calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour))!
        var ride = Ride(owner: "phone", startedAt: start)
        for (index, step) in stride(from: 0.0, through: meters, by: 40).enumerated() {
            let time = start.addingTimeInterval(Double(index) * 10)
            _ = ride.append(LocationSample(latitude: step / 111_195, longitude: 0, timestamp: time, accuracy: 5, speed: 4),
                            receivedAt: time)
        }
        if finished { ride.end(at: start.addingTimeInterval(meters / 4 + 10)) }
        return ride
    }

    @Test func totalsOnlyCompletedRidesInTheCurrentWeek() {
        let rides = [ride(day: 2, meters: 1_600), ride(day: 4, meters: 800), ride(day: 4, hour: 9, meters: 400, finished: false),
                     ride(day: 1, meters: 5_000), ride(day: 9, meters: 5_000)]
        let summary = WeeklyRideSummary.make(rides: rides, now: now, calendar: calendar)
        #expect(summary.weekStart == calendar.date(from: DateComponents(year: 2026, month: 11, day: 2))!)
        #expect(summary.rideCount == 2)
        #expect(abs(summary.dailyDistance[0] - 1_600) < 1)
        #expect(abs(summary.dailyDistance[2] - 800) < 1)
        #expect(abs(summary.distance - 2_400) < 1)
        #expect(summary.milesText == "1.5")
    }

    @Test func staleWeekResetsToZero() {
        let summary = WeeklyRideSummary.make(rides: [ride(day: 2, meters: 1_600)], now: now, calendar: calendar)
        let nextMonday = WeeklyRideSummary.nextWeek(after: now, calendar: calendar)
        #expect(nextMonday == calendar.date(from: DateComponents(year: 2026, month: 11, day: 9))!)
        #expect(summary.current(at: now, calendar: calendar) == summary)
        let reset = summary.current(at: nextMonday, calendar: calendar)
        #expect(reset.distance == 0 && reset.rideCount == 0)
        #expect(reset.weekStart == nextMonday)
    }

    @Test func roundTripsThroughJSON() throws {
        let summary = WeeklyRideSummary.make(rides: [ride(day: 3, meters: 800)], now: now, calendar: calendar)
        let decoded = try JSONDecoder().decode(WeeklyRideSummary.self, from: JSONEncoder().encode(summary))
        #expect(decoded == summary)
    }
}
