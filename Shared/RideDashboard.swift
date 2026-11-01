import MapKit
import ScooterCore
import SwiftUI
#if os(iOS)
import UIKit
#endif

enum RideFormat {
    static func duration(_ seconds: TimeInterval) -> String {
        let value = Int(max(0, seconds))
        return String(format: "%d:%02d:%02d", value / 3600, value / 60 % 60, value % 60)
    }

    static func speed(_ value: Double?) -> String {
        RideUnits.speed(value)
    }

    static func distance(_ value: Double) -> String { RideUnits.distance(value) }

    static func spokenDuration(_ seconds: TimeInterval) -> String {
        Duration.seconds(Int(max(0, seconds)))
            .formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide))
    }
}

struct RideDashboard: View {
    @ObservedObject var controller: RideController
    @StateObject private var health = HealthReader.shared
    #if os(iOS)
    @StateObject private var cloud = CloudRideSync()
    #endif
    @State private var confirmEnd = false
    @State private var confirmForget = false
    @State private var confirmLiveHR = false
    @State private var showSettings = false
    @AppStorage(RideTheme.preferenceKey) private var theme: RideTheme = .tronBlue
    @ScaledMetric(relativeTo: .largeTitle) private var scooterSymbolSize = 56
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if dynamicTypeSize.isAccessibilitySize { controls }
                    if controller.displayedRide == nil {
                        VStack(alignment: .leading, spacing: 16) {
                            if !dynamicTypeSize.isAccessibilitySize {
                                Image(systemName: "scooter")
                                    .font(.system(size: scooterSymbolSize, weight: .medium))
                                    .foregroundStyle(theme.color)
                                    .accessibilityHidden(true)
                            }
                            Text("Your next ride starts here.")
                                .font(.title2.bold())
                                .fixedSize(horizontal: false, vertical: true)
                            Text("GPS tracking for your Segway F3. No scooter connection needed.")
                                .font(.subheadline).foregroundStyle(RideTheme.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    if !dynamicTypeSize.isAccessibilitySize { controls }
                    if let ride = controller.displayedRide {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            rideContent(ride, now: context.date)
                        }
                    }
                } footer: {
                    if controller.displayedRide == nil {
                        Text("Start on one device only. Disconnected devices cannot coordinate starts.")
                            .foregroundStyle(RideTheme.secondaryText)
                    } else {
                        Text("Stopped time is an estimate, not traffic-light detection. Missing GPS time is shown as unknown.")
                            .foregroundStyle(RideTheme.secondaryText)
                    }
                }
                if (controller.archive.active != nil && controller.peer?.ride != nil)
                    || (!controller.reachable && controller.peer?.ride != nil) || controller.errorMessage != nil {
                    Section {
                        if controller.archive.active != nil && controller.peer?.ride != nil {
                            notice("Both devices have separate rides. This screen controls the local ride. End the other ride on its recording device; neither route will be discarded.")
                        }
                        if !controller.reachable, controller.peer?.ride != nil {
                            Button("Forget offline companion status") { confirmForget = true }
                        }
                        if let message = controller.errorMessage {
                            notice(message)
                            Button("Dismiss message") { controller.errorMessage = nil }
                            Button("Retry saving") { controller.retrySave() }
                        }
                    } header: {
                        Text("Needs attention").foregroundStyle(RideTheme.secondaryText)
                    }
                }
                Section {
                    NavigationLink { HistoryView(controller: controller) } label: {
                        toolLabel("Ride history", systemImage: "clock.arrow.circlepath")
                    }
                    NavigationLink { DirectionsView(controller: controller) } label: {
                        toolLabel("Directions", systemImage: "arrow.turn.up.right")
                    }
                    NavigationLink { SavedPlacesView(controller: controller) } label: {
                        toolLabel("Saved places", systemImage: "mappin.and.ellipse")
                    }
                } header: {
                    Text("Ride tools").foregroundStyle(RideTheme.secondaryText)
                }
                #if os(iOS)
                if controller.locationAuthorization != .authorizedWhenInUse
                    && controller.locationAuthorization != .authorizedAlways {
                    locationSection
                }
                if health.enabled { healthSection }
                #else
                locationSection
                healthSection
                appearanceSection
                #endif
            }
            .navigationTitle("ScooterLog")
            #if os(iOS)
            .listStyle(.insetGrouped)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Settings", systemImage: "gearshape") { showSettings = true }
                        .accessibilityIdentifier("settings")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu { themePicker } label: {
                        Image(systemName: "paintpalette")
                    }
                    .accessibilityLabel("Color scheme")
                    .accessibilityValue(theme.title)
                    .accessibilityIdentifier("themeMenu")
                }
            }
            .sheet(isPresented: $showSettings) {
                NavigationStack {
                    List {
                        appearanceSection
                        locationSection
                        healthSection
                        CloudSyncView(controller: controller, cloud: cloud)
                    }
                    .navigationTitle("Settings")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showSettings = false }
                        }
                    }
                }
                .tint(theme.color)
            }
            #endif
            .confirmationDialog("End and save this ride?", isPresented: $confirmEnd, titleVisibility: .visible) {
                Button("End ride", role: .destructive) {
                    if controller.isRemote { controller.endRemote() }
                    else { controller.perform { try controller.end() } }
                }
                Button("Cancel", role: .cancel) {}
            }
            .onChange(of: theme) { controller.refreshLiveActivityAppearance() }
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
        .tint(theme.color)
    }

    private var themePicker: some View {
        Picker("Color scheme", selection: $theme) {
            ForEach(RideTheme.allCases) { choice in
                Text(choice.title).tag(choice)
            }
        }
    }

    private var appearanceSection: some View {
        Section {
            themePicker
        } header: {
            Text("Appearance").foregroundStyle(RideTheme.secondaryText)
        }
    }

    private func toolLabel(_ title: LocalizedStringKey, systemImage: String) -> some View {
        Label {
            Text(title).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: systemImage)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(title))
    }

    private func notice(_ message: String, systemImage: String = "exclamationmark.triangle") -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage).accessibilityHidden(true)
            Text(message).fixedSize(horizontal: false, vertical: true)
        }
        .font(.footnote)
        .accessibilityElement(children: .combine)
    }

    private var locationSection: some View {
        Section {
            Text(controller.locationStatus).font(.footnote).foregroundStyle(RideTheme.secondaryText)
            if controller.locationAuthorization == .notDetermined {
                Button("Allow location") { controller.requestLocationPermission() }
            }
            #if os(iOS)
            if controller.locationAuthorization == .denied {
                Button("Open location settings") { openLocationSettings() }
            }
            #endif
        } header: {
            Text("Location").foregroundStyle(RideTheme.secondaryText)
        }
    }

    #if os(iOS)
    private func openLocationSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else {
            controller.report("Location settings could not be opened. Open Settings manually.")
            return
        }
        openURL(url) { opened in
            if !opened { controller.report("Location settings could not be opened. Open Settings manually.") }
        }
    }
    #endif

    private func rideContent(_ ride: Ride, now: Date) -> some View {
        let timingDate = controller.isRemote ? min(now, controller.peer?.sentAt ?? now) : now
        let stopped = ride.stoppedTime(at: timingDate)
        let unknown = max(0, ride.elapsed(at: now) - ride.movingDuration - stopped)
        return VStack(alignment: .leading, spacing: 12) {
            Text(dynamicTypeSize.isAccessibilitySize
                 ? RideFormat.spokenDuration(ride.elapsed(at: now))
                 : RideFormat.duration(ride.elapsed(at: now)))
                .font(.system(.largeTitle, design: .rounded, weight: .bold)).monospacedDigit()
                .foregroundStyle(theme.color)
                .accessibilityLabel("Elapsed time")
                .accessibilityValue(RideFormat.spokenDuration(ride.elapsed(at: now)))
                .accessibilityIdentifier("elapsedTime")
            RideMetric("Current speed", value: RideFormat.speed(ride.currentSpeed(at: now)))
            RideMetric("Distance", value: RideFormat.distance(ride.distance))
            Divider()
            RideMetric("Moving", seconds: ride.movingDuration)
            RideMetric("Stopped estimate", seconds: stopped)
            RideMetric("Unknown", seconds: unknown)
            RideMetric("Overall average", value: RideFormat.speed(ride.averageSpeed(at: now)))
            RideMetric("Moving average", value: RideFormat.speed(ride.movingAverageSpeed))
            Text("Recording owner: \(ride.owner)").font(.caption).foregroundStyle(RideTheme.secondaryText)
            if controller.isRemote, let peer = controller.peer {
                Text("\(peer.recording ? "Owner reports recording" : "Owner reports recording paused") • Updated \(peer.sentAt, style: .relative) ago")
                    .font(.caption).foregroundStyle(RideTheme.secondaryText)
                Text(controller.reachable ? "Companion reachable" : "Companion offline; metrics may be stale")
                    .font(.caption).foregroundStyle(RideTheme.secondaryText)
            } else if !controller.recording {
                notice("Recovered ride: recording is paused. Resume in the foreground or end it. The gap stays unknown.",
                       systemImage: "pause.circle")
            } else if ride.currentSpeed(at: now) == nil {
                notice("Waiting for a fresh GPS fix.", systemImage: "location.magnifyingglass")
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private var controls: some View {
        if controller.displayedRide == nil {
            Button { controller.perform { try controller.start() } } label: {
                actionLabel("Start ride here", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .foregroundStyle(Color("OnRideAccent"))
        } else {
            if !controller.isRemote && !controller.recording {
                Button { controller.perform { try controller.start() } } label: {
                    actionLabel("Resume recording", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .foregroundStyle(Color("OnRideAccent"))
            }
            Button(role: .destructive) { confirmEnd = true } label: {
                actionLabel(controller.commandPending ? "Waiting for owner..." : "End ride", systemImage: "stop.fill")
            }
                .buttonStyle(.bordered)
                .disabled(controller.commandPending || (controller.isRemote && !controller.reachable))
        }
    }

    private func actionLabel(_ title: LocalizedStringKey, systemImage: String) -> some View {
        Label {
            Text(title).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: systemImage)
        }
        .frame(maxWidth: .infinity, minHeight: 44)
    }

    private var healthSection: some View {
        Section {
            if let bpm = health.beatsPerMinute, let date = health.measuredAt {
                Text("\(Int(bpm)) BPM • Sample \(date, style: .time)")
                Text("Sample age: \(date, style: .relative)").font(.caption)
            }
            Text(health.status).font(.footnote).foregroundStyle(RideTheme.secondaryText)
            if health.enabled {
                Button("Refresh sample") { health.refresh() }
                Button("Turn off display") { health.disable() }
            } else {
                Button("Enable optional heart-rate reads") { Task { await health.enable() } }
            }
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
        } header: {
            Text("Heart rate").foregroundStyle(RideTheme.secondaryText)
        } footer: {
            Text("Passive reads do not start a workout. Samples can be old or absent; no diagnostic or emergency monitoring.")
                .foregroundStyle(RideTheme.secondaryText)
        }
    }
}

struct RideMetric: View {
    let title: LocalizedStringKey
    let value: String
    private let spokenValue: String

    init(_ title: LocalizedStringKey, value: String) {
        self.title = title
        self.value = value
        spokenValue = value
    }

    init(_ title: LocalizedStringKey, seconds: TimeInterval) {
        self.title = title
        value = RideFormat.duration(seconds)
        spokenValue = RideFormat.spokenDuration(seconds)
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(title).foregroundStyle(RideTheme.secondaryText).fixedSize()
                Spacer(minLength: 12)
                Text(value).monospacedDigit().fixedSize()
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title).foregroundStyle(RideTheme.secondaryText)
                Text(value).monospacedDigit()
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue(spokenValue)
    }
}

struct HistoryView: View {
    @ObservedObject var controller: RideController

    var body: some View {
        List {
            if controller.archive.completed.isEmpty {
                ContentUnavailableView {
                    Label("No saved rides", systemImage: "clock.arrow.circlepath")
                } description: {
                    Text("Completed rides will appear here, including companion rides after sync.")
                }
            }
            ForEach(controller.archive.completed) { ride in
                NavigationLink {
                    RideDetail(ride: ride)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(ride.startedAt, format: .dateTime.month().day().hour().minute())
                        Text("\(RideFormat.distance(ride.distance)) • \(RideFormat.duration(ride.elapsed(at: .now)))")
                            .font(.subheadline).foregroundStyle(RideTheme.secondaryText)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            Section {
                Button("Resend saved rides to companion") { controller.resendHistory() }
                    .disabled(controller.archive.completed.isEmpty)
            }
        }
        .navigationTitle("History")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

struct RideDetail: View {
    let ride: Ride

    var body: some View {
        List {
            Section {
                if segments.isEmpty {
                    ContentUnavailableView("No recorded route", systemImage: "map",
                                           description: Text("This ride has no continuous GPS segment to display."))
                } else {
                    Map {
                        // Do not connect over unknown GPS gaps.
                        ForEach(Array(segments.enumerated()), id: \.offset) { _, samples in
                            MapPolyline(coordinates: samples.map {
                                CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
                            }).stroke(.tint, lineWidth: 4)
                        }
                    }
                    .frame(height: 220)
                    .accessibilityLabel("Recorded route")
                    .accessibilityHint("Route segments are separated where GPS data is missing.")
                }
            }
            Section {
                Text(ride.startedAt, format: .dateTime).font(.headline)
                RideMetric("Recording owner", value: ride.owner)
                RideMetric("Distance", value: RideFormat.distance(ride.distance))
                RideMetric("Elapsed", seconds: ride.elapsed(at: .now))
                RideMetric("Moving", seconds: ride.movingDuration)
                RideMetric("Stopped estimate", seconds: ride.stoppedDuration)
                RideMetric("Unknown", seconds: ride.unknownDuration(at: .now))
                RideMetric("Overall average", value: RideFormat.speed(ride.averageSpeed(at: .now)))
                RideMetric("Moving average", value: RideFormat.speed(ride.movingAverageSpeed))
            } header: {
                Text("Ride summary").foregroundStyle(RideTheme.secondaryText)
            }
        }
        .navigationTitle("Ride")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
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
