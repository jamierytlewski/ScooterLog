import ActivityKit
import ScooterCore
import SwiftUI
import WidgetKit

@main
struct ScooterWidgets: WidgetBundle {
    var body: some Widget { ScooterRideWidget() }
}

struct ScooterRideWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RideActivityAttributes.self) { context in
            RideActivityView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label { Text("ScooterLog") } icon: { RideActivitySymbol(context: context) }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(RideUnits.distance(context.state.distance))
                        .monospacedDigit()
                        .accessibilityLabel("Distance \(RideUnits.distance(context.state.distance))")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        RideElapsed(context: context)
                        Spacer()
                        Text(context.isStale && context.state.endedAt == nil ? "GPS stale" : context.attributes.owner)
                    }
                }
            } compactLeading: {
                RideActivitySymbol(context: context)
            } compactTrailing: {
                CompactRideDistance(context: context)
            } minimal: {
                RideActivitySymbol(context: context)
            }
        }
        .supplementalActivityFamilies([.small])
    }

}

private struct RideActivitySymbol: View {
    let context: ActivityViewContext<RideActivityAttributes>

    var body: some View {
        Image(systemName: context.isStale && context.state.endedAt == nil ? "location.slash" : "scooter")
            .foregroundStyle((context.state.theme ?? .tronBlue).color)
            .accessibilityLabel(context.isStale && context.state.endedAt == nil ? "Scooter ride, GPS stale" : "Scooter ride")
    }
}

private struct CompactRideDistance: View {
    let context: ActivityViewContext<RideActivityAttributes>
    @Environment(\.isDynamicIslandLimitedInWidth) private var limitedWidth

    var body: some View {
        if !limitedWidth {
            Text(context.isStale && context.state.endedAt == nil ? "--" : RideUnits.distance(context.state.distance))
                .font(.caption.monospacedDigit())
                .accessibilityLabel(context.isStale && context.state.endedAt == nil
                                    ? "Distance unavailable, GPS stale"
                                    : "Distance \(RideUnits.distance(context.state.distance))")
        }
    }
}

private struct RideElapsed: View {
    let context: ActivityViewContext<RideActivityAttributes>

    var body: some View {
        elapsedText.monospacedDigit()
            .accessibilityLabel("Elapsed time")
            .accessibilityValue(elapsedText)
    }

    private var elapsedText: Text {
        if let end = context.state.endedAt {
            return Text(Duration.seconds(end.timeIntervalSince(context.attributes.startedAt)), format: .time(pattern: .hourMinuteSecond))
        } else {
            return Text(timerInterval: context.attributes.startedAt...Date.distantFuture, countsDown: false)
        }
    }

}

private struct RideActivityView: View {
    let context: ActivityViewContext<RideActivityAttributes>
    @Environment(\.activityFamily) private var family

    var body: some View {
        Group {
            if family == .small {
                VStack(alignment: .leading, spacing: 4) {
                    Label { Text("ScooterLog") } icon: { RideActivitySymbol(context: context) }
                        .font(.caption)
                    RideElapsed(context: context).font(.headline.monospacedDigit())
                        .foregroundStyle((context.state.theme ?? .tronBlue).color)
                    Text(RideUnits.distance(context.state.distance))
                        .font(.title3.monospacedDigit())
                        .accessibilityLabel("Distance \(RideUnits.distance(context.state.distance))")
                    status.font(.caption)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label { Text("ScooterLog • \(context.attributes.owner)") } icon: {
                            RideActivitySymbol(context: context)
                        }
                        Spacer()
                        status
                    }.font(.caption)
                    HStack {
                        RideElapsed(context: context)
                            .foregroundStyle((context.state.theme ?? .tronBlue).color)
                        Spacer()
                        Text(RideUnits.distance(context.state.distance))
                            .accessibilityLabel("Distance \(RideUnits.distance(context.state.distance))")
                    }.font(.title2.monospacedDigit())
                    Text(isStale ? "Open app for current metrics" : "Stopped estimate: \(Int(context.state.stopped)) sec")
                        .font(.caption)
                }
            }
        }
        .padding()
        .activitySystemActionForegroundColor((context.state.theme ?? .tronBlue).color)
        .foregroundStyle(.primary)
    }

    private var isStale: Bool { context.state.endedAt == nil && context.isStale }

    private var status: some View {
        Label(context.state.endedAt != nil ? "Saved" : isStale ? "GPS stale" : "Ride active",
              systemImage: context.state.endedAt != nil ? "checkmark.circle" : isStale ? "location.slash" : "record.circle")
    }
}
