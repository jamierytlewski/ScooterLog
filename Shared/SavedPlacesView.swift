import ScooterCore
import SwiftUI

struct SavedPlacesView: View {
    @ObservedObject var controller: RideController
    #if os(iOS)
    @State private var name = ""
    @State private var editing: SavedPlace?
    @State private var showName = false
    @State private var pendingDelete: SavedPlace?
    @State private var confirmDelete = false
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
                NavigationLink {
                    AddPlaceView(controller: controller)
                } label: {
                    Label("Search for a place", systemImage: "magnifyingglass")
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
                .accessibilityIdentifier("addPlace")
            } header: {
                Text("Add a place").foregroundStyle(RideTheme.secondaryText)
            } footer: {
                Text("Find an address, business or landmark, then name it Home, Work or anything you like.")
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
        .alert("Rename place", isPresented: $showName) {
            TextField("Home, Work, or any name", text: $name)
            Button("Save") {
                controller.perform {
                    guard var place = editing else { return }
                    place.name = trimmedName
                    place.modifiedAt = max(.now, place.modifiedAt.addingTimeInterval(0.001))
                    try controller.savePlace(place)
                }
            }
            .disabled(trimmedName.isEmpty || trimmedName.count > PlaceChoice.maxSavedNameLength)
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

    private func rename(_ place: SavedPlace) {
        editing = place
        name = place.name
        showName = true
    }

    private func requestDelete(_ place: SavedPlace) {
        pendingDelete = place
        confirmDelete = true
    }
    #endif
}

#if os(iOS)
struct AddPlaceView: View {
    @ObservedObject var controller: RideController
    @Environment(\.dismiss) private var dismiss
    @State private var choice: PlaceChoice?
    @State private var name = ""
    @State private var showName = false

    var body: some View {
        PlacePicker(near: controller.lastKnownCoordinate, dismissesOnPick: false) { place in
            choice = place
            name = place.suggestedSavedName
            showName = true
        }
        .alert("Name this place", isPresented: $showName, presenting: choice) { place in
            TextField("Home, Work, or any name", text: $name)
            Button("Save") { save(place) }
                .disabled(trimmedName.isEmpty || trimmedName.count > PlaceChoice.maxSavedNameLength)
            Button("Cancel", role: .cancel) {}
        } message: { place in
            Text("\(summary(of: place))\nGive it a short name such as Home or Work (up to 100 characters).")
        }
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func summary(of place: PlaceChoice) -> String {
        [place.name, place.detail].filter { !$0.isEmpty }.joined(separator: ", ")
    }

    private func save(_ place: PlaceChoice) {
        controller.perform {
            try controller.savePlace(SavedPlace(name: trimmedName, latitude: place.latitude, longitude: place.longitude))
        }
        dismiss()
    }
}
#endif
