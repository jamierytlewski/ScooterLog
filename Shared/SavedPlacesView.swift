import Combine
import MapKit
import ScooterCore
import SwiftUI

@MainActor
final class PlaceSearch: ObservableObject {
    @Published var query = ""
    @Published private(set) var results: [MKMapItem] = []
    @Published private(set) var status = "Search for a street address or place, then give it a name."
    @Published private(set) var loading = false

    func search() async {
        results = []
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            status = "Enter an address or place."
            return
        }
        loading = true
        defer { loading = false }
        do {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = query
            results = try await MKLocalSearch(request: request).start().mapItems
            status = results.isEmpty ? "No results. Try a more specific address." : "Select the correct result."
        } catch { status = "Place search failed: \(error.localizedDescription)" }
    }
}

struct SavedPlacesView: View {
    @ObservedObject var controller: RideController
    #if os(iOS)
    @StateObject private var search = PlaceSearch()
    @State private var selected: MKMapItem?
    @State private var name = ""
    @State private var editing: SavedPlace?
    @State private var showName = false
    #endif

    var body: some View {
        List {
            if let message = controller.errorMessage {
                Section("Needs attention") {
                    Text(message).foregroundStyle(.red)
                    Button("Dismiss message") { controller.errorMessage = nil }
                }
            }
            Section("Saved places") {
                if controller.places.visible.isEmpty {
                    Text("Add Home, Work or any named place on iPhone. Places sync to your watch.")
                }
                ForEach(controller.places.visible) { place in
                    #if os(iOS)
                    HStack {
                        Text(place.name)
                        Spacer()
                        Button("Rename") {
                            editing = place
                            selected = nil
                            name = place.name
                            showName = true
                        }.buttonStyle(.bordered)
                        Button(role: .destructive) {
                            controller.perform { try controller.deletePlace(place.id) }
                        } label: { Image(systemName: "trash") }
                            .buttonStyle(.bordered)
                            .accessibilityLabel("Delete \(place.name)")
                    }
                    #else
                    Text(place.name)
                    #endif
                }
            }
            #if os(iOS)
            Section("Add a place") {
                TextField("Address or place", text: $search.query)
                Button(search.loading ? "Searching..." : "Search Apple Maps") { Task { await search.search() } }
                    .disabled(search.loading)
                Text(search.status).font(.caption)
                ForEach(Array(search.results.enumerated()), id: \.offset) { _, item in
                    Button {
                        selected = item
                        editing = nil
                        name = ""
                        showName = true
                    } label: {
                        VStack(alignment: .leading) {
                            Text(item.name ?? "Place")
                            Text(item.address?.fullAddress ?? "").font(.caption)
                        }
                    }
                }
            }
            #endif
            Section {
                Text("Saved names and coordinates stay local and sync to your companion. Optional private iCloud sync includes them only when enabled and run.")
                    .font(.caption)
            }
        }
        .navigationTitle("Saved places")
        #if os(iOS)
        .alert(editing == nil ? "Name this place" : "Rename place", isPresented: $showName) {
            TextField("Home, Work, or any name", text: $name)
            Button("Save") {
                controller.perform {
                    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    if var place = editing {
                        place.name = trimmed
                        place.modifiedAt = max(.now, place.modifiedAt.addingTimeInterval(0.001))
                        try controller.savePlace(place)
                    } else if let selected {
                        let coordinate = selected.location.coordinate
                        try controller.savePlace(SavedPlace(name: trimmed, latitude: coordinate.latitude, longitude: coordinate.longitude))
                    }
                }
            }
            .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || name.count > 100)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Use Home, Work or another name (up to 100 characters).")
        }
        #endif
    }
}
