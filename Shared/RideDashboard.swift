import MapKit
import ScooterCore
import SwiftUI

enum RideFormat {
    static func duration(_ seconds: TimeInterval) -> String {
        let value = Int(max(0, seconds))
        return String(format: "%d:%02d:%02d", value / 3600, value / 60 % 60, value % 60)
    }

    static func speed(_ value: Double?) -> String {
        RideUnits.speed(value)
    }

    static func distance(_ value: Double) -> String { RideUnits.distance(value) }
}

struct RideDashboard: View {
    @ObservedObject var controller: RideController
    @StateObject private var health = HealthReader.shared
    @State private var confirmEnd = false
    @State private var confirmForget = false
    @State private var confirmLiveHR = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Label("ScooterLog", systemImage: "scooter").font(.title2.bold())
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        if let ride = controller.displayedRide {
                            rideContent(ride, now: context.date)
                        } else {
                            Text("Your next ride starts here.").foregroundStyle(.secondary)
                            Text("GPS tracking for your Segway F3. No scooter connection needed.")
                                .font(.footnote)
                        }
                    }
                    controls
                    if controller.archive.active != nil && controller.peer?.ride != nil {
                        Text("Both devices have separate rides. This screen controls the local ride. End the other ride on its recording device; neither route will be discarded.")
                            .font(.footnote).foregroundStyle(.orange)
                    }
                    if !controller.reachable, controller.peer?.ride != nil {
                        Button("Forget offline companion status") { confirmForget = true }
                    }
                    if let message = controller.errorMessage {
                        VStack {
                            Text(message).font(.footnote).foregroundStyle(.red)
                            Button("Dismiss message") { controller.errorMessage = nil }
                            Button("Retry saving") { controller.retrySave() }
                        }
                    }
                    NavigationLink("Ride history") { HistoryView(controller: controller) }
                    NavigationLink("Directions") { DirectionsView(controller: controller) }
                    NavigationLink("Saved places") { SavedPlacesView(controller: controller) }
                    healthSection
                    #if os(iOS)
                    CloudSyncView(controller: controller)
                    #endif
                    Text(controller.locationStatus).font(.caption).foregroundStyle(.secondary)
                    Button("Allow location") { controller.requestLocationPermission() }
                    Text("Stopped time is an estimate, not traffic-light detection. Missing GPS time is shown as unknown.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding()
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
            .background(.background)
            .confirmationDialog("End and save this ride?", isPresented: $confirmEnd, titleVisibility: .visible) {
                Button("End ride", role: .destructive) {
                    if controller.isRemote { controller.endRemote() }
                    else { controller.perform { try controller.end() } }
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    health.refresh()
                    controller.refreshConnection()
                }
            }
            .alert("Forget offline status?", isPresented: $confirmForget) {
                Button("Forget status", role: .destructive) { controller.forgetStalePeer() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This does not stop the other device. Starting here may create a second ride. Check the recording device when possible.")
            }
            #if os(watchOS)
            .alert("Start live heart rate?", isPresented: $confirmLiveHR) {
                Button("Start Other session") { Task { await health.startLiveSession() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Uses an Other workout session for sensors, not a scooter exercise classification. ScooterLog discards the builder without saving a workout. watchOS may still create Health samples or ring effects. Sampling frequency is not guaranteed.")
            }
            .onChange(of: controller.archive.active?.id) { _, id in
                if id == nil { health.stopLiveSession() }
            }
            #endif
        }
    }

    private func rideContent(_ ride: Ride, now: Date) -> some View {
        let timingDate = controller.isRemote ? min(now, controller.peer?.sentAt ?? now) : now
        let stopped = ride.stoppedTime(at: timingDate)
        let unknown = max(0, ride.elapsed(at: now) - ride.movingDuration - stopped)
        return VStack(spacing: 12) {
            Text(RideFormat.duration(ride.elapsed(at: now)))
                .font(.system(.largeTitle, design: .rounded, weight: .bold)).monospacedDigit()
                .accessibilityLabel("Elapsed \(RideFormat.duration(ride.elapsed(at: now)))")
            Text(RideFormat.speed(ride.currentSpeed(at: now))).font(.title2.monospacedDigit())
            Text(RideFormat.distance(ride.distance)).font(.title3.monospacedDigit())
            HStack {
                VStack {
                    Text("Moving").font(.caption)
                    Text(RideFormat.duration(ride.movingDuration)).font(.headline.monospacedDigit())
                }
                Spacer()
                VStack {
                    Text("Stopped estimate").font(.caption)
                    Text(RideFormat.duration(stopped)).font(.headline.monospacedDigit())
                }
            }
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                metric("Unknown", RideFormat.duration(unknown))
                metric("Overall average", RideFormat.speed(ride.averageSpeed(at: now)))
                metric("Moving average", RideFormat.speed(ride.movingAverageSpeed))
            }.font(.caption)
            Text("Recording owner: \(ride.owner)").font(.caption)
            if controller.isRemote, let peer = controller.peer {
                Text("\(peer.recording ? "Owner reports recording" : "Owner reports recording paused") • Updated \(peer.sentAt, style: .relative) ago")
                    .font(.caption).foregroundStyle(.secondary)
                Text(controller.reachable ? "Companion reachable" : "Companion offline; metrics may be stale")
                    .font(.caption).foregroundStyle(controller.reachable ? Color.secondary : Color.orange)
            } else if !controller.recording {
                Text("Recovered ride: recording is paused. Resume in the foreground or end it. The gap stays unknown.")
                    .font(.footnote).foregroundStyle(.orange)
            } else if ride.currentSpeed(at: now) == nil {
                Text("Waiting for a fresh GPS fix.").font(.caption).foregroundStyle(.orange)
            }
        }
    }

    private func metric(_ label: String, _ value: String) -> some View {
        GridRow { Text(label); Text(value).monospacedDigit() }
    }

    @ViewBuilder private var controls: some View {
        if controller.displayedRide == nil {
            Button { controller.perform { try controller.start() } } label: {
                Label("Start ride here", systemImage: "play.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).tint(.green)
            Text("Start on one device only. Disconnected devices cannot coordinate starts.")
                .font(.caption).foregroundStyle(.secondary)
        } else {
            if !controller.isRemote && !controller.recording {
                Button("Resume recording") { controller.perform { try controller.start() } }
                    .buttonStyle(.borderedProminent)
            }
            Button(controller.commandPending ? "Waiting for owner..." : "End ride") { confirmEnd = true }
                .buttonStyle(.bordered).tint(.red)
                .disabled(controller.commandPending || (controller.isRemote && !controller.reachable))
        }
    }

    private var healthSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Heart rate").font(.headline)
            if let bpm = health.beatsPerMinute, let date = health.measuredAt {
                Text("\(Int(bpm)) BPM • Sample \(date, style: .time)")
                Text("Sample age: \(date, style: .relative)").font(.caption)
            }
            Text(health.status).font(.caption)
            if health.enabled {
                Button("Refresh sample") { health.refresh() }
                Button("Turn off display") { health.disable() }
            } else {
                Button("Enable optional heart-rate reads") { Task { await health.enable() } }
            }
            Text("Passive reads do not start a workout. Samples can be old or absent; no diagnostic or emergency monitoring.")
                .font(.caption).foregroundStyle(.secondary)
            #if os(watchOS)
            if health.liveActive {
                Button("Stop live HR and discard") { health.stopLiveSession() }
            } else {
                Button(health.liveStarting ? "Requesting live HR..." : "Live HR (Other session)") { confirmLiveHR = true }
                    .disabled(health.liveStarting || !controller.recording || controller.isRemote)
                Text("Optional, only while recording here. Explicit consent required each session.")
                    .font(.caption)
            }
            #endif
        }
    }
}

struct HistoryView: View {
    @ObservedObject var controller: RideController

    var body: some View {
        List {
            Button("Resend saved rides to companion") { controller.resendHistory() }
            if controller.archive.completed.isEmpty {
                Text("Completed rides will appear here, including companion rides after sync.")
            }
            ForEach(controller.archive.completed) { ride in
                NavigationLink {
                    RideDetail(ride: ride)
                } label: {
                    VStack(alignment: .leading) {
                        Text(ride.startedAt, format: .dateTime.month().day().hour().minute())
                        Text("\(RideFormat.distance(ride.distance)) • \(RideFormat.duration(ride.elapsed(at: .now)))")
                            .font(.caption)
                    }
                }
            }
        }
        .navigationTitle("History")
    }
}

struct RideDetail: View {
    let ride: Ride

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Map {
                    if ride.samples.count > 1 {
                        // Do not connect over unknown GPS gaps.
                        ForEach(Array(segments.enumerated()), id: \.offset) { _, samples in
                            MapPolyline(coordinates: samples.map {
                                CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
                            }).stroke(.blue, lineWidth: 4)
                        }
                    }
                }
                .frame(height: 220)
                Text(ride.startedAt, format: .dateTime).font(.headline)
                Text("\(ride.owner) • \(RideFormat.distance(ride.distance))")
                Text("Elapsed: \(RideFormat.duration(ride.elapsed(at: .now)))")
                Text("Moving: \(RideFormat.duration(ride.movingDuration))")
                Text("Stopped estimate: \(RideFormat.duration(ride.stoppedDuration))")
                Text("Unknown: \(RideFormat.duration(ride.unknownDuration(at: .now)))")
                Text("Overall: \(RideFormat.speed(ride.averageSpeed(at: .now)))")
                Text("Moving average: \(RideFormat.speed(ride.movingAverageSpeed))")
            }.padding()
        }
        .navigationTitle("Ride")
    }

    private var segments: [[LocationSample]] {
        var result: [[LocationSample]] = []
        for sample in ride.samples {
            if let last = result.last?.last, sample.timestamp.timeIntervalSince(last.timestamp) <= 15 {
                result[result.count - 1].append(sample)
            } else { result.append([sample]) }
        }
        return result.filter { $0.count > 1 }
    }
}
