import Combine
import MapKit
import ScooterCore
import SwiftUI

@MainActor
final class DirectionsModel: ObservableObject {
    static let idleStatus = "Search for a destination to see walking directions. Directions need a recent ride location and network."

    @Published private(set) var destination: PlaceChoice?
    @Published private(set) var steps: [String] = []
    @Published var stepIndex = 0
    @Published private(set) var status = DirectionsModel.idleStatus
    @Published private(set) var loading = false
    private var request: MKDirections?
    private var generation = 0

    func route(to place: PlaceChoice, from coordinate: CLLocationCoordinate2D?) async {
        generation += 1
        let token = generation
        request?.cancel()
        destination = place
        steps = []
        stepIndex = 0
        guard let coordinate else {
            loading = false
            status = "Start a ride and wait for an accurate location first."
            return
        }
        loading = true
        defer { if token == generation { loading = false } }
        do {
            let target = MKMapItem(location: CLLocation(latitude: place.latitude, longitude: place.longitude), address: nil)
            target.name = place.name
            let routeRequest = MKDirections.Request()
            routeRequest.source = MKMapItem(location: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude),
                                            address: nil)
            routeRequest.destination = target
            routeRequest.transportType = .walking
            let directions = MKDirections(request: routeRequest)
            request = directions
            let routes = try await directions.calculate()
            guard token == generation else { return }
            guard let route = routes.routes.first else { status = "No walking route available."; return }
            steps = route.steps.compactMap { step in
                guard !step.instructions.isEmpty else { return nil }
                return "\(step.instructions) (\(RideUnits.distance(step.distance)))"
            }
            stepIndex = 0
            status = "Walking route to \(place.name). Manual step progression."
        } catch {
            guard token == generation else { return }
            status = "Directions unavailable: \(error.localizedDescription)"
        }
    }
}

struct DirectionsView: View {
    @ObservedObject var controller: RideController
    @StateObject private var model = DirectionsModel()

    var body: some View {
        Form {
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
                if model.loading { ProgressView("Finding route...") }
                if let destination = model.destination {
                    Button("Refresh route") { route(to: destination) }
                        .disabled(model.loading)
                        .accessibilityIdentifier("findRoute")
                }
                Text(model.status).font(.footnote).foregroundStyle(RideTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("Destination").foregroundStyle(RideTheme.secondaryText)
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
                    Text("Choose a destination to see directions here.").foregroundStyle(RideTheme.secondaryText)
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
        Task { await model.route(to: place, from: recentCoordinate) }
    }

    private var recentCoordinate: CLLocationCoordinate2D? {
        guard let sample = controller.displayedRide?.samples.last,
              Date.now.timeIntervalSince(sample.timestamp) <= 30 else { return nil }
        return CLLocationCoordinate2D(latitude: sample.latitude, longitude: sample.longitude)
    }
}
