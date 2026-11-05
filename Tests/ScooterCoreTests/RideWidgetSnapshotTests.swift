import Foundation
import Testing
@testable import ScooterCore

struct RideWidgetSnapshotTests {
    var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Detroit")!
        calendar.firstWeekday = 2
        return calendar
    }()

    func date(_ day: Int, _ hour: Int, _ minute: Int = 0, month: Int = 11) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
    }

    func ride(_ start: Date, meters: Double = 1_600) -> Ride {
        var ride = Ride(owner: "phone", startedAt: start)
        for (index, step) in stride(from: 0.0, through: meters, by: 40).enumerated() {
            let time = start.addingTimeInterval(Double(index) * 10)
            _ = ride.append(LocationSample(latitude: step / 111_195, longitude: 0, timestamp: time, accuracy: 5, speed: 4),
                            receivedAt: time)
        }
        ride.end(at: start.addingTimeInterval(meters / 4 + 10))
        return ride
    }

    /// Wednesday Nov 4 2026, 12:00.
    var now: Date { date(4, 12) }

    @Test func streakCountsConsecutiveWeeksAndSurvivesAnEmptyCurrentWeek() {
        let rides = [ride(date(28, 8, month: 10)), ride(date(21, 8, month: 10)), ride(date(7, 8, month: 10))]
        let snapshot = RideWidgetSnapshot.make(rides: rides, now: now, calendar: calendar)
        #expect(snapshot.weekStreak == 2)
        #expect(!snapshot.streakIncludesCurrentWeek)

        let withThisWeek = RideWidgetSnapshot.make(rides: rides + [ride(date(3, 8))], now: now, calendar: calendar)
        #expect(withThisWeek.weekStreak == 3)
        #expect(withThisWeek.streakIncludesCurrentWeek)
    }

    @Test func rollsOverWeekStreakAndMonth() {
        let snapshot = RideWidgetSnapshot.make(rides: [ride(date(3, 8)), ride(date(27, 8, month: 10))], now: now, calendar: calendar)
        #expect(snapshot.weekStreak == 2)
        let nextWeek = snapshot.current(at: date(10, 9), calendar: calendar)
        #expect(nextWeek.weekStreak == 2 && !nextWeek.streakIncludesCurrentWeek)
        #expect(nextWeek.week.distance == 0)
        let twoWeeks = snapshot.current(at: date(17, 9), calendar: calendar)
        #expect(twoWeeks.weekStreak == 0)
        #expect(abs(snapshot.monthDistance - 1_600) < 1)
        #expect(snapshot.current(at: date(1, 9, month: 12), calendar: calendar).monthDistance == 0)
    }

    @Test func goalProgressAndLastRide() {
        let rides = [ride(date(2, 8), meters: 8_000), ride(date(3, 17), meters: 4_000)]
        let snapshot = RideWidgetSnapshot.make(rides: rides, goalMiles: 10, now: now, calendar: calendar)
        #expect(abs(snapshot.goalProgress - 12_000 / RideUnits.metersPerMile / 10) < 0.001)
        #expect(!snapshot.goalMet)
        #expect(snapshot.lastRide?.startedAt == date(3, 17))
        #expect(abs((snapshot.lastRide?.averageSpeed ?? 0) - 4) < 0.1)
        #expect(RideWidgetSnapshot.make(rides: [], goalMiles: 1, now: now, calendar: calendar).weeklyGoalMiles == 5)
    }

    @Test func learnsUsualStartTimes() {
        let mondays = [ride(date(26, 8, 5, month: 10)), ride(date(2, 8, 10))]
        let evenings = [ride(date(3, 18)), ride(date(29, 18, month: 10)), ride(date(30, 18, 30, month: 10))]
        let snapshot = RideWidgetSnapshot.make(rides: mondays + evenings, now: now, calendar: calendar)
        #expect(snapshot.habits.contains(.init(weekday: 2, hour: 8, count: 2)))
        #expect(snapshot.habits.contains(.init(weekday: nil, hour: 18, count: 3)))

        #expect(RideWidgetRelevance.habitScore(snapshot, at: date(9, 7, 30), calendar: calendar) == 0.8)
        #expect(RideWidgetRelevance.habitScore(snapshot, at: date(10, 7, 30), calendar: calendar) == 0)
        #expect(RideWidgetRelevance.habitScore(snapshot, at: date(4, 17, 30), calendar: calendar) > 0.5)
        #expect(RideWidgetRelevance.habitScore(snapshot, at: date(4, 20), calendar: calendar) == 0)
    }

    @Test func weatherWidgetSurfacesForBadWeatherOrUsualRideTimes() {
        let rides = [ride(date(26, 8, month: 10)), ride(date(2, 8))]
        var snapshot = RideWidgetSnapshot.make(rides: rides, now: now, calendar: calendar)
        snapshot.weather = .init(verdict: .good, summary: "Dry", temperature: 10, updated: date(9, 7), latitude: 42.33, longitude: -83.05)
        #expect(RideWidgetRelevance.score(.weather, snapshot: snapshot, at: date(9, 7, 45), calendar: calendar) >= 0.6)
        #expect(RideWidgetRelevance.score(.weather, snapshot: snapshot, at: date(9, 12), calendar: calendar) == 0)

        snapshot.weather?.verdict = .avoid
        #expect(RideWidgetRelevance.score(.weather, snapshot: snapshot, at: date(9, 9), calendar: calendar) >= 0.9)
        #expect(RideWidgetRelevance.score(.weather, snapshot: snapshot, at: date(9, 12), calendar: calendar) < 0.5,
                "A stale forecast must not keep the widget on top")
        snapshot.rideActive = true
        #expect(RideWidgetRelevance.score(.weather, snapshot: snapshot, at: date(9, 9), calendar: calendar) < 0.1)
    }

    @Test func rideWidgetsSurfaceAfterARideAndWhenTheStreakIsAtRisk() {
        let snapshot = RideWidgetSnapshot.make(rides: [ride(date(4, 10))], goalMiles: 5, now: now, calendar: calendar)
        #expect(RideWidgetRelevance.score(.lastRide, snapshot: snapshot, at: date(4, 11), calendar: calendar) == 0.9)
        #expect(RideWidgetRelevance.score(.lastRide, snapshot: snapshot, at: date(4, 20), calendar: calendar) == 0.05)
        #expect(RideWidgetRelevance.score(.weeklyGoal, snapshot: snapshot, at: date(4, 11), calendar: calendar) == 0.6)

        let lastWeekOnly = RideWidgetSnapshot.make(rides: [ride(date(28, 8, month: 10))], now: now, calendar: calendar)
        #expect(RideWidgetRelevance.score(.streak, snapshot: lastWeekOnly, at: date(7, 10), calendar: calendar) >= 0.75)
        #expect(RideWidgetRelevance.score(.streak, snapshot: lastWeekOnly, at: date(4, 13), calendar: calendar) < 0.75)
    }

    @Test func timelineCoversHourBoundariesAndRideFollowUps() {
        let snapshot = RideWidgetSnapshot.make(rides: [ride(date(4, 11))], now: now, calendar: calendar)
        let dates = RideWidgetRelevance.timelineDates(snapshot, from: now, hours: 6, calendar: calendar)
        #expect(dates.first == now)
        #expect(dates.contains(date(4, 13)) && dates.contains(date(4, 13, 15)))
        #expect(dates.contains(snapshot.lastRide!.endedAt.addingTimeInterval(2 * 3600)))
        #expect(dates == dates.sorted() && dates.allSatisfy { $0 <= now.addingTimeInterval(6 * 3600) })
    }

    @Test func weatherLocationIsCoarse() {
        let weather = RideWidgetSnapshot.Weather(verdict: .good, summary: "", temperature: nil, updated: now,
                                                 latitude: 42.331427, longitude: -83.045754)
        #expect(weather.latitude == 42.33 && weather.longitude == -83.05)
    }
}
