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
    @State private var pendingDelete: SavedPlace?
    @State private var confirmDelete = false
    @FocusState private var searchFocused: Bool
    #endif

    var body: some View {
        List {
            if let message = controller.errorMessage {
                Section {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Dismiss message") { controller.errorMessage = nil }
                } header: {
                    Text("Needs attention").foregroundStyle(RideTheme.secondaryText)
                }
            }
            Section {
                if controller.places.visible.isEmpty {
                    Text("Add Home, Work or any named place on iPhone. Places sync to your watch.")
                }
                ForEach(controller.places.visible) { place in
                    #if os(iOS)
                    HStack(alignment: .top) {
                        Text(place.name)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        Spacer()
                        Menu {
                            Button("Rename", systemImage: "pencil") { rename(place) }
                            Button("Delete", systemImage: "trash", role: .destructive) { requestDelete(place) }
                        } label: {
                            Image(systemName: "ellipsis")
                                .frame(minWidth: 44, minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .accessibilityLabel("Actions for \(place.name)")
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button("Delete", systemImage: "trash", role: .destructive) { requestDelete(place) }
                        Button("Rename", systemImage: "pencil") { rename(place) }
                    }
                    #else
                    Text(place.name)
                    #endif
                }
            } header: {
                Text("Saved places").foregroundStyle(RideTheme.secondaryText)
            }
            #if os(iOS)
            Section {
                TextField("Address or place", text: $search.query)
                    .focused($searchFocused)
                    .submitLabel(.search)
                    .onSubmit { if canSearch { searchPlaces() } }
                    .accessibilityIdentifier("placeQuery")
                if search.loading { ProgressView("Searching...") }
                Button("Search Apple Maps") { searchPlaces() }
                    .disabled(!canSearch)
                    .accessibilityIdentifier("searchPlaces")
                Text(search.status).font(.footnote).foregroundStyle(RideTheme.secondaryText)
                ForEach(Array(search.results.enumerated()), id: \.offset) { _, item in
                    Button {
                        selected = item
                        editing = nil
                        name = ""
                        searchFocused = false
                        showName = true
                    } label: {
                        VStack(alignment: .leading) {
                            Text(item.name ?? "Place").foregroundStyle(.primary)
                            Text(item.address?.fullAddress ?? "").font(.caption).foregroundStyle(RideTheme.secondaryText)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } header: {
                Text("Add a place").foregroundStyle(RideTheme.secondaryText)
            }
            #endif
            Section {
                Text("Saved names and coordinates stay local and sync to your companion. Optional private iCloud sync includes them only when enabled and run.")
                    .font(.caption)
            }
        }
        .navigationTitle("Saved places")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
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
            .disabled(trimmedName.isEmpty || trimmedName.count > 100)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Use Home, Work or another name (up to 100 characters).")
        }
        .confirmationDialog("Delete saved place?", isPresented: $confirmDelete, titleVisibility: .visible,
                            presenting: pendingDelete) { place in
            Button("Delete place", role: .destructive) {
                controller.perform { try controller.deletePlace(place.id) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { place in
            Text("Remove \(place.name) from saved places? Completed rides are not affected.")
        }
        #endif
    }

    #if os(iOS)
    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSearch: Bool {
        !search.loading && !search.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func searchPlaces() {
        searchFocused = false
        Task { await search.search() }
    }

    private func rename(_ place: SavedPlace) {
        editing = place
        selected = nil
        name = place.name
        showName = true
    }

    private func requestDelete(_ place: SavedPlace) {
        pendingDelete = place
        confirmDelete = true
    }
    #endif
}
