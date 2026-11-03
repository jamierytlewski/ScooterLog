import AVFoundation
import Combine
import CoreLocation
import MapKit
import ScooterCore
import SwiftUI

enum RouteMode: String, CaseIterable, Identifiable {
    case cycling = "Cycling"
    case walking = "Walking"

    var id: String { rawValue }
    var transportType: MKDirectionsTransportType { self == .walking ? .walking : .cycling }
}

struct RouteOption: Identifiable {
    let id = UUID()
    let name: String
    let distance: Double
    let expectedTravelTime: TimeInterval
    let polyline: MKPolyline
    let steps: [RouteInstruction]

    init(_ route: MKRoute) {
        name = route.name
        distance = route.distance
        expectedTravelTime = route.expectedTravelTime
        polyline = route.polyline
        steps = route.steps.enumerated().compactMap { index, step in
            step.instructions.isEmpty ? nil : RouteInstruction(
                id: index, text: step.instructions, distance: step.distance, polyline: step.polyline)
        }
    }

    #if DEBUG
    init(name: String, distance: Double, origin: CLLocationCoordinate2D, destination: CLLocationCoordinate2D,
         mode: RouteMode) {
        self.name = name
        self.distance = distance
        expectedTravelTime = distance / (mode == .walking ? 1.4 : 4.5)
        let midpoint = CLLocationCoordinate2D(latitude: (origin.latitude + destination.latitude) / 2 + 0.002,
                                              longitude: (origin.longitude + destination.longitude) / 2)
        polyline = MKPolyline(coordinates: [origin, midpoint, destination], count: 3)
        let points = [origin, midpoint, destination]
        steps = (0..<2).map { index in
            let segment = [points[index], points[index + 1]]
            return RouteInstruction(
                id: index, text: index == 0 ? "Head toward \(name)" : "Continue to your destination",
                distance: distance / 2, polyline: MKPolyline(coordinates: segment, count: segment.count))
        }
    }
    #endif
}

struct RouteInstruction: Identifiable {
    let id: Int
    let text: String
    let distance: Double
    let polyline: MKPolyline
}

private struct RouteStepProgress {
    let crossTrackDistance: Double
    let distanceToEnd: Double
}

private enum RouteProgress {
    static func closestStep(to location: CLLocationCoordinate2D, in route: RouteOption,
                            startingAt firstStep: Int = 0) -> (index: Int, progress: RouteStepProgress)? {
        guard firstStep < route.steps.count else { return nil }
        return route.steps.indices.dropFirst(firstStep).compactMap { index in
            progress(to: location, on: route.steps[index].polyline).map { (index, $0) }
        }.min { $0.1.crossTrackDistance < $1.1.crossTrackDistance }
    }

    static func progress(to coordinate: CLLocationCoordinate2D, on polyline: MKPolyline) -> RouteStepProgress? {
        guard polyline.pointCount >= 2 else { return nil }
        let points = Array(UnsafeBufferPointer(start: polyline.points(), count: polyline.pointCount))
        let location = MKMapPoint(coordinate)
        let scale = MKMetersPerMapPointAtLatitude(coordinate.latitude)
        var bestDistance = Double.infinity
        var bestRemaining = 0.0
        var traversed = 0.0
        var total = 0.0

        for index in 0..<(points.count - 1) {
            let start = points[index]
            let end = points[index + 1]
            let dx = end.x - start.x
            let dy = end.y - start.y
            let lengthSquared = dx * dx + dy * dy
            let fraction = lengthSquared == 0 ? 0 : min(1, max(0,
                ((location.x - start.x) * dx + (location.y - start.y) * dy) / lengthSquared))
            let projection = MKMapPoint(x: start.x + fraction * dx, y: start.y + fraction * dy)
            let segmentLength = hypot(dx, dy) * scale
            let distance = location.distance(to: projection)
            if distance < bestDistance {
                bestDistance = distance
                bestRemaining = traversed + fraction * segmentLength
            }
            traversed += segmentLength
            total += segmentLength
        }
        return RouteStepProgress(crossTrackDistance: bestDistance, distanceToEnd: max(0, total - bestRemaining))
    }
}

enum PlanningLocationError: LocalizedError {
    case permission, unavailable

    var errorDescription: String? {
        switch self {
        case .permission: "Location access is unavailable. Choose a starting point, or enable location in Settings."
        case .unavailable: "Couldn't find your current location. Try again outdoors or choose a starting point."
        }
    }
}

/// One foreground fix for planning. It never starts a ride or writes to ride storage.
@MainActor
final class PlanningLocation: NSObject, @preconcurrency CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocationCoordinate2D, any Error>?
    private var timeout: Task<Void, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
    }

    func coordinate() async throws -> CLLocationCoordinate2D {
        cancel()
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            timeout = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(15)) }
                catch { return }
                self?.finish(.failure(PlanningLocationError.unavailable))
            }
            switch manager.authorizationStatus {
            case .notDetermined: manager.requestWhenInUseAuthorization()
            case .authorizedAlways, .authorizedWhenInUse: manager.requestLocation()
            default: finish(.failure(PlanningLocationError.permission))
            }
        }
    }

    func cancel() { finish(.failure(CancellationError())) }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard continuation != nil else { return }
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: manager.requestLocation()
        case .notDetermined: break
        default: finish(.failure(PlanningLocationError.permission))
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last(where: {
            CLLocationCoordinate2DIsValid($0.coordinate) && $0.horizontalAccuracy >= 0 && $0.horizontalAccuracy <= 100
                && abs($0.timestamp.timeIntervalSinceNow) <= 60
        }) else {
            finish(.failure(PlanningLocationError.unavailable))
            return
        }
        finish(.success(location.coordinate))
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        finish(.failure(error))
    }

    private func finish(_ result: Result<CLLocationCoordinate2D, any Error>) {
        timeout?.cancel()
        timeout = nil
        manager.stopUpdatingLocation()
        let pending = continuation
        continuation = nil
        pending?.resume(with: result)
    }
}

@MainActor
final class DirectionsModel: ObservableObject {
    static let idleStatus = "Choose a destination to preview routes. No ride needs to be started. Apple Maps requires a network connection."

    @Published private(set) var destination: PlaceChoice?
    @Published private(set) var routes: [RouteOption] = []
    @Published private(set) var selectedRouteID: UUID?
    @Published private(set) var routeOrigin: CLLocationCoordinate2D?
    @Published var stepIndex = 0
    @Published private(set) var isGuiding = false
    @Published private(set) var startedRideForGuidance = false
    @Published private(set) var currentLocation: CLLocation?
    @Published private(set) var distanceToManeuver: Double?
    @Published private(set) var guidanceError: String?
    @Published private(set) var isOffRoute = false
    @Published private(set) var isRerouting = false
    @Published private(set) var hasArrived = false
    @Published private(set) var status = DirectionsModel.idleStatus
    @Published private(set) var loading = false
    private var request: MKDirections?
    private let location = PlanningLocation()
    private var generation = 0
    private var mode: RouteMode?
    private var voiceGuidanceEnabled = false
    private let speaker = AVSpeechSynthesizer()
    private var lastAnnouncedStepIndex = -1
    private var offRouteSamples = 0
    private var automaticRerouteAttempted = false
    private var rerouteTask: Task<Void, Never>?
    private var locationTimeout: Task<Void, Never>?
    private var guidanceRideID: UUID?
    var onGuidanceChange: (() -> Void)?

    var selectedRoute: RouteOption? { routes.first { $0.id == selectedRouteID } }
    var steps: [RouteInstruction] { selectedRoute?.steps ?? [] }
    var guidance: RideGuidance? {
        guard isGuiding, let guidanceRideID, let instruction = steps[safe: stepIndex] else { return nil }
        return RideGuidance(rideID: guidanceRideID, destination: destination?.name ?? "Destination",
                            instruction: instruction.text, nextInstruction: steps[safe: stepIndex + 1]?.text,
                            distanceToManeuver: distanceToManeuver, step: stepIndex + 1, stepCount: steps.count,
                            locationTimestamp: currentLocation?.timestamp, error: guidanceError,
                            isRerouting: isRerouting, hasArrived: hasArrived)
    }

    func select(_ route: RouteOption) {
        stopGuidance()
        selectedRouteID = route.id
        stepIndex = 0
    }

    func cancel() {
        generation += 1
        request?.cancel()
        request = nil
        location.cancel()
        stopGuidance()
        loading = false
    }

    func route(to place: PlaceChoice, from origin: PlaceChoice?, mode: RouteMode) async {
        cancel()
        self.mode = mode
        let token = generation
        destination = place
        routes = []
        selectedRouteID = nil
        routeOrigin = nil
        stepIndex = 0
        loading = true
        status = origin == nil ? "Finding your current location..." : "Finding routes..."
        defer { if token == generation { loading = false } }
        do {
            let coordinate: CLLocationCoordinate2D
            if let origin {
                coordinate = CLLocationCoordinate2D(latitude: origin.latitude, longitude: origin.longitude)
            } else {
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("-ScooterLogStubDirections") {
                    if ProcessInfo.processInfo.arguments.contains("-ScooterLogStubLocationDenied") {
                        throw PlanningLocationError.permission
                    }
                    coordinate = CLLocationCoordinate2D(latitude: 40.7527, longitude: -73.9772)
                } else {
                    coordinate = try await location.coordinate()
                }
                #else
                coordinate = try await location.coordinate()
                #endif
            }
            guard token == generation else { return }
            routeOrigin = coordinate
            status = "Finding \(mode.rawValue.lowercased()) routes..."
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-ScooterLogStubDirections") {
                if ProcessInfo.processInfo.arguments.contains("-ScooterLogStubRouteFailure") {
                    throw URLError(.notConnectedToInternet)
                }
                let target = CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude)
                routes = [
                    RouteOption(name: "Park path", distance: RideUnits.metersPerMile,
                                origin: coordinate, destination: target, mode: mode),
                    RouteOption(name: "Riverside path", distance: 1.2 * RideUnits.metersPerMile,
                                origin: coordinate, destination: target, mode: mode)
                ]
                select(routes[0])
                status = "\(mode.rawValue) routes to \(place.name). Choose a route below."
                return
            }
            #endif
            let target = MKMapItem(location: CLLocation(latitude: place.latitude, longitude: place.longitude), address: nil)
            target.name = place.name
            let routeRequest = MKDirections.Request()
            routeRequest.source = MKMapItem(location: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude),
                                            address: nil)
            routeRequest.destination = target
            routeRequest.transportType = mode.transportType
            routeRequest.requestsAlternateRoutes = true
            let directions = MKDirections(request: routeRequest)
            request = directions
            let response = try await directions.calculate()
            guard token == generation else { return }
            routes = response.routes.map(RouteOption.init)
            guard let first = routes.first else {
                status = "No \(mode.rawValue.lowercased()) route available. Try another travel mode or starting point."
                return
            }
            select(first)
            status = "\(mode.rawValue) routes to \(place.name). Choose a route below."
        } catch {
            guard token == generation else { return }
            status = "Directions unavailable: \(error.localizedDescription) Try again or choose a different starting point."
        }
    }

        func startGuidance(controller: RideController, voiceEnabled: Bool) {
            guard let route = selectedRoute, !route.steps.isEmpty else {
                guidanceError = "This route has no turn instructions."
                return
            }
            guard !isGuiding else { return }
            do {
                startedRideForGuidance = !controller.recording
                if startedRideForGuidance { try controller.start() }
                guidanceRideID = controller.archive.active?.id
                guidanceError = nil
                voiceGuidanceEnabled = voiceEnabled
                isGuiding = true
                lastAnnouncedStepIndex = stepIndex
                hasArrived = false
                offRouteSamples = 0
                automaticRerouteAttempted = false
                defer { onGuidanceChange?() }
                locationTimeout?.cancel()
                locationTimeout = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(25)) }
                    catch { return }
                    guard let self, self.currentLocation == nil, self.isGuiding else { return }
                    self.guidanceError = "The ride has started, but GPS hasn't found an accurate location yet. Wait outdoors for a fix or stop navigation."
                    self.onGuidanceChange?()
                }
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("-ScooterLogStubNavigation"),
                   let routeOrigin {
                    let sample = CLLocation(latitude: routeOrigin.latitude, longitude: routeOrigin.longitude)
                    updateGuidance(sample)
                    if voiceGuidanceEnabled, let instruction = selectedRoute?.steps[safe: stepIndex] {
                        speak("Directions started. \(instruction.text)")
                    }
                    return
                }
                #endif
                updateGuidance(from: controller.displayedRide?.samples.last)
                if voiceGuidanceEnabled, let instruction = selectedRoute?.steps[safe: stepIndex] {
                    speak("Directions started. \(instruction.text)")
                }
            } catch {
                startedRideForGuidance = false
                guidanceError = "Couldn't start the ride: \(error.localizedDescription)"
            }
        }

        func updateGuidance(from sample: LocationSample?) {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-ScooterLogStubNavigation") { return }
            #endif
            guard isGuiding, let sample,
                  Date.now.timeIntervalSince(sample.timestamp) >= 0,
                  Date.now.timeIntervalSince(sample.timestamp) <= 10,
                  sample.accuracy >= 0, sample.accuracy <= 25 else { return }
            updateGuidance(CLLocation(coordinate: CLLocationCoordinate2D(latitude: sample.latitude, longitude: sample.longitude),
                                      altitude: 0, horizontalAccuracy: sample.accuracy, verticalAccuracy: -1,
                                      course: -1, speed: sample.speed, timestamp: sample.timestamp))
        }

        func stopGuidance() {
            let wasGuiding = isGuiding
            locationTimeout?.cancel()
            locationTimeout = nil
            rerouteTask?.cancel()
            rerouteTask = nil
            if speaker.isSpeaking { speaker.stopSpeaking(at: .immediate) }
            isGuiding = false
            startedRideForGuidance = false
            currentLocation = nil
            distanceToManeuver = nil
            guidanceError = nil
            isOffRoute = false
            isRerouting = false
            hasArrived = false
            offRouteSamples = 0
            automaticRerouteAttempted = false
            lastAnnouncedStepIndex = -1
            voiceGuidanceEnabled = false
            guidanceRideID = nil
            if wasGuiding { onGuidanceChange?() }
        }

        func setVoiceGuidance(_ enabled: Bool) {
            voiceGuidanceEnabled = enabled
            if !enabled, speaker.isSpeaking { speaker.stopSpeaking(at: .immediate) }
            if enabled, isGuiding, let instruction = selectedRoute?.steps[safe: stepIndex] {
                speak(instruction.text)
            }
        }

        func recalculateRoute() {
            guard let currentLocation else {
                guidanceError = "Waiting for an accurate location before recalculating."
                return
            }
            automaticRerouteAttempted = true
            rerouteTask?.cancel()
            rerouteTask = Task { await reroute(from: currentLocation) }
        }

        #if DEBUG
        func advanceSimulatedLocation() {
            guard ProcessInfo.processInfo.arguments.contains("-ScooterLogStubNavigation"),
                  isGuiding, let route = selectedRoute, stepIndex + 1 < route.steps.count else { return }
            let next = route.steps[stepIndex + 1].polyline
            guard next.pointCount > 1 else { return }
            let points = Array(UnsafeBufferPointer(start: next.points(), count: next.pointCount))
            let point = MKMapPoint(x: (points[0].x + points[1].x) / 2,
                                   y: (points[0].y + points[1].y) / 2)
            updateGuidance(CLLocation(latitude: point.coordinate.latitude, longitude: point.coordinate.longitude))
        }

        func simulateDetour() {
            guard ProcessInfo.processInfo.arguments.contains("-ScooterLogStubNavigation"),
                  let currentLocation else { return }
            let coordinate = CLLocationCoordinate2D(latitude: currentLocation.coordinate.latitude + 0.01,
                                                    longitude: currentLocation.coordinate.longitude + 0.01)
            let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            updateGuidance(location)
            updateGuidance(location)
            updateGuidance(location)
        }
        #endif

        private func updateGuidance(_ location: CLLocation) {
            guard isGuiding, !hasArrived, let route = selectedRoute else { return }
            let previousStep = stepIndex
            let previousError = guidanceError
            let previousArrival = hasArrived
            defer {
                if previousStep != stepIndex || previousError != guidanceError || previousArrival != hasArrived {
                    onGuidanceChange?()
                }
            }
            currentLocation = location
            locationTimeout?.cancel()
            locationTimeout = nil

            guard let nearest = RouteProgress.closestStep(to: location.coordinate, in: route, startingAt: stepIndex) else {
                return
            }
            let threshold = max(50, location.horizontalAccuracy > 0 ? location.horizontalAccuracy * 1.5 : 50)
            guard nearest.progress.crossTrackDistance <= threshold else {
                offRouteSamples += 1
                if offRouteSamples >= 3, !isOffRoute {
                    isOffRoute = true
                    guidanceError = "You're off this route. Finding a new route from your current location."
                    if voiceGuidanceEnabled { speak("You appear to be off route. Finding a new route.") }
                    if !automaticRerouteAttempted {
                        automaticRerouteAttempted = true
                        rerouteTask = Task { await reroute(from: location) }
                    }
                }
                return
            }

            offRouteSamples = 0
            isOffRoute = false
            guidanceError = nil
            if nearest.index > stepIndex {
                stepIndex = nearest.index
                if voiceGuidanceEnabled, lastAnnouncedStepIndex != stepIndex {
                    speak(route.steps[stepIndex].text)
                    lastAnnouncedStepIndex = stepIndex
                }
            }
            guard let progress = RouteProgress.closestStep(to: location.coordinate, in: route, startingAt: stepIndex)?.progress
            else { return }
            distanceToManeuver = progress.distanceToEnd
            if stepIndex + 1 < route.steps.count, progress.distanceToEnd <= 200, voiceGuidanceEnabled,
               lastAnnouncedStepIndex != stepIndex + 1 {
                speak("In \(spokenDistance(progress.distanceToEnd)), \(route.steps[stepIndex + 1].text)")
                lastAnnouncedStepIndex = stepIndex + 1
            }
            if stepIndex == route.steps.count - 1, progress.distanceToEnd <= max(25, location.horizontalAccuracy) {
                hasArrived = true
                if voiceGuidanceEnabled { speak("You have arrived at \(destination?.name ?? "your destination").") }
            }
        }

        private func reroute(from location: CLLocation) async {
            guard let destination, let mode, !isRerouting else { return }
            isRerouting = true
            onGuidanceChange?()
            defer {
                isRerouting = false
                onGuidanceChange?()
            }
            do {
                let alternatives: [RouteOption]
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("-ScooterLogStubNavigation") {
                    if ProcessInfo.processInfo.arguments.contains("-ScooterLogStubRerouteFailure") {
                        throw URLError(.notConnectedToInternet)
                    }
                    alternatives = [RouteOption(name: "Recalculated route",
                                                distance: RideUnits.metersPerMile,
                                                origin: location.coordinate,
                                                destination: CLLocationCoordinate2D(latitude: destination.latitude,
                                                                                   longitude: destination.longitude),
                                                mode: mode)]
                } else {
                    alternatives = try await requestRoutes(from: location.coordinate, to: destination, mode: mode)
                }
                #else
                alternatives = try await requestRoutes(from: location.coordinate, to: destination, mode: mode)
                #endif
                guard isGuiding, let first = alternatives.first else {
                    guidanceError = "No updated route is available. Stop safely and choose another route."
                    return
                }
                routes = alternatives
                selectedRouteID = first.id
                routeOrigin = location.coordinate
                stepIndex = 0
                lastAnnouncedStepIndex = 0
                distanceToManeuver = nil
                offRouteSamples = 0
                isOffRoute = false
                automaticRerouteAttempted = false
                guidanceError = nil
                if voiceGuidanceEnabled { speak("Route updated. \(first.steps.first?.text ?? "Continue to your destination.")") }
                updateGuidance(location)
            } catch is CancellationError {
                return
            } catch {
                guidanceError = "Couldn't find a new route: \(error.localizedDescription) Stop safely and try again."
                isOffRoute = true
                if voiceGuidanceEnabled { speak("A new route is unavailable. Stop safely and try again.") }
            }
        }

        private func requestRoutes(from coordinate: CLLocationCoordinate2D, to place: PlaceChoice,
                                   mode: RouteMode) async throws -> [RouteOption] {
            let source = MKMapItem(location: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude), address: nil)
            let target = MKMapItem(location: CLLocation(latitude: place.latitude, longitude: place.longitude), address: nil)
            target.name = place.name
            let request = MKDirections.Request()
            request.source = source
            request.destination = target
            request.transportType = mode.transportType
            request.requestsAlternateRoutes = true
            let directions = MKDirections(request: request)
            self.request?.cancel()
            self.request = directions
            return try await directions.calculate().routes.map(RouteOption.init)
        }

        private func speak(_ text: String) {
            guard voiceGuidanceEnabled else { return }
            speaker.stopSpeaking(at: .immediate)
            speaker.speak(AVSpeechUtterance(string: text))
        }

        private func spokenDistance(_ meters: Double) -> String {
            if meters < 160 { return "\(max(10, Int(meters / 10) * 10)) meters" }
            return RideUnits.distance(meters)
        }

    func reportGuidanceError(_ message: String) {
        guidanceError = message
    }
}

struct DirectionsView: View {
    @ObservedObject var controller: RideController
    @ObservedObject private var model: DirectionsModel
    @State private var showingGuidance = false
    @State private var origin: PlaceChoice?
    @State private var mode = RouteMode.cycling
    @AppStorage("f3PlanningSpeedMPH") private var planningSpeed = 20.0
    @AppStorage("directionsVoiceGuidance") private var voiceGuidance = true
    @State private var camera = MapCameraPosition.automatic

    init(controller: RideController) {
        self.controller = controller
        model = controller.directions
    }

    var body: some View {
        Form {
            Section {
                NavigationLink {
                    PlacePicker(near: controller.lastKnownCoordinate) { place in
                        origin = place
                        refresh()
                    }
                } label: {
                    Label(origin?.name ?? "Current location", systemImage: "location")
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(minHeight: 44)
                }
                .accessibilityIdentifier("originQuery")
                if origin != nil {
                    Button("Use current location") {
                        origin = nil
                        refresh()
                    }
                }
                Text("Choose a starting point to plan from anywhere, even without GPS.")
                    .font(.footnote).foregroundStyle(RideTheme.secondaryText)
            } header: {
                Text("Starting point").foregroundStyle(RideTheme.secondaryText)
            }
            Section {
                ForEach(controller.places.visible) { place in
                    if let choice = PlaceChoice(place) {
                        Button("Directions to \(place.name)") { route(to: choice) }
                            .disabled(model.loading)
                    }
                }
                NavigationLink("Manage saved places") { SavedPlacesView(controller: controller) }
            } header: {
                Text("Saved destinations").foregroundStyle(RideTheme.secondaryText)
            }
            Section {
                NavigationLink {
                    PlacePicker(near: controller.lastKnownCoordinate) { place in route(to: place) }
                } label: {
                    destinationLabel
                }
                .accessibilityIdentifier("destinationQuery")
                Picker("Travel mode", selection: $mode) {
                    ForEach(RouteMode.allCases) { Text($0.rawValue).tag($0) }
                }
                .accessibilityIdentifier("routeMode")
                if model.loading { ProgressView("Finding route...") }
                if let destination = model.destination {
                    Button("Refresh route") { route(to: destination) }
                        .disabled(model.loading)
                        .accessibilityIdentifier("findRoute")
                }
                Text(model.status).font(.footnote).foregroundStyle(RideTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("directionsStatus")
            } header: {
                Text("Destination").foregroundStyle(RideTheme.secondaryText)
            }
            if let selected = model.selectedRoute {
                Section {
                    Map(position: $camera, interactionModes: [.zoom]) {
                        ForEach(model.routes) { route in
                            MapPolyline(route.polyline)
                                .stroke(route.id == selected.id ? RideTheme.selected.color : Color.secondary,
                                        lineWidth: route.id == selected.id ? 5 : 2)
                        }
                        if let start = model.routeOrigin {
                            Marker("Start", systemImage: "location", coordinate: start)
                        }
                        if let destination = model.destination {
                            Marker(destination.name, coordinate: CLLocationCoordinate2D(
                                latitude: destination.latitude, longitude: destination.longitude))
                        }
                    }
                    .frame(height: 240)
                    .clipShape(.rect(cornerRadius: 16))
                    .accessibilityLabel("Route preview")
                    .accessibilityHint("Pinch to zoom. Choose an alternative using the route list below.")
                    .accessibilityIdentifier("routePreview")
                    ForEach(model.routes) { route in
                        Button {
                            model.select(route)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(route.name).font(.headline).foregroundStyle(Color.primary)
                                    Text("\(RideUnits.distance(route.distance)) · \(duration(route.expectedTravelTime)) \(mode.rawValue.lowercased())")
                                        .font(.subheadline).foregroundStyle(RideTheme.secondaryText)
                                }
                                .fixedSize(horizontal: false, vertical: true)
                                Spacer()
                                if route.id == selected.id {
                                    Image(systemName: "checkmark").accessibilityHidden(true)
                                }
                            }
                            .frame(minHeight: 44)
                        }
                        .accessibilityIdentifier("routeOption")
                        .accessibilityAddTraits(route.id == selected.id ? .isSelected : [])
                    }
                } header: {
                    Text("Routes").foregroundStyle(RideTheme.secondaryText)
                }
                scooterEstimate(for: selected)
                Section {
                    Toggle("Speak turns aloud", isOn: $voiceGuidance)
                    Button {
                        model.startGuidance(controller: controller, voiceEnabled: voiceGuidance)
                    } label: {
                        Label(controller.recording ? "Start turn-by-turn" : "Start ride & turn-by-turn",
                              systemImage: "location.north.line")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .accessibilityIdentifier("startTurnByTurn")
                    .disabled(model.isGuiding)
                    Text(controller.recording
                         ? "Uses your active ride's GPS. The ride keeps recording if you stop directions."
                         : "Starts GPS ride recording and live directions together.")
                        .font(.footnote).foregroundStyle(RideTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    if let guidanceError = model.guidanceError {
                        Text(guidanceError).font(.footnote).foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("guidanceError")
                    }
                } header: {
                    Text("Turn-by-turn").foregroundStyle(RideTheme.secondaryText)
                }
            }
            Section {
                if !model.steps.isEmpty {
                    Text("Step \(model.stepIndex + 1) of \(model.steps.count)").font(.caption)
                    Text(model.steps[model.stepIndex].text).font(.headline)
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 12) { stepControls }
                        VStack(spacing: 8) { stepControls }
                    }
                    .buttonStyle(.bordered)
                } else {
                    Text("Choose a destination to see directions here.").foregroundStyle(RideTheme.secondaryText)
                }
                Text("Manual steps are available before navigation starts. Live guidance advances steps and recalculates if you go off route. Check local laws and route safety.")
                    .font(.footnote).foregroundStyle(RideTheme.secondaryText)
            } header: {
                Text("Manual directions").foregroundStyle(RideTheme.secondaryText)
            }
        }
        .rideSurface()
        .navigationTitle("Directions")
        .onChange(of: mode) { refresh() }
        .onChange(of: model.selectedRouteID) { camera = .automatic }
        .onDisappear { if !model.isGuiding { model.cancel() } }
        .onAppear { showingGuidance = model.isGuiding }
        .onChange(of: model.isGuiding) { _, guiding in showingGuidance = guiding }
        .navigationDestination(isPresented: $showingGuidance) {
            TurnByTurnView(model: model, controller: controller, voiceGuidance: $voiceGuidance)
        }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    @ViewBuilder private var stepControls: some View {
        Button { model.stepIndex -= 1 } label: {
            Label("Back", systemImage: "chevron.left").frame(minWidth: 44, minHeight: 44)
                .fixedSize(horizontal: true, vertical: false)
        }
        .disabled(model.stepIndex == 0)
        .accessibilityLabel("Previous direction")
        Button { model.stepIndex += 1 } label: {
            Label("Next", systemImage: "chevron.right").frame(minWidth: 44, minHeight: 44)
                .fixedSize(horizontal: true, vertical: false)
        }
        .disabled(model.stepIndex == model.steps.count - 1)
        .accessibilityLabel("Next direction")
    }

    @ViewBuilder private var destinationLabel: some View {
        if let place = model.destination {
            VStack(alignment: .leading, spacing: 2) {
                Text(place.name)
                if !place.detail.isEmpty {
                    Text(place.detail).font(.footnote).foregroundStyle(RideTheme.secondaryText)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .accessibilityElement(children: .combine)
        } else {
            Label("Search for a destination", systemImage: "magnifyingglass")
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        }
    }

    private func route(to place: PlaceChoice) {
        let start = origin
        let travelMode = mode
        Task { await model.route(to: place, from: start, mode: travelMode) }
    }

    private func refresh() {
        if let destination = model.destination { route(to: destination) }
    }

    private func duration(_ seconds: TimeInterval) -> String {
        let minutes = max(1, Int(ceil(seconds / 60)))
        return Duration.seconds(minutes * 60)
            .formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }

    @ViewBuilder private func scooterEstimate(for route: RouteOption) -> some View {
        Section {
            Text("Segway F3 · Max speed 20 mph · Battery 477 Wh")
                .font(.subheadline).fixedSize(horizontal: false, vertical: true)
            Stepper(value: $planningSpeed, in: 5...ScooterEstimate.maximumSpeedMPH, step: 1) {
                Text("Planning speed: \(planningSpeed, specifier: "%.0f") mph")
            }
            .accessibilityIdentifier("planningSpeed")
            if let estimate = ScooterEstimate(distanceMeters: route.distance, speedMPH: planningSpeed) {
                Text("At \(planningSpeed, specifier: "%.0f") mph, without stops: \(duration(estimate.noStopDuration))")
                    .accessibilityIdentifier("scooterDuration")
                Text("Rated energy estimate: \(estimate.energyWattHours.lowerBound, specifier: "%.1f")–\(estimate.energyWattHours.upperBound, specifier: "%.1f") Wh")
                    .accessibilityIdentifier("scooterEnergy")
                Text("\(estimate.batteryPercent.lowerBound, specifier: "%.1f")–\(estimate.batteryPercent.upperBound, specifier: "%.1f")% of a full new battery")
                if estimate.batteryPercent.upperBound > 100 {
                    Label("This route exceeds the F3's 25-mile full-speed rated range.", systemImage: "exclamationmark.triangle")
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text("Planning speed is invalid. Reset it to estimate this route.")
                Button("Reset planning speed") { planningSpeed = ScooterEstimate.maximumSpeedMPH }
            }
        } header: {
            Text("Scooter estimate").foregroundStyle(RideTheme.secondaryText)
        } footer: {
            Text("Time assumes riding this entire route at the selected speed; stops and slower sections add time. Energy uses F3 ratings of 43.5 mi at 9 mph and 25 mi at 20 mph, not live battery data or a speed-specific prediction. Hills, load, wind, temperature, tires and riding habits can put actual use outside this band. Walking and cycling routes are not verified for scooters.")
                .foregroundStyle(RideTheme.secondaryText)
        }
    }
}

struct TurnByTurnView: View {
    @ObservedObject var model: DirectionsModel
    @ObservedObject var controller: RideController
    @Binding var voiceGuidance: Bool
    @State private var camera = MapCameraPosition.automatic
    @State private var confirmEndRide = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            if let route = model.selectedRoute {
                Map(position: $camera, interactionModes: [.zoom]) {
                    MapPolyline(route.polyline).stroke(RideTheme.selected.color.opacity(0.35), lineWidth: 5)
                    if let location = model.currentLocation {
                        Marker("You", systemImage: "location.fill", coordinate: location.coordinate)
                    }
                    if let destination = model.destination {
                        Marker(destination.name, coordinate: CLLocationCoordinate2D(
                            latitude: destination.latitude, longitude: destination.longitude))
                    }
                }
                .accessibilityLabel("Live route map")
                .accessibilityHint("Pinch to zoom. The map follows your GPS location.")
                .accessibilityIdentifier("liveRouteMap")
                .frame(maxHeight: .infinity)
                .onChange(of: model.currentLocation?.timestamp) { updateCamera() }

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if model.hasArrived {
                            Label("You've reached \(model.destination?.name ?? "your destination").",
                                  systemImage: "checkmark.circle.fill")
                                .font(.title2.bold())
                                .accessibilityIdentifier("navigationArrival")
                        } else if model.isOffRoute {
                            Label(model.guidanceError ?? "You're off this route. Finding a new route.",
                                  systemImage: "exclamationmark.triangle.fill")
                                .font(.headline).foregroundStyle(.orange)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("offRouteWarning")
                            Button("Recalculate route from here") { model.recalculateRoute() }
                                .disabled(model.isRerouting)
                                .accessibilityIdentifier("recalculateRoute")
                        } else if let instruction = route.steps[safe: model.stepIndex] {
                            Text("STEP \(model.stepIndex + 1) OF \(route.steps.count)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(RideTheme.secondaryText)
                            Text(instruction.text)
                                .font(.title2.bold())
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityAddTraits(.updatesFrequently)
                                .accessibilityIdentifier("currentManeuver")
                            if let distance = model.distanceToManeuver,
                               model.stepIndex + 1 < route.steps.count {
                                Text("Next turn in \(RideUnits.distance(distance))")
                                    .font(.headline)
                                    .accessibilityIdentifier("maneuverDistance")
                                Text("Then: \(route.steps[model.stepIndex + 1].text)")
                                    .font(.body).foregroundStyle(RideTheme.secondaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                            } else if model.stepIndex + 1 == route.steps.count {
                                Text("Final direction").font(.subheadline)
                                    .foregroundStyle(RideTheme.secondaryText)
                            }
                            Button("Recalculate route from here") { model.recalculateRoute() }
                                .disabled(model.isRerouting || model.currentLocation == nil)
                                .accessibilityIdentifier("recalculateRoute")
                        } else if let error = model.guidanceError {
                            Text(error).foregroundStyle(.red)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            ProgressView("Waiting for an accurate GPS location...")
                        }
                        Toggle("Speak turns aloud", isOn: $voiceGuidance)
                            .onChange(of: voiceGuidance) { model.setVoiceGuidance(voiceGuidance) }
                        #if DEBUG
                        if ProcessInfo.processInfo.arguments.contains("-ScooterLogStubNavigation") {
                            Button("Advance simulated location") { model.advanceSimulatedLocation() }
                                .accessibilityIdentifier("simulateTurn")
                            Button("Simulate a detour") { model.simulateDetour() }
                                .accessibilityIdentifier("simulateDetour")
                        }
                        #endif
                        if model.startedRideForGuidance {
                            Button("End ride and directions", role: .destructive) {
                                confirmEndRide = true
                            }
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .accessibilityIdentifier("endRideAndDirections")
                            Button("Stop directions (keep ride recording)") {
                                model.stopGuidance()
                            }
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .accessibilityIdentifier("stopDirectionsKeepRide")
                        } else {
                            Button("Stop directions") {
                                model.stopGuidance()
                            }
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .accessibilityIdentifier("endNavigation")
                        }
                        Text("Directions follow the recording device's GPS, including in the background. The paired watch shows the current instruction while connected. Follow a safe, legal detour if the route is blocked.")
                            .font(.footnote).foregroundStyle(RideTheme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding()
                }
                .background(RideTheme.panel)
                .frame(maxHeight: 360)
            } else {
                ContentUnavailableView("Route unavailable", systemImage: "map",
                                       description: Text(model.guidanceError ?? "Choose a route before starting directions."))
            }
        }
        .background(RideTheme.canvas)
        .navigationTitle("Turn-by-turn")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear {
            updateCamera()
            model.updateGuidance(from: controller.displayedRide?.samples.last)
        }
        .onChange(of: model.isGuiding) { _, guiding in
            if !guiding { dismiss() }
        }
        .confirmationDialog("End this ride and save it?", isPresented: $confirmEndRide,
                            titleVisibility: .visible) {
            Button("End ride and save", role: .destructive) {
                do {
                    try controller.end()
                    model.stopGuidance()
                } catch {
                    model.reportGuidanceError("Couldn't end the ride: \(error.localizedDescription)")
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The recorded ride will be saved to History.")
        }
    }

    private func updateCamera() {
        guard let location = model.currentLocation else { return }
        camera = .camera(MapCamera(centerCoordinate: location.coordinate, distance: 900,
                                   heading: location.course >= 0 ? location.course : 0, pitch: 35))
    }
}

struct RideGuidanceSummary: View {
    let guidance: RideGuidance
    let now: Date
    let recording: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(guidance.destination, systemImage: "location.north.line")
                .font(.caption).foregroundStyle(RideTheme.secondaryText)
            if guidance.hasArrived {
                Label("You've arrived", systemImage: "checkmark.circle.fill").font(.headline)
            } else if let error = guidance.error {
                Label(error, systemImage: "exclamationmark.triangle").font(.headline)
            } else {
                Text(guidance.instruction)
                    .font(.title3.bold())
                    .accessibilityIdentifier("dashboardManeuver")
                if !recording {
                    Text("Recording paused. Resume GPS on the recording device.").font(.footnote)
                } else if !guidance.hasFreshLocation(at: now) {
                    Text("Waiting for fresh GPS. This is the last known direction.").font(.footnote)
                } else if let distance = guidance.distanceToManeuver {
                    Text("\(RideUnits.distance(distance)) to \(guidance.nextInstruction == nil ? "destination" : "next turn")")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(RideTheme.selected.color)
                }
                if let next = guidance.nextInstruction, recording, guidance.hasFreshLocation(at: now) {
                    Text("Then: \(next)").font(.body).foregroundStyle(RideTheme.secondaryText)
                }
            }
            if guidance.isRerouting { ProgressView("Updating route...") }
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .contain)
    }
}

struct CompanionDirectionsView: View {
    @ObservedObject var controller: RideController

    var body: some View {
        List {
            if let guidance = controller.peer?.activeGuidance {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    RideGuidanceSummary(guidance: guidance, now: context.date,
                                        recording: controller.peer?.recording == true)
                }
                Text("Step \(guidance.step) of \(guidance.stepCount)").font(.caption)
                Text(controller.reachable
                     ? "Directions from \(controller.peer?.ride?.owner ?? "the companion")."
                     : "Companion offline. Directions may be out of date.")
                    .font(.footnote).foregroundStyle(RideTheme.secondaryText)
                Text("Change or stop navigation on the recording device.").font(.footnote)
            } else {
                Text("No live directions from the recording device. Choose a destination and start turn-by-turn there.")
            }
        }
        .rideSurface()
        .navigationTitle("Turn-by-turn")
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
