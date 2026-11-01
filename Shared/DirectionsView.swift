import Combine
import MapKit
import ScooterCore
import SwiftUI

@MainActor
final class DirectionsModel: ObservableObject {
    @Published var destination = ""
    @Published private(set) var steps: [String] = []
    @Published var stepIndex = 0
    @Published private(set) var status = "Walking directions require a recent ride location and network."
    @Published private(set) var loading = false
    private var request: MKDirections?

    func search(from coordinate: CLLocationCoordinate2D?, savedPlace: SavedPlace? = nil) async {
        guard let coordinate else { status = "Start a ride and wait for an accurate location first."; return }
        guard savedPlace != nil || !destination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            status = "Enter a destination."
            return
        }
        loading = true
        steps = []
        defer { loading = false }
        do {
            let destination: MKMapItem
            if let savedPlace {
                destination = MKMapItem(location: CLLocation(latitude: savedPlace.latitude, longitude: savedPlace.longitude), address: nil)
                destination.name = savedPlace.name
            } else {
                let search = MKLocalSearch.Request()
                search.naturalLanguageQuery = self.destination
                search.region = MKCoordinateRegion(center: coordinate, latitudinalMeters: 20_000, longitudinalMeters: 20_000)
                let response = try await MKLocalSearch(request: search).start()
                guard let match = response.mapItems.first else { status = "No matching destination."; return }
                destination = match
            }
            let routeRequest = MKDirections.Request()
            routeRequest.source = MKMapItem(location: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude),
                                            address: nil)
            routeRequest.destination = destination
            routeRequest.transportType = .walking
            let directions = MKDirections(request: routeRequest)
            request = directions
            let routes = try await directions.calculate()
            guard let route = routes.routes.first else { status = "No walking route available."; return }
            steps = route.steps.compactMap { step in
                guard !step.instructions.isEmpty else { return nil }
                return "\(step.instructions) (\(RideUnits.distance(step.distance)))"
            }
            stepIndex = 0
            status = "Walking route to \(destination.name ?? "destination"). Manual step progression."
        } catch { status = "Directions unavailable: \(error.localizedDescription)" }
    }
}

struct DirectionsView: View {
    @ObservedObject var controller: RideController
    @StateObject private var model = DirectionsModel()
    @FocusState private var destinationFocused: Bool

    var body: some View {
        Form {
            Section {
                ForEach(controller.places.visible) { place in
                    Button("Directions to \(place.name)") {
                        Task { await model.search(from: recentCoordinate, savedPlace: place) }
                    }.disabled(model.loading)
                }
                NavigationLink("Manage saved places") { SavedPlacesView(controller: controller) }
            } header: {
                Text("Saved destinations").foregroundStyle(RideTheme.secondaryText)
            }
            Section {
                TextField("Destination", text: $model.destination)
                    .focused($destinationFocused)
                    .submitLabel(.search)
                    .onSubmit { if canFindRoute { findRoute() } }
                    .accessibilityIdentifier("destinationQuery")
                if model.loading { ProgressView("Finding route...") }
                Button("Find walking route") {
                    findRoute()
                }
                .disabled(!canFindRoute)
                .accessibilityIdentifier("findRoute")
                Text(model.status).font(.footnote).foregroundStyle(RideTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section {
                if !model.steps.isEmpty {
                    Text("Step \(model.stepIndex + 1) of \(model.steps.count)").font(.caption)
                    Text(model.steps[model.stepIndex]).font(.headline)
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 12) { stepControls }
                        VStack(spacing: 8) { stepControls }
                    }
                    .buttonStyle(.bordered)
                } else {
                    Text("Find a route to see directions here.").foregroundStyle(RideTheme.secondaryText)
                }
                Text("Not scooter-specific. Check local laws and route safety. No automatic turns, rerouting or haptics.")
                    .font(.footnote).foregroundStyle(RideTheme.secondaryText)
            } header: {
                Text("Manual directions").foregroundStyle(RideTheme.secondaryText)
            }
        }
        .navigationTitle("Directions")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
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

    private var canFindRoute: Bool {
        !model.loading && !model.destination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func findRoute() {
        destinationFocused = false
        Task { await model.search(from: recentCoordinate) }
    }

    private var recentCoordinate: CLLocationCoordinate2D? {
        guard let sample = controller.displayedRide?.samples.last,
              Date.now.timeIntervalSince(sample.timestamp) <= 30 else { return nil }
        return CLLocationCoordinate2D(latitude: sample.latitude, longitude: sample.longitude)
    }
}
