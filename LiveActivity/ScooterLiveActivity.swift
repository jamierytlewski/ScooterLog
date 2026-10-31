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
                DynamicIslandExpandedRegion(.leading) { Label("ScooterLog", systemImage: "scooter") }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(RideUnits.distance(context.state.distance))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        RideElapsed(context: context)
                        Spacer()
                        Text(context.isStale ? "GPS stale" : context.attributes.owner)
                    }
                }
            } compactLeading: {
                Image(systemName: "scooter")
            } compactTrailing: {
                Text(context.isStale ? "--" : RideUnits.distance(context.state.distance))
            } minimal: {
                Image(systemName: context.isStale ? "location.slash" : "scooter")
            }
        }
        .supplementalActivityFamilies([.small])
    }

}

private struct RideElapsed: View {
    let context: ActivityViewContext<RideActivityAttributes>

    @ViewBuilder var body: some View {
        if let end = context.state.endedAt {
            Text(Duration.seconds(end.timeIntervalSince(context.attributes.startedAt)), format: .time(pattern: .hourMinuteSecond))
        } else {
            Text(timerInterval: context.attributes.startedAt...Date.distantFuture, countsDown: false)
                .monospacedDigit()
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
                    Label("ScooterLog", systemImage: "scooter").font(.caption)
                    RideElapsed(context: context).font(.headline.monospacedDigit())
                    Text(RideUnits.distance(context.state.distance))
                        .font(.title3.monospacedDigit())
                    status.font(.caption2)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("ScooterLog • \(context.attributes.owner)", systemImage: "scooter")
                        Spacer()
                        status
                    }.font(.caption)
                    HStack {
                        RideElapsed(context: context)
                        Spacer()
                        Text(RideUnits.distance(context.state.distance))
                    }.font(.title2.monospacedDigit())
                    Text(context.isStale ? "Open app for current metrics" : "Stopped estimate: \(Int(context.state.stopped)) sec")
                        .font(.caption)
                }
            }
        }
        .padding()
        .activityBackgroundTint(.black)
        .activitySystemActionForegroundColor(.white)
        .foregroundStyle(.white)
    }

    private var status: some View {
        Text(context.state.endedAt != nil ? "Saved" : context.isStale ? "GPS stale" : "Ride active")
            .foregroundStyle(context.isStale ? Color.orange : Color.white)
    }
}
