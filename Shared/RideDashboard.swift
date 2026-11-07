import MapKit
import ScooterCore
import SwiftUI
#if os(iOS)
import UIKit
#elseif os(watchOS)
import WidgetKit
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
    @ObservedObject private var directions: DirectionsModel
    @AppStorage("directionsVoiceGuidance") private var voiceGuidance = true
    @StateObject private var health = HealthReader.shared
    @StateObject private var weather = RideWeatherModel()
    @StateObject private var widgets = RideWidgetPublisher()
    @AppStorage(RideWidgetSnapshot.goalKey, store: RideWidgetStore.defaults)
    private var weeklyGoal = RideWidgetSnapshot.defaultGoalMiles
    #if os(iOS)
    @StateObject private var cloud = CloudRideSync()
    #endif
    @State private var confirmEnd = false
    @State private var confirmForget = false
    @State private var confirmLiveHR = false
    @State private var showSettings = false
    @State private var informationError: String?
    @State private var navigationID = UUID()
    @State private var showActiveRideNotice = false
    #if os(iOS)
    @ObservedObject private var homeScreen = HomeScreenActions.shared
    @State private var tab: DashboardTab = .ride
    @State private var rideBarVisibility = RideBarVisibility()
    #endif
    @AppStorage(RideTheme.preferenceKey) private var theme: RideTheme = .tronBlue
    @AppStorage(RideUnitSystem.preferenceKey, store: RideWidgetStore.defaults)
    private var units: RideUnitSystem = .imperial
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.openURL) private var openURL

    init(controller: RideController) {
        self.controller = controller
        directions = controller.directions
    }

    var body: some View {
        #if os(iOS)
        TabView(selection: $tab) {
            Tab("Ride", systemImage: "scooter", value: .ride) { dashboard }
            Tab("History", systemImage: "clock.arrow.circlepath", value: .history) {
                NavigationStack { HistoryView(controller: controller) }
            }
            Tab("Directions", systemImage: "arrow.turn.up.right", value: .directions) {
                NavigationStack { directionsView }
            }
            Tab("Saved places", systemImage: "mappin.and.ellipse", value: .places) {
                NavigationStack { SavedPlacesView(controller: controller) }
            }
        }
        .tabViewBottomAccessory(isEnabled: rideBarVisibility.isVisible) { rideAccessory }
        .environment(\.rideBarVisibility, rideBarVisibility)
        .tint(theme.color)
        .modifier(endRideConfirmation)
        #else
        dashboard.modifier(endRideConfirmation)
        #endif
    }

    private var endRideConfirmation: EndRideConfirmation {
        EndRideConfirmation(isPresented: $confirmEnd) {
            if controller.isRemote { controller.endRemote() }
            else { controller.perform { try controller.end() } }
        }
    }

    @ViewBuilder private var directionsView: some View {
        if controller.isRemote {
            CompanionDirectionsView(controller: controller)
        } else {
            DirectionsView(controller: controller)
        }
    }

    private var dashboard: some View {
        NavigationStack {
            List {
                guidanceSection
                if controller.displayedRide == nil { weatherSection }
                rideSection
                if controller.displayedRide != nil { weatherSection }
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
                #if os(iOS)
                if controller.locationAuthorization != .authorizedWhenInUse
                    && controller.locationAuthorization != .authorizedAlways {
                    locationSection
                }
                if health.enabled { healthSection }
                #else
                toolsSection
                locationSection
                healthSection
                appearanceSection
                unitsSection
                scootersSection
                widgetsSection
                privacyAndSupportSection
                #endif
            }
            .rideSurface()
            .navigationTitle("ScooterLog")
            #if os(watchOS)
            .toolbar { rideActionToolbar }
            #endif
            #if os(iOS)
            .listStyle(.plain)
            .listRowInsets(EdgeInsets(top: 12, leading: 20, bottom: 12, trailing: 20))
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
                        unitsSection
                        scootersSection
                        widgetsSection
                        locationSection
                        healthSection
                        CloudSyncView(controller: controller, cloud: cloud)
                        privacyAndSupportSection
                    }
                    .rideSurface()
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
            .onAppear { handleHomeScreenStart() }
            .onChange(of: homeScreen.startRequested, initial: false) { _, _ in handleHomeScreenStart() }
            .alert("A ride is already active", isPresented: $showActiveRideNotice) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Continue it here or end it on its recording device before starting a new ride.")
            }
            #endif
            .onChange(of: theme, initial: false) { _, _ in
                controller.refreshLiveActivityAppearance()
                publishWidgets()
            }
            .onChange(of: weeklyGoal, initial: false) { _, _ in publishWidgets() }
            .onChange(of: weather.widgetWeather, initial: false) { _, _ in publishWidgets() }
            .onChange(of: units, initial: false) { _, _ in
                controller.refreshLiveActivityAppearance()
                widgets.invalidate()
                publishWidgets()
            }
            .onReceive(controller.$archive) { publishWidgets($0) }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    health.refresh()
                    if controller.locationAuthorization == .authorizedWhenInUse
                        || controller.locationAuthorization == .authorizedAlways {
                        weather.refresh()
                    }
                    publishWidgets()
                    controller.refreshConnection()
                    #if os(iOS)
                    handleHomeScreenStart()
                    #endif
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
        .id(navigationID)
        .tint(theme.color)
        #if os(watchOS)
        .onContinueUserActivity(NSUserActivityTypeLiveActivity) { _ in
            navigationID = UUID()
            controller.refreshConnection()
        }
        #endif
    }

    @ViewBuilder private var guidanceSection: some View {
        if let guidance = controller.displayedGuidance {
            Section {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    RideGuidanceSummary(guidance: guidance, now: context.date,
                                        recording: controller.isRemote ? controller.peer?.recording == true : controller.recording)
                }
                NavigationLink("Live directions") {
                    if controller.isRemote {
                        CompanionDirectionsView(controller: controller)
                    } else {
                        TurnByTurnView(model: directions, controller: controller, voiceGuidance: $voiceGuidance)
                    }
                }
            }
            .ridePanelRow()
            .id("live-guidance")
        }
    }

    private var weatherSection: some View {
        RideWeatherSection(model: weather, locationAuthorization: controller.locationAuthorization)
    }

    private var rideSection: some View {
        Section {
            if dynamicTypeSize.isAccessibilitySize { controls }
            if controller.displayedRide == nil {
                rideIntroduction
                    .listRowInsets(EdgeInsets())
                    #if os(iOS)
                    .listRowSeparator(.hidden)
                    #endif
            }
            if !dynamicTypeSize.isAccessibilitySize { controls }
            #if os(watchOS)
            if controller.displayedRide == nil { rideIntroductionCopy }
            #endif
            if let ride = controller.displayedRide {
                TimelineView(.periodic(from: .now, by: 1)) { context in rideContent(ride, now: context.date) }
            }
        } footer: {
            Text(controller.displayedRide == nil
                 ? "Start on one device only. Disconnected devices cannot coordinate starts."
                 : "Stopped time is an estimate, not traffic-light detection. Missing GPS time is shown as unknown.")
                .foregroundStyle(RideTheme.secondaryText)
        }
        .id("ride-metrics")
    }

    private var toolsSection: some View {
        Section {
            NavigationLink { HistoryView(controller: controller) } label: {
                toolLabel("Ride history", systemImage: "clock.arrow.circlepath")
            }
            NavigationLink { directionsView } label: {
                toolLabel("Directions", systemImage: "arrow.turn.up.right")
            }
            NavigationLink { SavedPlacesView(controller: controller) } label: {
                toolLabel("Saved places", systemImage: "mappin.and.ellipse")
            }
        } header: {
            Text("Ride tools").foregroundStyle(RideTheme.secondaryText)
        }
        .ridePanelRow()
        .id("ride-tools")
    }

    #if os(iOS)
    private func handleHomeScreenStart() {
        guard UIApplication.shared.applicationState == .active, homeScreen.startRequested else { return }
        showSettings = false
        navigationID = UUID()
        tab = .ride
        homeScreen.startRequested = false
        guard controller.displayedRide == nil else {
            showActiveRideNotice = true
            return
        }
        controller.perform { try controller.start() }
    }
    #endif

    private var rideIntroduction: some View {
        Group {
            #if os(iOS)
            if verticalSizeClass == .compact && !dynamicTypeSize.isAccessibilitySize {
                HStack(spacing: 20) {
                    ScooterArtwork(theme: theme).frame(width: 240, height: 180)
                    rideIntroductionCopy
                }
                .padding(.horizontal, 20)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    if !dynamicTypeSize.isAccessibilitySize {
                        ScooterArtwork(theme: theme).frame(height: 260)
                    }
                    rideIntroductionCopy
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)
                        .padding(.top, dynamicTypeSize.isAccessibilitySize ? 20 : 0)
                }
            }
            #else
            if !dynamicTypeSize.isAccessibilitySize {
                ScooterArtwork(theme: theme).frame(height: 120)
            }
            #endif
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RideTheme.artworkBackground)
    }

    private var rideIntroductionCopy: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your next ride starts here.")
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(.white)
                .accessibilityAddTraits(.isHeader)
        }
        .fixedSize(horizontal: false, vertical: true)
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

    private var unitsSection: some View {
        Section {
            Picker("Distance and speed", selection: $units) {
                Text("Miles and mph").tag(RideUnitSystem.imperial)
                Text("Kilometers and km/h").tag(RideUnitSystem.metric)
            }
            .accessibilityIdentifier("rideUnits")
        } header: {
            Text("Units").foregroundStyle(RideTheme.secondaryText)
        } footer: {
            Text("This device's app, widgets and Live Activity use these units.")
                .foregroundStyle(RideTheme.secondaryText)
        }
    }

    private var scootersSection: some View {
        Section {
            NavigationLink {
                ScooterProfilesView(store: .shared)
            } label: {
                Label("Scooter profiles", systemImage: "scooter")
            }
        }
    }

    private var widgetsSection: some View {
        Section {
            Stepper(value: Binding(
                get: { weeklyGoal * RideUnits.metersPerMile / units.metersPerUnit },
                set: { weeklyGoal = $0 * units.metersPerUnit / RideUnits.metersPerMile }
            ), in: (RideWidgetSnapshot.goalRange.lowerBound * RideUnits.metersPerMile / units.metersPerUnit)...(RideWidgetSnapshot.goalRange.upperBound * RideUnits.metersPerMile / units.metersPerUnit), step: 5) {
                #if os(watchOS)
                Text(RideUnits.distance(weeklyGoal * RideUnits.metersPerMile, units: units))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                #else
                LabeledContent("Weekly goal", value: RideUnits.distance(weeklyGoal * RideUnits.metersPerMile, units: units))
                #endif
            }
            .accessibilityIdentifier("weeklyGoal")
        } header: {
            #if os(watchOS)
            Text("Weekly goal").foregroundStyle(RideTheme.secondaryText)
            #else
            Text("Widgets").foregroundStyle(RideTheme.secondaryText)
            #endif
        } footer: {
            #if os(watchOS)
            Text("Sets the target for your weekly mileage widget.").foregroundStyle(RideTheme.secondaryText)
            #else
            Text("Used by the weekly goal widget on this device.").foregroundStyle(RideTheme.secondaryText)
            #endif
        }
    }

    private func publishWidgets(_ archive: RideArchive? = nil) {
        let archive = archive ?? controller.archive
        widgets.publish(rides: archive.completed, rideActive: controller.displayedRide != nil || archive.active != nil,
                        goalMiles: weeklyGoal, weather: weather.widgetWeather, theme: theme.rawValue)
    }

    private func toolLabel(_ title: LocalizedStringKey, systemImage: String) -> some View {
        Label {
            Text(title).fixedSize(horizontal: false, vertical: true)
        } icon: {
            RideToolIcon(systemImage: systemImage)
        }
        .font(.headline)
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

    private var privacyAndSupportSection: some View {
        Section {
            Button("Privacy policy", systemImage: "hand.raised") {
                openInformationURL("https://scooterlog.j4m13.dev/privacy/")
            }
            .accessibilityIdentifier("privacyPolicy")
            Button("Support", systemImage: "questionmark.circle") {
                openInformationURL("https://scooterlog.j4m13.dev/support/")
            }
            .accessibilityIdentifier("supportWebsite")
            Button("Email support", systemImage: "envelope") {
                openInformationURL("mailto:privacy@j4m13.dev")
            }
            .accessibilityIdentifier("supportEmail")
            Text("privacy@j4m13.dev")
                .font(.footnote)
                .foregroundStyle(RideTheme.secondaryText)
            #if os(watchOS)
            Text("If a link does not open, visit scooterlog.j4m13.dev on your iPhone.")
                .font(.footnote)
                .foregroundStyle(RideTheme.secondaryText)
            #endif
            if let informationError {
                notice(informationError)
                    .accessibilityIdentifier("informationError")
            }
        } header: {
            Text("Privacy & support").foregroundStyle(RideTheme.secondaryText)
        }
    }

    private func openInformationURL(_ address: String) {
        informationError = nil
        guard let url = URL(string: address) else {
            informationError = "This address is unavailable. Contact privacy@j4m13.dev."
            return
        }
        #if os(watchOS)
        openURL(url)
        #else
        openURL(url) { opened in
            if !opened {
                informationError = "Could not open \(address). Open it on your iPhone or contact privacy@j4m13.dev."
            }
        }
        #endif
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
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 24) {
                    instrument("Current speed", value: RideFormat.speed(ride.currentSpeed(at: now)))
                    Spacer(minLength: 0)
                    instrument("Distance", value: RideFormat.distance(ride.distance))
                }
                VStack(alignment: .leading, spacing: 16) {
                    instrument("Current speed", value: RideFormat.speed(ride.currentSpeed(at: now)))
                    instrument("Distance", value: RideFormat.distance(ride.distance))
                }
            }
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
                if controller.reachable {
                    Text("Companion reachable")
                        .font(.caption).foregroundStyle(RideTheme.secondaryText)
                } else {
                    Text("Recording device offline; metrics may be stale. Reconnect, or end the ride on that device.")
                        .font(.caption).foregroundStyle(RideTheme.secondaryText)
                }
            } else if !controller.recording {
                notice("Recovered ride: recording is paused. Resume in the foreground or end it. The gap stays unknown.",
                       systemImage: "pause.circle")
            } else if ride.currentSpeed(at: now) == nil {
                notice(controller.locationStatus, systemImage: "location.magnifyingglass")
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func instrument(_ title: LocalizedStringKey, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.system(.title2, design: .rounded, weight: .bold))
                .monospacedDigit()
                .fixedSize()
            Text(title)
                .font(.caption)
                .foregroundStyle(RideTheme.secondaryText)
                .fixedSize()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue(value)
    }

    /// Start and End live in the bottom toolbar; only an interrupted ride's Resume stays inline.
    @ViewBuilder private var controls: some View {
        if controller.displayedRide != nil, !controller.isRemote, !controller.recording {
            Button { controller.perform { try controller.start() } } label: {
                actionLabel("Resume recording", systemImage: "play.fill")
            }
            .buttonStyle(RidePrimaryButtonStyle())
            .foregroundStyle(Color("OnRideAccent"))
            #if os(watchOS)
            .listRowBackground(Color.clear)
            #endif
        }
    }

    #if os(iOS)
    /// Lives above the tab bar on every tab, like a Now Playing bar: Start, or live stats with End.
    private var rideAccessory: some View {
        // System bars cap text size; the Large Content Viewer covers larger accessibility sizes.
        rideAccessoryContent
            .controlSize(.large)
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .accessibilityShowsLargeContentViewer()
    }

    private var recordingStatus: RideRecordingStatus {
        RideRecordingStatus(isRemote: controller.isRemote,
                            isRecording: controller.isRemote ? controller.peer?.recording == true : controller.recording,
                            isReachable: controller.reachable)
    }

    @ViewBuilder private var rideAccessoryContent: some View {
        if let ride = controller.displayedRide {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 12) {
                    Button { tab = .ride } label: {
                        RideAccessoryStatus(status: recordingStatus, startedAt: ride.startedAt,
                                            distance: ride.distance, color: theme.color)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Shows ride status and recording-device details.")
                    .accessibilityIdentifier("rideAccessoryDetails")
                    Spacer(minLength: 0)
                    rideActionButton
                }
                if controller.isRemote && !controller.reachable {
                    Button { tab = .ride } label: {
                        Text("Device offline. Reconnect, or end the ride on that device.")
                            .font(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Reconnect, or end the ride on the recording device.")
                    .accessibilityIdentifier("offlineRideDetails")
                }
            }
            .padding(.leading, 16)
            .padding(.trailing, 6)
        } else {
            rideActionButton.padding(.horizontal, 6)
        }
    }
    #else
    @ToolbarContentBuilder private var rideActionToolbar: some ToolbarContent {
        ToolbarItem(placement: .bottomBar) { rideActionButton }
    }
    #endif

    private var wideAction: CGFloat? {
        #if os(iOS)
        .infinity
        #else
        nil
        #endif
    }

    /// The primary ride action, drawn on system Liquid Glass: the theme accent to start, red to end.
    @ViewBuilder private var rideActionButton: some View {
        if controller.displayedRide == nil {
            Button {
                #if os(iOS)
                tab = .ride
                #endif
                controller.perform { try controller.start() }
            } label: {
                Label("Start ride here", systemImage: "play.fill").frame(maxWidth: wideAction)
            }
            .buttonStyle(.glassProminent)
            .tint(theme.color)
            .foregroundStyle(Color("OnRideAccent"))
            .labelStyle(.titleAndIcon)
        } else {
            Button(role: .destructive) { confirmEnd = true } label: {
                Label(controller.commandPending ? "Waiting for owner..." : "End ride", systemImage: "stop.fill")
            }
            .buttonStyle(.glassProminent)
            .tint(.red)
            .foregroundStyle(.white)
            .labelStyle(.titleAndIcon)
            .disabled(controller.commandPending || (controller.isRemote && !controller.reachable))
            .accessibilityHint(controller.isRemote && !controller.reachable
                               ? Text("Reconnect, or end the ride on the recording device.")
                               : Text("Asks for confirmation before saving the ride."))
        }
    }

    private func actionLabel(
        _ title: LocalizedStringKey,
        systemImage: String,
        fillsWidth: Bool = true
    ) -> some View {
        Label {
            Text(title).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: systemImage)
        }
        .frame(maxWidth: fillsWidth ? .infinity : nil, minHeight: 44)
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

enum RideDeletion {
    static func title(_ count: Int) -> String { count == 1 ? "Delete this ride?" : "Delete \(count) rides?" }
    static func action(_ count: Int) -> String { count == 1 ? "Delete ride" : "Delete \(count) rides" }

    static var message: String {
        #if os(iOS)
        "This can't be undone. Deleted rides are also removed from your paired Apple Watch and, if iCloud sync is on, from iCloud at your next sync."
        #else
        "This can't be undone. Deleted rides are also removed from your paired iPhone."
        #endif
    }
}

extension View {
    /// Confirms an irreversible ride deletion. Attach it to the control that starts the deletion so the dialog appears next to it.
    func rideDeletionConfirmation(isPresented: Binding<Bool>, count: Int, delete: @escaping () -> Void) -> some View {
        confirmationDialog(RideDeletion.title(count), isPresented: isPresented, titleVisibility: .visible) {
            Button(RideDeletion.action(count), role: .destructive, action: delete)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(RideDeletion.message)
        }
    }
}

struct AttentionSection: View {
    @ObservedObject var controller: RideController

    var body: some View {
        if let message = controller.errorMessage {
            Section {
                Label(message, systemImage: "exclamationmark.triangle")
                    .fixedSize(horizontal: false, vertical: true)
                Button("Dismiss message") { controller.errorMessage = nil }
            } header: {
                Text("Needs attention").foregroundStyle(RideTheme.secondaryText)
            }
        }
    }
}

struct HistoryView: View {
    @ObservedObject var controller: RideController
    @State private var rowDeletion: UUID?
    #if os(iOS)
    @State private var editMode: EditMode = .inactive
    @State private var selection: Set<UUID> = []
    @State private var confirmSelectionDeletion = false
    @State private var exporting = false
    @State private var exportFiles: ActivityExportFiles?
    @State private var exportDirectory: URL?
    #endif

    private var rideIDs: Set<UUID> { Set(controller.archive.completed.map(\.id)) }

    var body: some View {
        list
            .rideSurface()
            .navigationTitle("History")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !controller.archive.completed.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(editMode.isEditing ? "Done" : "Select") { setEditing(!editMode.isEditing) }
                            .accessibilityIdentifier("selectRides")
                    }
                }
                if editMode.isEditing {
                    ToolbarItemGroup(placement: .bottomBar) {
                        Button(allSelected ? "Deselect all" : "Select all") {
                            selection = allSelected ? [] : rideIDs
                        }
                        .accessibilityIdentifier("selectAllRides")
                        Spacer()
                        Button(selectedIDs.isEmpty ? "Delete" : "Delete (\(selectedIDs.count))", role: .destructive) {
                            confirmSelectionDeletion = true
                        }
                        .disabled(selectedIDs.isEmpty)
                        .rideDeletionConfirmation(isPresented: $confirmSelectionDeletion, count: selectedIDs.count) {
                            if delete(selectedIDs) { setEditing(false) }
                        }
                        .accessibilityIdentifier("deleteSelectedRides")
                    }
                }
            }
            .environment(\.editMode, $editMode)
            // Like Photos, selection swaps the tab bar for its Select all / Delete bar.
            .hidesRideBar(editMode.isEditing, reason: "historySelection")
            .onChange(of: rideIDs) { _, ids in
                selection.formIntersection(ids)
                if ids.isEmpty { editMode = .inactive }
            }
            .sheet(item: $exportFiles, onDismiss: removeExport) { files in
                ActivityExportShareSheet(urls: files.urls) { error in
                    if let error { controller.report("Could not share activities: \(error.localizedDescription)") }
                    exportFiles = nil
                }
            }
            #endif
    }

    @ViewBuilder private var list: some View {
        #if os(iOS)
        List(selection: $selection) { rows }
        #else
        List { rows }
        #endif
    }

    @ViewBuilder private var rows: some View {
        AttentionSection(controller: controller)
        if controller.archive.completed.isEmpty {
            ContentUnavailableView {
                Label("No saved rides", systemImage: "clock.arrow.circlepath")
            } description: {
                Text("Completed rides will appear here, including companion rides after sync.")
            }
        }
        ForEach(controller.archive.completed) { ride in
            row(for: ride)
                .ridePanelRow()
                .accessibilityIdentifier("rideRow")
                .accessibilityValue(ride.owner)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    // Not `.destructive`: that role animates the row away and drops a dialog attached to it.
                    Button("Delete", systemImage: "trash") { rowDeletion = ride.id }
                        .tint(.red)
                }
                #if os(iOS)
                .contextMenu {
                    Button("Delete", systemImage: "trash", role: .destructive) { rowDeletion = ride.id }
                }
                #endif
                .rideDeletionConfirmation(isPresented: rowDeletionBinding(for: ride.id), count: 1) {
                    delete([ride.id])
                }
        }
        if !isEditing {
            Section {
                #if os(iOS)
                Button {
                    downloadActivities()
                } label: {
                    Label(exporting ? "Preparing activities..." : "Download all activities",
                          systemImage: "square.and.arrow.down")
                }
                .disabled(exporting || controller.archive.completed.isEmpty)
                .accessibilityIdentifier("downloadAllActivities")
                Text("Save or share JSON and GPX files containing all saved rides on this iPhone. Includes precise routes and times, but no heart-rate data or active ride.")
                    .font(.footnote).foregroundStyle(RideTheme.secondaryText)
                #endif
                Button("Resend saved rides to companion") { controller.resendHistory() }
                    .disabled(controller.archive.completed.isEmpty)
            }
        }
    }

    private var isEditing: Bool {
        #if os(iOS)
        editMode.isEditing
        #else
        false
        #endif
    }

    @ViewBuilder private func row(for ride: Ride) -> some View {
        if isEditing {
            // A link renders dimmed while selecting, which reads as disabled.
            RideRow(ride: ride)
        } else {
            NavigationLink {
                RideDetail(ride: ride, controller: controller)
            } label: {
                RideRow(ride: ride)
            }
        }
    }

    private func rowDeletionBinding(for id: UUID) -> Binding<Bool> {
        Binding(
            get: { rowDeletion == id },
            set: { if !$0 && rowDeletion == id { rowDeletion = nil } }
        )
    }

    /// Returns whether the deletion succeeded. A failure is reported on screen.
    @discardableResult
    private func delete(_ ids: Set<UUID>) -> Bool {
        // The set may be stale if the companion deleted some of these rides while the dialog was open.
        let ids = ids.intersection(rideIDs)
        guard !ids.isEmpty else { return true }
        do {
            try withAnimation { try controller.deleteRides(ids) }
            return true
        } catch {
            controller.report(error.localizedDescription)
            return false
        }
    }

    #if os(iOS)
    private var selectedIDs: Set<UUID> { selection.intersection(rideIDs) }
    private var allSelected: Bool { !rideIDs.isEmpty && selectedIDs.count == rideIDs.count }

    private func setEditing(_ editing: Bool) {
        withAnimation {
            editMode = editing ? .active : .inactive
            if !editing { selection = [] }
        }
    }

    private func downloadActivities() {
        let rides = controller.archive.completed
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScooterLog-export-\(UUID().uuidString)", isDirectory: true)
        exporting = true
        exportDirectory = directory
        Task {
            defer { exporting = false }
            do {
                let urls = try await Task.detached(priority: .userInitiated) {
                    try RideExport.write(rides, to: directory)
                }.value
                exportFiles = ActivityExportFiles(urls: urls)
            } catch {
                controller.report("Could not export activities: \(error.localizedDescription)")
                removeExport()
            }
        }
    }

    private func removeExport() {
        guard let directory = exportDirectory else { return }
        exportDirectory = nil
        do { try FileManager.default.removeItem(at: directory) }
        catch { controller.report("Could not remove temporary export files: \(error.localizedDescription)") }
    }
    #endif
}

#if os(iOS)
private struct ActivityExportFiles: Identifiable {
    let id = UUID()
    let urls: [URL]
}

private struct ActivityExportShareSheet: UIViewControllerRepresentable {
    let urls: [URL]
    let completion: @MainActor (Error?) -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: urls, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, error in
            Task { @MainActor in completion(error) }
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif

private struct RideRow: View {
    let ride: Ride

    var body: some View {
        HStack(spacing: 14) {
            #if os(iOS)
            RideToolIcon(systemImage: "point.topleft.down.to.point.bottomright.curvepath")
            #endif
            VStack(alignment: .leading, spacing: 6) {
                Text(RideFormat.distance(ride.distance))
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .monospacedDigit()
                Text(ride.startedAt, format: .dateTime.month().day().hour().minute())
                    .font(.subheadline).foregroundStyle(RideTheme.secondaryText)
                Text(RideFormat.duration(ride.elapsed(at: .now)))
                    .font(.caption).monospacedDigit().foregroundStyle(RideTheme.secondaryText)
                if ride.isTrimmedEstimate == true {
                    Text("GPS estimate").font(.caption).foregroundStyle(RideTheme.secondaryText)
                }
            }
        }
        .padding(.vertical, 6)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }
}

struct RideDetail: View {
    let ride: Ride
    @ObservedObject var controller: RideController
    @State private var confirmDeletion = false
    @State private var showSpeedMap = true
    @State private var visibleMapCamera: MapCamera?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            AttentionSection(controller: controller)
            Section {
                if segments.isEmpty {
                    ContentUnavailableView("No recorded route", systemImage: "map",
                                           description: Text("This ride has no continuous GPS segment to display."))
                } else {
                    Toggle("Speed heat map", isOn: $showSpeedMap)
                        .accessibilityIdentifier("speedHeatMap")
                    Map(initialPosition: visibleMapCamera.map { .camera($0) } ?? .automatic) {
                        if showSpeedMap {
                            ForEach(ride.speedSegments) { segment in
                                MapPolyline(coordinates: coordinates(segment.samples))
                                    .stroke(segment.band.color, lineWidth: 5)
                            }
                        } else {
                            ForEach(Array(segments.enumerated()), id: \.offset) { _, samples in
                                MapPolyline(coordinates: coordinates(samples)).stroke(.tint, lineWidth: 4)
                            }
                        }
                    }
                    // Replace MapKit's cached overlays without losing the visible camera.
                    .id(showSpeedMap)
                    .onMapCameraChange { visibleMapCamera = $0.camera }
                    .frame(height: 220)
                    .clipShape(.rect(cornerRadius: 16))
                    .accessibilityLabel(showSpeedMap ? "Recorded route coloured by GPS speed" : "Recorded route")
                    .accessibilityHint("Route segments are separated where GPS data is missing. Speed colours match the legend below.")
                    .accessibilityIdentifier("savedRideRouteMap")
                    if showSpeedMap {
                        ForEach(RideSpeedBand.allCases, id: \.self) { band in
                            Label {
                                Text(band.label).font(.caption)
                            } icon: {
                                Image(systemName: "line.diagonal").foregroundStyle(band.color)
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityIdentifier("speedLegend-\(band.rawValue)")
                        }
                        Text("Colours show recorded GPS speed, not an inferred speed across gaps.")
                            .font(.footnote).foregroundStyle(RideTheme.secondaryText)
                    }
                }
            }
            .ridePanelRow()
            Section {
                Text(ride.startedAt, format: .dateTime).font(.headline)
                Text(RideFormat.distance(ride.distance))
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(.tint)
                    .accessibilityLabel(ride.isTrimmedEstimate == true ? "Estimated distance" : "Distance")
                    .accessibilityValue(RideFormat.distance(ride.distance))
                RideMetric("Recording owner", value: ride.owner)
                RideMetric("Elapsed", seconds: ride.elapsed(at: .now))
                if ride.isTrimmedEstimate == true {
                    RideMetric("Moving and stopped time", value: "Unavailable")
                } else {
                    RideMetric("Moving", seconds: ride.movingDuration)
                    RideMetric("Stopped estimate", seconds: ride.stoppedDuration)
                }
                RideMetric("Unknown", seconds: ride.unknownDuration(at: .now))
                RideMetric(ride.isTrimmedEstimate == true ? "Estimated overall average" : "Overall average",
                           value: RideFormat.speed(ride.averageSpeed(at: .now)))
                if ride.isTrimmedEstimate != true {
                    RideMetric("Moving average", value: RideFormat.speed(ride.movingAverageSpeed))
                }
                if ride.isTrimmedEstimate == true {
                    Text("Trimmed copy: distance is estimated from GPS. Moving and stopped time are unknown because pause and stationary events were not retained.")
                        .font(.footnote).foregroundStyle(RideTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } header: {
                Text("Ride summary").foregroundStyle(RideTheme.secondaryText)
            }
            .ridePanelRow()
            #if os(iOS)
            Section {
                NavigationLink {
                    RideTrimView(ride: ride, controller: controller)
                } label: {
                    Label("Trim ride", systemImage: "scissors")
                }
                .disabled(ride.samples.count < 3)
                NavigationLink {
                    RideShareView(ride: ride)
                } label: {
                    Label("Share ride scorecard", systemImage: "square.and.arrow.up")
                }
                .accessibilityIdentifier("shareRideStats")
                Text("Preview an arcade-style image with stats and a route map. Choose protected endpoints, the whole route, or stats only before sharing.")
                    .font(.footnote).foregroundStyle(RideTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("Share").foregroundStyle(RideTheme.secondaryText)
            }
            .ridePanelRow()
            #endif
            #if !os(iOS)
            Section {
                Button("Delete ride", role: .destructive) { confirmDeletion = true }
                    .rideDeletionConfirmation(isPresented: $confirmDeletion, count: 1, delete: deleteRide)
            }
            #endif
        }
        .rideSurface()
        .navigationTitle("Ride")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Delete ride", systemImage: "trash", role: .destructive) { confirmDeletion = true }
                    .rideDeletionConfirmation(isPresented: $confirmDeletion, count: 1, delete: deleteRide)
                    .accessibilityIdentifier("deleteRide")
            }
        }
        #endif
        // Leave the screen once the ride is gone, whether deleted here or from the companion.
        .onChange(of: controller.archive.isDeleted(ride.id)) { _, deleted in
            if deleted { dismiss() }
        }
    }

    private func deleteRide() {
        do { try controller.deleteRides([ride.id]) }
        catch { controller.report(error.localizedDescription) }
    }

    private var segments: [[LocationSample]] {
        ride.routeSegments.filter { $0.count > 1 }
    }

    private func coordinates(_ samples: [LocationSample]) -> [CLLocationCoordinate2D] {
        samples.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
    }
}

#if os(iOS)
private struct RideTrimView: View {
    let ride: Ride
    @ObservedObject var controller: RideController
    @State private var first = 0.0
    @State private var last: Double
    @State private var preview: Ride?
    @State private var showConfirmation = false
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    init(ride: Ride, controller: RideController) {
        self.ride = ride
        self.controller = controller
        _last = State(initialValue: Double(ride.samples.count - 1))
    }

    private var startIndex: Int { Int(first) }
    private var endIndex: Int { Int(last) }
    private var changed: Bool { startIndex > 0 || endIndex < ride.samples.count - 1 }

    var body: some View {
        Form {
            Section {
                Text("Choose the part of your ride to keep.")
                Stepper(value: Binding(get: { startIndex }, set: {
                    first = Double($0)
                    preview = nil
                }), in: 0...(endIndex - 1)) {
                    VStack(alignment: .leading) {
                        Text("Start")
                        Text(ride.samples[startIndex].timestamp, format: .dateTime.month().day().hour().minute().second())
                            .font(.subheadline).foregroundStyle(RideTheme.secondaryText)
                    }
                }
                Slider(value: Binding(get: { first }, set: {
                    first = min($0, last - 1)
                    preview = nil
                }), in: 0...Double(ride.samples.count - 2), step: 1)
                .accessibilityLabel("Trim start")
                .accessibilityValue(ride.samples[startIndex].timestamp.formatted(date: .abbreviated, time: .standard))
                Stepper(value: Binding(get: { endIndex }, set: {
                    last = Double($0)
                    preview = nil
                }), in: (startIndex + 1)...(ride.samples.count - 1)) {
                    VStack(alignment: .leading) {
                        Text("End")
                        Text(ride.samples[endIndex].timestamp, format: .dateTime.month().day().hour().minute().second())
                            .font(.subheadline).foregroundStyle(RideTheme.secondaryText)
                    }
                }
                Slider(value: Binding(get: { last }, set: {
                    last = max($0, first + 1)
                    preview = nil
                }), in: 1...Double(ride.samples.count - 1), step: 1)
                .accessibilityLabel("Trim end")
                .accessibilityValue(ride.samples[endIndex].timestamp.formatted(date: .abbreviated, time: .standard))
                Button("Preview trimmed ride") {
                    do { preview = try ride.trimmedCopy(from: startIndex, through: endIndex); error = nil }
                    catch { self.error = "Couldn't trim this ride: \(error.localizedDescription)" }
                }
                .disabled(!changed)
                if let error { Text(error).foregroundStyle(.red) }
            }
            if let preview {
                Section {
                    if preview.routeSegments.contains(where: { $0.count > 1 }) {
                        Map {
                            ForEach(Array(preview.routeSegments.enumerated()), id: \.offset) { _, samples in
                                if samples.count > 1 {
                                    MapPolyline(coordinates: samples.map {
                                        CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
                                    }).stroke(.tint, lineWidth: 4)
                                }
                            }
                        }
                        .frame(height: 200)
                        .clipShape(.rect(cornerRadius: 16))
                        .accessibilityLabel("Trimmed route preview")
                    }
                    RideMetric("Estimated distance", value: RideFormat.distance(preview.distance))
                    RideMetric("Elapsed", seconds: preview.elapsed(at: .now))
                    RideMetric("Moving and stopped time", value: "Unavailable")
                    Button("Save trimmed copy") { showConfirmation = true }
                        .confirmationDialog("Save a trimmed copy?", isPresented: $showConfirmation,
                                            titleVisibility: .visible) {
                            Button("Save copy") { save(preview) }
                            Button("Cancel", role: .cancel) {}
                        } message: {
                            Text("The original remains in History and both rides count in totals until you delete one. GPS-derived distance is an estimate; moving and stopped time are unknown because earlier pause and stationary events were not saved.")
                        }
                } header: {
                    Text("Preview").foregroundStyle(RideTheme.secondaryText)
                } footer: {
                    Text("Distance is a GPS estimate. Moving and stopped time are unknown because pause and stationary events were not retained.")
                }
            }
        }
        .rideSurface()
        .navigationTitle("Trim ride")
    }

    private func save(_ copy: Ride) {
        do {
            try controller.saveTrimmedCopy(copy, of: ride.id)
            dismiss()
        } catch {
            self.error = "Couldn't save the trimmed copy: \(error.localizedDescription)"
        }
    }
}
#endif

extension RideSpeedBand {
    var color: Color {
        switch self {
        case .slow: .blue
        case .cruising: .green
        case .brisk: .orange
        case .fast: .red
        case .unknown: .gray
        }
    }

    var label: String {
        let unit = RideUnitSystem.selected
        let factor = RideUnits.metersPerMile / unit.metersPerUnit
        let format = unit == .metric ? "%.1f" : "%.0f"
        let five = String(format: format, 5 * factor)
        let ten = String(format: format, 10 * factor)
        let fifteen = String(format: format, 15 * factor)
        switch self {
        case .slow: return "Blue: under \(five) \(unit.speedSymbol)"
        case .cruising: return "Green: \(five) to under \(ten) \(unit.speedSymbol)"
        case .brisk: return "Orange: \(ten) to under \(fifteen) \(unit.speedSymbol)"
        case .fast: return "Red: \(fifteen) \(unit.speedSymbol) or more"
        case .unknown: return "Gray: speed unavailable"
        }
    }
}

#if os(iOS)
private enum DashboardTab: Hashable {
    case ride, history, directions, places
}
#endif

private struct EndRideConfirmation: ViewModifier {
    @Binding var isPresented: Bool
    let end: () -> Void

    func body(content: Content) -> some View {
        content.confirmationDialog("End and save this ride?", isPresented: $isPresented, titleVisibility: .visible) {
            Button("End ride", role: .destructive, action: end)
            Button("Cancel", role: .cancel) {}
        }
    }
}

@Observable
@MainActor
final class RideBarVisibility {
    private var hiddenReasons: Set<String> = []

    var isVisible: Bool { hiddenReasons.isEmpty }

    func setHidden(_ hidden: Bool, reason: String) {
        if hidden { hiddenReasons.insert(reason) } else { hiddenReasons.remove(reason) }
    }
}

extension EnvironmentValues {
    /// Lets a focused screen hide the iPhone tab bar and its Start/End accessory.
    @Entry var rideBarVisibility: RideBarVisibility?
}

extension View {
    func hidesRideBar(_ hidden: Bool = true, reason: String) -> some View {
        modifier(RideBarHiding(hidden: hidden, reason: reason))
    }
}

private struct RideBarHiding: ViewModifier {
    let hidden: Bool
    let reason: String
    @Environment(\.rideBarVisibility) private var visibility

    func body(content: Content) -> some View {
        content
            #if os(iOS)
            .toolbarVisibility(hidden ? .hidden : .automatic, for: .tabBar)
            #endif
            .onAppear { visibility?.setHidden(hidden, reason: reason) }
            .onChange(of: hidden) { _, hidden in visibility?.setHidden(hidden, reason: reason) }
            .onDisappear { visibility?.setHidden(false, reason: reason) }
    }
}

#if os(iOS)
private struct RideAccessoryStatus: View {
    let status: RideRecordingStatus
    let startedAt: Date
    let distance: Double
    let color: Color

    private var title: LocalizedStringResource {
        switch status {
        case .recording: "Recording"
        case .paused: "Recording paused"
        case .remoteRecording: "Device reports recording"
        case .remotePaused: "Device reports recording paused"
        case .remoteOffline: "Recording device offline"
        }
    }

    private var symbol: String {
        switch status {
        case .recording, .remoteRecording: "record.circle"
        case .paused, .remotePaused: "pause.circle"
        case .remoteOffline: "exclamationmark.circle"
        }
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack(spacing: 6) {
                Image(systemName: symbol).foregroundStyle(color)
                Text(RideFormat.duration(context.date.timeIntervalSince(startedAt)))
                Text("·").foregroundStyle(.secondary)
                Text(RideFormat.distance(distance))
            }
            .font(.subheadline.weight(.semibold))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(minHeight: 44)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(title))
            .accessibilityValue("\(RideFormat.spokenDuration(context.date.timeIntervalSince(startedAt))), \(RideFormat.distance(distance))")
            .accessibilityIdentifier("rideAccessoryStatus")
        }
    }
}
#endif
