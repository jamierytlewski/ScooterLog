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
                smallView
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
                .padding()
            }
        }
        .activitySystemActionForegroundColor((context.state.theme ?? .tronBlue).color)
        .foregroundStyle(.primary)
    }

    /// Watch Smart Stack and CarPlay: two short lines inside the system margins.
    private var smallView: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                RideActivitySymbol(context: context)
                RideElapsed(context: context)
                    .foregroundStyle((context.state.theme ?? .tronBlue).color)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                if context.state.endedAt != nil {
                    Image(systemName: "checkmark.circle").accessibilityLabel("Saved")
                }
            }
            .font(.headline.monospacedDigit())
            Text(isStale ? "GPS stale" : RideUnits.distance(context.state.distance))
                .font(.title3.weight(.semibold).monospacedDigit())
                .accessibilityLabel(isStale ? "Distance unavailable, GPS stale"
                                    : "Distance \(RideUnits.distance(context.state.distance))")
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var isStale: Bool { context.state.endedAt == nil && context.isStale }

    private var status: some View {
        Label(context.state.endedAt != nil ? "Saved" : isStale ? "GPS stale" : "Ride active",
              systemImage: context.state.endedAt != nil ? "checkmark.circle" : isStale ? "location.slash" : "record.circle")
    }
}

#if DEBUG
#Preview("Ride", as: .content, using: RideActivityAttributes(rideID: UUID(), startedAt: .now.addingTimeInterval(-3_725), owner: "iPhone")) {
    ScooterRideWidget()
} contentStates: {
    RideActivityAttributes.ContentState(distance: 12_874, speed: 6.2, stopped: 95, updatedAt: .now, endedAt: nil, theme: nil)
    RideActivityAttributes.ContentState(distance: 12_874, speed: nil, stopped: 95, updatedAt: .now, endedAt: .now, theme: nil)
}
#endif
