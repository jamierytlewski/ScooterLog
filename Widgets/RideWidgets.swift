import ScooterCore
import SwiftUI
import WidgetKit

// MARK: - Widgets

struct WeeklyMilesWidget: Widget {
    var body: some WidgetConfiguration {
        rideWidget(.weeklyMiles, name: "Distance this week", description: "Distance ridden since the start of the week.",
                   families: RideWidgetFamilies.large + RideWidgetFamilies.accessory) { WeeklyMilesView(snapshot: $0) }
    }
}

struct WeeklyGoalWidget: Widget {
    var body: some WidgetConfiguration {
        rideWidget(.weeklyGoal, name: "Weekly goal", description: "Progress toward your weekly mileage goal. Set the goal in ScooterLog settings.",
                   families: RideWidgetFamilies.small + RideWidgetFamilies.accessory) { WeeklyGoalView(snapshot: $0) }
    }
}

struct RideStreakWidget: Widget {
    var body: some WidgetConfiguration {
        rideWidget(.streak, name: "Ride streak", description: "Consecutive weeks with at least one ride.",
                   families: RideWidgetFamilies.small + RideWidgetFamilies.accessory) { RideStreakView(snapshot: $0) }
    }
}

struct LastRideWidget: Widget {
    var body: some WidgetConfiguration {
        rideWidget(.lastRide, name: "Last ride", description: "Distance, time and average speed of your latest ride.",
                   families: RideWidgetFamilies.large + RideWidgetFamilies.text) { LastRideView(snapshot: $0) }
    }
}

struct RideWeatherWidget: Widget {
    var body: some WidgetConfiguration {
        rideWidget(.weather, name: "Scooter weather", description: "Whether rain, ice or snow make it a bad time to ride.",
                   families: RideWidgetFamilies.large + RideWidgetFamilies.accessory) { RideWeatherWidgetView(snapshot: $0) }
    }
}

enum RideWidgetFamilies {
    #if os(watchOS)
    static let small: [WidgetFamily] = []
    static let large: [WidgetFamily] = []
    static let accessory: [WidgetFamily] = [.accessoryRectangular, .accessoryCircular, .accessoryCorner, .accessoryInline]
    #else
    static let small: [WidgetFamily] = [.systemSmall]
    static let large: [WidgetFamily] = [.systemSmall, .systemMedium]
    static let accessory: [WidgetFamily] = [.accessoryRectangular, .accessoryCircular, .accessoryInline]
    #endif
    static let text: [WidgetFamily] = [.accessoryRectangular, .accessoryInline]
}

@MainActor
private func rideWidget<Content: View>(
    _ kind: RideWidgetKind, name: String, description: String, families: [WidgetFamily],
    @ViewBuilder content: @escaping @MainActor @Sendable (RideWidgetSnapshot) -> Content
) -> some WidgetConfiguration {
    StaticConfiguration(kind: kind.rawValue, provider: RideWidgetProvider(kind: kind)) { entry in
        content(entry.snapshot)
            .containerBackground(for: .widget) { RideTheme.canvas }
    }
    .configurationDisplayName(name)
    .description(description)
    .supportedFamilies(families)
}

// MARK: - Shared pieces

extension WidgetFamily {
    var isMedium: Bool {
        #if os(watchOS)
        false
        #else
        self == .systemMedium
        #endif
    }
}

extension RideWidgetSnapshot {
    var accent: Color { (theme.flatMap(RideTheme.init(rawValue:)) ?? .tronBlue).color }
    var ridesText: String { week.rideCount == 1 ? "1 ride" : "\(week.rideCount) rides" }
    var unit: RideUnitSystem { .selected }
    var weekText: String { distanceNumber(week.distance) }
    var goalText: String { distanceNumber(weeklyGoalMiles * RideUnits.metersPerMile) }
    var streakText: String { weekStreak == 1 ? "1 week" : "\(weekStreak) weeks" }
    func distanceNumber(_ meters: Double) -> String { String(format: "%.1f", meters / unit.metersPerUnit) }
}

private func duration(_ seconds: TimeInterval) -> String {
    Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes], width: .narrow))
}

/// Title row and a big number used by the Home Screen sizes.
private struct BigStat: View {
    let title: String
    let systemImage: String
    let value: String
    let caption: String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(accent)
            Spacer(minLength: 0)
            Text(value)
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .foregroundStyle(.white)
            Text(caption)
                .font(.caption)
                .foregroundStyle(RideTheme.secondaryText)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
    }
}

/// Header, value and caption lines for the rectangular Lock Screen and Smart Stack size.
private struct RectangularStat: View {
    let title: String
    let systemImage: String
    let value: String
    let caption: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .widgetAccentable()
            Text(value)
                .font(.title3.weight(.bold))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Weekly miles

struct WeeklyMilesView: View {
    let snapshot: RideWidgetSnapshot
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let value = snapshot.weekText
        let unit = snapshot.unit.distanceSymbol
        switch family {
        case .accessoryInline:
            Label("\(value) \(unit) this week", systemImage: "scooter")
        case .accessoryCircular:
            VStack(spacing: 0) {
                Image(systemName: "scooter").font(.caption2).widgetAccentable()
                Text(value).font(.headline).monospacedDigit().minimumScaleFactor(0.5)
                Text(unit).font(.caption2)
            }
            .accessibilityLabel("\(value) \(unit) this week")
        #if os(watchOS)
        case .accessoryCorner:
            Text(value).font(.title3.bold()).monospacedDigit()
                .widgetCurvesContent()
                .widgetLabel { Text("\(unit) this week") }
        #endif
        case .accessoryRectangular:
            RectangularStat(title: "This week", systemImage: "scooter", value: "\(value) \(unit)", caption: snapshot.ridesText)
        case _ where family.isMedium:
            HStack(spacing: 16) {
                BigStat(title: "This week", systemImage: "scooter", value: value,
                        caption: "\(unit) · \(snapshot.ridesText)", accent: snapshot.accent)
                DailyMilesChart(snapshot: snapshot)
            }
        default:
            BigStat(title: "This week", systemImage: "scooter", value: value,
                    caption: "\(unit) · \(snapshot.ridesText)", accent: snapshot.accent)
        }
    }
}

private struct DailyMilesChart: View {
    let snapshot: RideWidgetSnapshot

    var body: some View {
        let calendar = Calendar.current
        let week = snapshot.week
        let peak = max(week.dailyDistance.max() ?? 0, 1)
        let today = calendar.dateComponents([.day], from: week.weekStart, to: calendar.startOfDay(for: .now)).day ?? -1
        HStack(alignment: .bottom, spacing: 6) {
            ForEach(0..<7, id: \.self) { day in
                let date = calendar.date(byAdding: .day, value: day, to: week.weekStart) ?? week.weekStart
                VStack(spacing: 4) {
                    Capsule()
                        .fill(day == today ? snapshot.accent : snapshot.accent.opacity(0.45))
                        .frame(height: max(4, 70 * week.dailyDistance[day] / peak))
                        .frame(maxHeight: 70, alignment: .bottom)
                    Text(calendar.veryShortWeekdaySymbols[calendar.component(.weekday, from: date) - 1])
                        .font(.caption2)
                        .foregroundStyle(day == today ? .white : RideTheme.secondaryText)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }
}

// MARK: - Weekly goal

struct WeeklyGoalView: View {
    let snapshot: RideWidgetSnapshot
    @Environment(\.widgetFamily) private var family

    private var caption: String {
        snapshot.goalMet ? "Goal reached" : "\(snapshot.distanceNumber(snapshot.milesToGoal * RideUnits.metersPerMile)) \(snapshot.unit.distanceSymbol) to go"
    }

    var body: some View {
        switch family {
        case .accessoryInline:
            Label("\(snapshot.weekText)/\(snapshot.goalText) \(snapshot.unit.distanceSymbol) goal", systemImage: "target")
        case .accessoryCircular:
            Gauge(value: snapshot.goalProgress) {
                Image(systemName: "scooter")
            } currentValueLabel: {
                Text(snapshot.weekText).monospacedDigit()
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .widgetAccentable()
            .accessibilityLabel("\(snapshot.weekText) of \(snapshot.goalText) \(snapshot.unit.distanceSymbol)")
        #if os(watchOS)
        case .accessoryCorner:
            Image(systemName: snapshot.goalMet ? "checkmark" : "scooter")
                .font(.title3)
                .widgetLabel {
                    Gauge(value: snapshot.goalProgress) { Text("Goal") }
                        .tint(snapshot.accent)
                }
        #endif
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Label("Weekly goal", systemImage: "target").font(.caption.weight(.semibold)).widgetAccentable()
                Text("\(snapshot.weekText) of \(snapshot.goalText) \(snapshot.unit.distanceSymbol)").font(.headline).monospacedDigit()
                Gauge(value: snapshot.goalProgress) { EmptyView() }
                    .gaugeStyle(.accessoryLinearCapacity)
                    .widgetAccentable()
            }
            .accessibilityElement(children: .combine)
        default:
            VStack(alignment: .leading, spacing: 8) {
                Label("Weekly goal", systemImage: "target")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(snapshot.accent)
                ZStack {
                    Circle().stroke(snapshot.accent.opacity(0.25), lineWidth: 10)
                    Circle()
                        .trim(from: 0, to: snapshot.goalProgress)
                        .stroke(snapshot.accent, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 0) {
                        Text(snapshot.weekText)
                            .font(.title2.weight(.bold)).monospacedDigit()
                            .foregroundStyle(.white)
                        Text("of \(snapshot.goalText) \(snapshot.unit.distanceSymbol)").font(.caption2).foregroundStyle(RideTheme.secondaryText)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                Text(caption).font(.caption).foregroundStyle(RideTheme.secondaryText)
            }
            .accessibilityElement(children: .combine)
        }
    }
}

// MARK: - Streak

struct RideStreakView: View {
    let snapshot: RideWidgetSnapshot
    @Environment(\.widgetFamily) private var family

    private var atRisk: Bool { snapshot.weekStreak > 0 && !snapshot.streakIncludesCurrentWeek }
    private var caption: String {
        if snapshot.weekStreak == 0 { return "Ride this week to start one" }
        return atRisk ? "Ride this week to keep it" : "This week counts"
    }

    var body: some View {
        switch family {
        case .accessoryInline:
            Label("\(snapshot.streakText) streak", systemImage: "flame")
        case .accessoryCircular:
            VStack(spacing: 0) {
                Image(systemName: atRisk ? "flame" : "flame.fill").font(.caption).widgetAccentable()
                Text("\(snapshot.weekStreak)").font(.title3.bold()).monospacedDigit()
                Text("wk").font(.caption2)
            }
            .accessibilityLabel("\(snapshot.streakText) streak")
        #if os(watchOS)
        case .accessoryCorner:
            Image(systemName: "flame.fill").font(.title3).widgetAccentable()
                .widgetLabel { Text("\(snapshot.streakText) streak") }
        #endif
        case .accessoryRectangular:
            RectangularStat(title: "Ride streak", systemImage: "flame.fill", value: snapshot.streakText, caption: caption)
        default:
            BigStat(title: "Ride streak", systemImage: "flame.fill", value: "\(snapshot.weekStreak)",
                    caption: "\(snapshot.weekStreak == 1 ? "week" : "weeks") · \(caption)", accent: snapshot.accent)
        }
    }
}

// MARK: - Last ride

struct LastRideView: View {
    let snapshot: RideWidgetSnapshot
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let ride = snapshot.lastRide {
            content(ride)
        } else {
            switch family {
            case .accessoryInline: Label("No rides yet", systemImage: "scooter")
            case .accessoryRectangular:
                RectangularStat(title: "Last ride", systemImage: "scooter", value: "No rides yet", caption: "Start one in ScooterLog")
            default:
                BigStat(title: "Last ride", systemImage: "scooter", value: "--", caption: "No rides yet", accent: snapshot.accent)
            }
        }
    }

    @ViewBuilder
    private func content(_ ride: RideWidgetSnapshot.LastRide) -> some View {
        let distance = snapshot.distanceNumber(ride.distance)
        let unit = snapshot.unit.distanceSymbol
        let speed = ride.isTrimmedEstimate == true ? "Unavailable" : RideUnits.speed(ride.averageSpeed)
        let distanceCaption = ride.isTrimmedEstimate == true ? "\(unit) estimated" : unit
        let when = ride.endedAt.formatted(.relative(presentation: .named))
        switch family {
        case .accessoryInline:
            Label("Last ride \(distance) \(distanceCaption)", systemImage: "scooter")
        case .accessoryRectangular:
            RectangularStat(title: "Last ride", systemImage: "scooter", value: "\(distance) \(unit)",
                            caption: ride.isTrimmedEstimate == true ? "Estimated distance" : "\(duration(ride.duration)) · \(speed)")
        case _ where family.isMedium:
            HStack(spacing: 16) {
                BigStat(title: "Last ride", systemImage: "scooter", value: distance, caption: "\(distanceCaption) · \(when)",
                        accent: snapshot.accent)
                VStack(alignment: .leading, spacing: 10) {
                    detail("Time", duration(ride.duration))
                    detail("Moving avg", speed)
                    detail("This month", "\(snapshot.distanceNumber(snapshot.monthDistance)) \(unit)")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        default:
            BigStat(title: "Last ride", systemImage: "scooter", value: distance,
                    caption: "\(distanceCaption) · \(duration(ride.duration)) · \(when)", accent: snapshot.accent)
        }
    }

    private func detail(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.caption2).foregroundStyle(RideTheme.secondaryText)
            Text(value).font(.headline).monospacedDigit().foregroundStyle(.white)
        }
    }
}

// MARK: - Weather

struct RideWeatherWidgetView: View {
    let snapshot: RideWidgetSnapshot
    @Environment(\.widgetFamily) private var family

    private var weather: RideWidgetSnapshot.Weather? {
        snapshot.weather.flatMap { $0.isFresh(at: .now) ? $0 : nil }
    }

    var body: some View {
        if let weather {
            content(weather)
        } else {
            switch family {
            case .accessoryInline: Label("Open ScooterLog for weather", systemImage: "cloud")
            case .accessoryCircular: Image(systemName: "cloud").font(.title2).accessibilityLabel("Weather unavailable")
            #if os(watchOS)
            case .accessoryCorner:
                Image(systemName: "cloud").font(.title3).widgetLabel { Text("Open ScooterLog") }
            #endif
            case .accessoryRectangular:
                RectangularStat(title: "Scooter weather", systemImage: "cloud", value: "No forecast",
                                caption: "Open ScooterLog to check")
            default:
                BigStat(title: "Scooter weather", systemImage: "cloud", value: "--",
                        caption: "Open ScooterLog to check the forecast", accent: snapshot.accent)
            }
        }
    }

    @ViewBuilder
    private func content(_ weather: RideWidgetSnapshot.Weather) -> some View {
        let symbol = Self.symbol(weather.verdict)
        let temperature = weather.temperature.map(RideWeather.temperature) ?? ""
        switch family {
        case .accessoryInline:
            Label(Self.shortTitle(weather.verdict), systemImage: symbol)
        case .accessoryCircular:
            VStack(spacing: 0) {
                Image(systemName: symbol).font(.title3).widgetAccentable()
                Text(temperature).font(.caption).monospacedDigit()
            }
            .accessibilityLabel(weather.verdict.title)
        #if os(watchOS)
        case .accessoryCorner:
            Image(systemName: symbol).font(.title3).widgetAccentable()
                .widgetLabel { Text(Self.shortTitle(weather.verdict)) }
        #endif
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 0) {
                Label(weather.verdict.title, systemImage: symbol)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .widgetAccentable()
                Text(weather.displaySummary)
                    .font(.caption)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                Text(" Weather · \(temperature)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        default:
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: symbol)
                        .font(.title2)
                        .foregroundStyle(Self.color(weather.verdict))
                    Spacer()
                    Text(temperature).font(.title3.weight(.semibold)).foregroundStyle(.white)
                }
                Spacer(minLength: 0)
                Text(weather.verdict.title)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                Text(weather.displaySummary)
                    .font(.caption)
                    .foregroundStyle(RideTheme.secondaryText)
                    .lineLimit(family.isMedium ? 2 : 3)
                Text(" Weather").font(.caption2).foregroundStyle(RideTheme.secondaryText)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .accessibilityElement(children: .combine)
        }
    }

    static func symbol(_ verdict: RideWeatherVerdict) -> String {
        switch verdict {
        case .good: "checkmark.circle.fill"
        case .caution: "exclamationmark.triangle.fill"
        case .avoid: "xmark.octagon.fill"
        }
    }

    static func shortTitle(_ verdict: RideWeatherVerdict) -> String {
        switch verdict {
        case .good: "Good to ride"
        case .caution: "Ride carefully"
        case .avoid: "Skip the ride"
        }
    }

    static func color(_ verdict: RideWeatherVerdict) -> Color {
        switch verdict {
        case .good: .green
        case .caution: .orange
        case .avoid: .red
        }
    }
}

// MARK: - Start ride control

@available(iOS 18.0, watchOS 26.0, *)
struct StartRideControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "StartRideControl") {
            ControlWidgetButton(action: StartRideControlIntent()) {
                Label("Start ride", systemImage: "scooter")
            }
        }
        .displayName("Start ride")
        .description("Open ScooterLog and start recording a ride.")
    }
}

#if DEBUG && os(iOS)
#Preview("Weekly", as: .systemMedium) { WeeklyMilesWidget() } timeline: {
    RideWidgetEntry(date: .now, snapshot: .preview, relevance: nil)
}

#Preview("Goal", as: .systemSmall) { WeeklyGoalWidget() } timeline: {
    RideWidgetEntry(date: .now, snapshot: .preview, relevance: nil)
}

#Preview("Weather", as: .accessoryRectangular) { RideWeatherWidget() } timeline: {
    RideWidgetEntry(date: .now, snapshot: .preview, relevance: nil)
}
#endif

#if DEBUG && os(watchOS)
#Preview("Smart Stack weather", as: .accessoryRectangular) { RideWeatherWidget() } timeline: {
    RideWidgetEntry(date: .now, snapshot: .preview, relevance: nil)
}

#Preview("Goal ring", as: .accessoryCircular) { WeeklyGoalWidget() } timeline: {
    RideWidgetEntry(date: .now, snapshot: .preview, relevance: nil)
}
#endif
