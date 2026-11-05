import CoreLocation
import ScooterCore
import WidgetKit

struct RideWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: RideWidgetSnapshot
    let relevance: TimelineEntryRelevance?
}

/// One timeline per widget kind. Each entry carries a relevance score so iOS and watchOS
/// can float the widget to the top of a Smart Stack at the right moment.
struct RideWidgetProvider: TimelineProvider {
    let kind: RideWidgetKind

    func placeholder(in context: Context) -> RideWidgetEntry {
        RideWidgetEntry(date: .now, snapshot: .preview, relevance: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (RideWidgetEntry) -> Void) {
        let stored = RideWidgetStore.load()
        let snapshot = stored ?? (context.isPreview ? .preview : .empty())
        completion(RideWidgetEntry(date: .now, snapshot: snapshot.current(at: .now), relevance: nil))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RideWidgetEntry>) -> Void) {
        let kind = kind
        let reply = UncheckedCompletion(completion)
        Task {
            var snapshot = RideWidgetStore.load() ?? .empty()
            if kind == .weather { snapshot = await Self.refreshingWeather(snapshot) }
            reply.call(Self.timeline(kind, snapshot: snapshot, now: .now))
        }
    }

    static func timeline(_ kind: RideWidgetKind, snapshot: RideWidgetSnapshot, now: Date) -> Timeline<RideWidgetEntry> {
        let dates = RideWidgetRelevance.timelineDates(snapshot, from: now)
        let entries = dates.enumerated().map { index, date in
            let next = index + 1 < dates.count ? dates[index + 1] : date.addingTimeInterval(3600)
            let score = RideWidgetRelevance.score(kind, snapshot: snapshot, at: date)
            return RideWidgetEntry(date: date, snapshot: snapshot.current(at: date),
                                   relevance: TimelineEntryRelevance(score: Float(score), duration: next.timeIntervalSince(date)))
        }
        // Weather goes stale quickly; everything else only changes when the app publishes new rides.
        return Timeline(entries: entries, policy: kind == .weather ? .after(now.addingTimeInterval(30 * 60)) : .atEnd)
    }

    /// Refreshes a forecast older than 30 minutes for the last location the app checked.
    private static func refreshingWeather(_ snapshot: RideWidgetSnapshot) async -> RideWidgetSnapshot {
        guard let weather = snapshot.weather, Date.now.timeIntervalSince(weather.updated) > 30 * 60 else { return snapshot }
        let location = CLLocation(latitude: weather.latitude, longitude: weather.longitude)
        guard let report = try? await RideWeatherService.report(for: location) else { return snapshot }
        var updated = snapshot
        updated.weather = RideWidgetSnapshot.Weather(RideWeather.assess(report), updated: .now,
                                                     latitude: weather.latitude, longitude: weather.longitude)
        if var stored = RideWidgetStore.load() {
            stored.weather = updated.weather
            RideWidgetStore.save(stored)
        }
        return updated
    }
}

/// WidgetKit's completion handlers predate Sendable; they are safe to call from any thread.
private struct UncheckedCompletion<Value>: @unchecked Sendable {
    let completion: (Value) -> Void
    init(_ completion: @escaping (Value) -> Void) { self.completion = completion }
    func call(_ value: Value) { completion(value) }
}

extension RideWidgetSnapshot {
    static var preview: RideWidgetSnapshot {
        let now = Date.now
        var snapshot = RideWidgetSnapshot.empty(at: now)
        snapshot.week.dailyDistance = [4_800, 0, 9_650, 3_200, 0, 0, 0]
        snapshot.week.rideCount = 3
        snapshot.weeklyGoalMiles = 15
        snapshot.weekStreak = 4
        snapshot.streakIncludesCurrentWeek = true
        snapshot.monthDistance = 42_000
        snapshot.totalDistance = 310_000
        snapshot.lastRide = LastRide(startedAt: now.addingTimeInterval(-5_400), endedAt: now.addingTimeInterval(-3_600),
                                     distance: 9_650, movingDuration: 1_500, averageSpeed: 6.4)
        snapshot.weather = Weather(verdict: .caution, summary: "Rain 60% around 5:00 PM", temperature: 11,
                                   updated: now, latitude: 0, longitude: 0)
        return snapshot
    }
}
