import Combine
import CoreLocation
import MapKit
import ScooterCore
import SwiftUI

/// One autocomplete row. `handle` ties it back to the search completion that produced it.
struct PlaceSuggestion: Identifiable, Equatable, Sendable {
    let id: String
    let handle: UUID
    let title: AttributedString
    let subtitle: AttributedString
    let plainTitle: String
    let plainSubtitle: String
}

/// Builds suggestions with row identities that stay stable between keystrokes, so the list updates in place.
struct SuggestionBuilder {
    private var seen: [String: Int] = [:]

    mutating func make(handle: UUID = UUID(), title: String, titleRanges: [NSRange],
                       subtitle: String, subtitleRanges: [NSRange]) -> PlaceSuggestion {
        let key = "\(title)|\(subtitle)"
        let occurrence = seen[key, default: 0]
        seen[key] = occurrence + 1
        return PlaceSuggestion(id: "\(key)|\(occurrence)", handle: handle,
                               title: MatchHighlighting.attributed(title, ranges: titleRanges),
                               subtitle: MatchHighlighting.attributed(subtitle, ranges: subtitleRanges),
                               plainTitle: title, plainSubtitle: subtitle)
    }
}

enum PlaceSearchError: LocalizedError {
    case expiredSuggestion

    var errorDescription: String? { "That suggestion is out of date. Pick another." }
}

@MainActor
protocol PlaceSearchService: AnyObject {
    /// Called with the query fragment the suggestions answer, so late answers can be recognised as stale.
    var onSuggestions: (String, [PlaceSuggestion]) -> Void { get set }
    var onFailure: (String, String) -> Void { get set }
    func suggest(_ fragment: String, near origin: CLLocationCoordinate2D?)
    func resolve(_ suggestion: PlaceSuggestion, near origin: CLLocationCoordinate2D?) async throws -> [PlaceChoice]
    func search(_ text: String, near origin: CLLocationCoordinate2D?) async throws -> [PlaceChoice]
}

enum PlaceSearchServices {
    @MainActor static func make() -> any PlaceSearchService {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ScooterLogStubPlaceSearch") { return StubPlaceSearchService() }
        #endif
        return MapKitPlaceSearchService()
    }
}

private extension PlaceChoice {
    init?(mapItem: MKMapItem) {
        let coordinate = mapItem.location.coordinate
        let address = mapItem.addressRepresentations?.fullAddress(includingRegion: false, singleLine: true)
            ?? mapItem.address?.fullAddress
        self.init(name: mapItem.name, address: address, latitude: coordinate.latitude, longitude: coordinate.longitude)
    }
}

@MainActor
final class MapKitPlaceSearchService: NSObject, PlaceSearchService, MKLocalSearchCompleterDelegate {
    var onSuggestions: (String, [PlaceSuggestion]) -> Void = { _, _ in }
    var onFailure: (String, String) -> Void = { _, _ in }
    private let completer = MKLocalSearchCompleter()
    // Every completion handed out stays resolvable, so a tap on a row that just refreshed never picks a different place.
    private var completions: [UUID: MKLocalSearchCompletion] = [:]

    override init() {
        super.init()
        completer.delegate = self
    }

    func suggest(_ fragment: String, near origin: CLLocationCoordinate2D?) {
        if let origin { completer.region = Self.region(around: origin) }
        completer.queryFragment = fragment
    }

    func resolve(_ suggestion: PlaceSuggestion, near origin: CLLocationCoordinate2D?) async throws -> [PlaceChoice] {
        guard let completion = completions[suggestion.handle] else { throw PlaceSearchError.expiredSuggestion }
        let request = MKLocalSearch.Request(completion: completion)
        if let origin { request.region = Self.region(around: origin) }
        return Self.choices(from: try await MKLocalSearch(request: request).start())
    }

    func search(_ text: String, near origin: CLLocationCoordinate2D?) async throws -> [PlaceChoice] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text
        if let origin { request.region = Self.region(around: origin) }
        return Self.choices(from: try await MKLocalSearch(request: request).start())
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let batch = CompletionBatch(fragment: completer.queryFragment, completions: completer.results)
        Task { @MainActor in self.received(batch) }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: any Error) {
        let fragment = completer.queryFragment
        let message = PlaceSearchModel.message(for: error)
        Task { @MainActor in self.onFailure(fragment, message) }
    }

    private func received(_ batch: CompletionBatch) {
        var builder = SuggestionBuilder()
        let suggestions = batch.completions.map { completion in
            let handle = UUID()
            completions[handle] = completion
            return builder.make(handle: handle,
                                title: completion.title, titleRanges: completion.titleHighlightRanges.map(\.rangeValue),
                                subtitle: completion.subtitle, subtitleRanges: completion.subtitleHighlightRanges.map(\.rangeValue))
        }
        onSuggestions(batch.fragment, suggestions)
    }

    private static func region(around origin: CLLocationCoordinate2D) -> MKCoordinateRegion {
        MKCoordinateRegion(center: origin, latitudinalMeters: 40_000, longitudinalMeters: 40_000)
    }

    private static func choices(from response: MKLocalSearch.Response) -> [PlaceChoice] {
        var seen = Set<String>()
        return response.mapItems.compactMap(PlaceChoice.init(mapItem:)).filter { seen.insert($0.id).inserted }
    }
}

/// MapKit hands completions over on its own schedule. They are immutable value-like objects, so moving them to the main actor is safe.
private struct CompletionBatch: @unchecked Sendable {
    let fragment: String
    let completions: [MKLocalSearchCompletion]
}

#if DEBUG
/// Deterministic stand-in for Apple Maps, selected with the `-ScooterLogStubPlaceSearch` launch argument so UI tests do not depend on the network.
@MainActor
final class StubPlaceSearchService: PlaceSearchService {
    var onSuggestions: (String, [PlaceSuggestion]) -> Void = { _, _ in }
    var onFailure: (String, String) -> Void = { _, _ in }
    private var resolutions: [UUID: [PlaceChoice]] = [:]
    private var pending: Task<Void, Never>?

    private static let landmarks = [
        PlaceChoice(name: "Central Park", address: "New York, NY", latitude: 40.7829, longitude: -73.9654),
        PlaceChoice(name: "Central Park Zoo", address: "830 5th Ave, New York, NY", latitude: 40.7678, longitude: -73.9718),
        PlaceChoice(name: "Central Station", address: "89 E 42nd St, New York, NY", latitude: 40.7527, longitude: -73.9772)
    ].compactMap { $0 }
    private static let coffee = [
        PlaceChoice(name: "Blue Bottle Coffee", address: "1 Rockefeller Plz, New York, NY", latitude: 40.7587, longitude: -73.9787),
        PlaceChoice(name: "Joe Coffee", address: "141 Waverly Pl, New York, NY", latitude: 40.7329, longitude: -74.0003)
    ].compactMap { $0 }

    func suggest(_ fragment: String, near origin: CLLocationCoordinate2D?) {
        pending?.cancel()
        guard !fragment.isEmpty else {
            onSuggestions(fragment, [])
            return
        }
        pending = Task {
            try? await Task.sleep(for: .milliseconds(60))
            guard !Task.isCancelled else { return }
            if fragment.localizedCaseInsensitiveContains("offline") {
                onFailure(fragment, "Can't reach Apple Maps. Check your connection and try again.")
                return
            }
            var builder = SuggestionBuilder()
            var suggestions: [PlaceSuggestion] = []
            for place in Self.landmarks where place.name.localizedCaseInsensitiveContains(fragment) {
                let handle = UUID()
                resolutions[handle] = [place]
                suggestions.append(builder.make(handle: handle, title: place.name, titleRanges: [Self.range(of: fragment, in: place.name)],
                                                subtitle: place.detail, subtitleRanges: []))
            }
            if "coffee".hasPrefix(fragment.lowercased()) {
                let handle = UUID()
                resolutions[handle] = Self.coffee
                suggestions.append(builder.make(handle: handle, title: "Coffee", titleRanges: [NSRange(location: 0, length: fragment.count)],
                                                subtitle: "Search Nearby", subtitleRanges: []))
            }
            onSuggestions(fragment, suggestions)
        }
    }

    func resolve(_ suggestion: PlaceSuggestion, near origin: CLLocationCoordinate2D?) async throws -> [PlaceChoice] {
        try await Task.sleep(for: .milliseconds(60))
        guard let places = resolutions[suggestion.handle] else { throw PlaceSearchError.expiredSuggestion }
        return places
    }

    func search(_ text: String, near origin: CLLocationCoordinate2D?) async throws -> [PlaceChoice] {
        try await Task.sleep(for: .milliseconds(60))
        if text.localizedCaseInsensitiveContains("offline") { throw URLError(.notConnectedToInternet) }
        return (Self.landmarks + Self.coffee).filter { $0.name.localizedCaseInsensitiveContains(text) }
    }

    private static func range(of fragment: String, in text: String) -> NSRange {
        (text as NSString).range(of: fragment, options: .caseInsensitive)
    }
}
#endif

@MainActor
final class PlaceSearchModel: ObservableObject {
    enum Phase: Equatable {
        case hint
        case suggesting
        case results(title: String)
        case noResults
        case failed(String)
    }

    @Published var query = "" {
        didSet { if query != oldValue { queryDidChange() } }
    }
    @Published private(set) var phase = Phase.hint
    @Published private(set) var suggestions: [PlaceSuggestion] = []
    @Published private(set) var results: [PlaceChoice] = []
    @Published private(set) var isBusy = false

    let origin: CLLocationCoordinate2D?
    private let service: any PlaceSearchService
    private var generation = 0
    private var suggestionsAnswered = false

    init(service: any PlaceSearchService, origin: CLLocationCoordinate2D?) {
        self.service = service
        self.origin = origin
        service.onSuggestions = { [weak self] fragment, suggestions in self?.received(suggestions, for: fragment) }
        service.onFailure = { [weak self] fragment, message in self?.failedSuggesting(message, for: fragment) }
    }

    var showsNoSuggestions: Bool { phase == .suggesting && suggestions.isEmpty && suggestionsAnswered }

    /// Resolves a tapped suggestion. Returns the place when it is unambiguous; otherwise lists the matches to choose from.
    func select(_ suggestion: PlaceSuggestion) async -> PlaceChoice? {
        guard !isBusy else { return nil }
        guard let found = await run({ try await service.resolve(suggestion, near: origin) }) else { return nil }
        if found.count == 1 { return found[0] }
        show(found, title: "Results for “\(suggestion.plainTitle)”")
        return nil
    }

    /// Full search for the typed text, for when no suggestion fits.
    func submit() async {
        let text = trimmedQuery
        guard !text.isEmpty, !isBusy else { return }
        guard let found = await run({ try await service.search(text, near: origin) }) else { return }
        show(found, title: "Results for “\(text)”")
    }

    func distance(to place: PlaceChoice) -> String? {
        origin.map { RideUnits.distance(place.distance(fromLatitude: $0.latitude, longitude: $0.longitude)) }
    }

    nonisolated static func message(for error: any Error) -> String {
        let nsError = error as NSError
        let unreachable: Set<Int> = [Int(MKError.Code.serverFailure.rawValue), Int(MKError.Code.loadingThrottled.rawValue)]
        if nsError.domain == NSURLErrorDomain || (nsError.domain == MKError.errorDomain && unreachable.contains(nsError.code)) {
            return "Can't reach Apple Maps. Check your connection and try again."
        }
        return "Search failed: \(error.localizedDescription)"
    }

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func queryDidChange() {
        generation += 1
        isBusy = false
        results = []
        suggestionsAnswered = false
        let fragment = trimmedQuery
        if fragment.isEmpty {
            suggestions = []
            phase = .hint
        } else {
            phase = .suggesting
        }
        service.suggest(fragment, near: origin)
    }

    private func received(_ new: [PlaceSuggestion], for fragment: String) {
        guard fragment == trimmedQuery, phase == .suggesting else { return }
        suggestions = new
        suggestionsAnswered = true
    }

    private func failedSuggesting(_ message: String, for fragment: String) {
        guard fragment == trimmedQuery, phase == .suggesting else { return }
        phase = .failed(message)
    }

    private func show(_ found: [PlaceChoice], title: String) {
        results = found
        phase = found.isEmpty ? .noResults : .results(title: title)
    }

    /// Runs one lookup. Returns nil when it failed or the rider kept typing, so late answers never replace newer ones.
    private func run(_ operation: () async throws -> [PlaceChoice]) async -> [PlaceChoice]? {
        let token = generation
        isBusy = true
        defer { if token == generation { isBusy = false } }
        do {
            let found = try await operation()
            return token == generation ? found : nil
        } catch {
            guard token == generation else { return nil }
            if (error as? MKError)?.code == .placemarkNotFound { return [] }
            phase = .failed(Self.message(for: error))
            return nil
        }
    }
}

struct PlacePicker: View {
    @StateObject private var model: PlaceSearchModel
    @Environment(\.dismiss) private var dismiss
    @State private var searchPresented = false
    private let dismissesOnPick: Bool
    private let onPick: (PlaceChoice) -> Void

    init(near origin: CLLocationCoordinate2D?, dismissesOnPick: Bool = true, onPick: @escaping (PlaceChoice) -> Void) {
        _model = StateObject(wrappedValue: PlaceSearchModel(service: PlaceSearchServices.make(), origin: origin))
        self.dismissesOnPick = dismissesOnPick
        self.onPick = onPick
    }

    var body: some View {
        List {
            if case .results(let title) = model.phase {
                Section {
                    ForEach(model.results) { place in resultRow(place) }
                } header: {
                    Text(title).foregroundStyle(RideTheme.secondaryText)
                }
            } else if model.phase == .suggesting, !model.suggestions.isEmpty {
                Section {
                    ForEach(model.suggestions) { suggestion in suggestionRow(suggestion) }
                }
            }
        }
        .rideSurface()
        .overlay { placeholder }
        .overlay {
            if model.isBusy { ProgressView("Searching...").padding().background(.regularMaterial, in: .rect(cornerRadius: 12)) }
        }
        .navigationTitle("Choose a place")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        #endif
        #if os(iOS)
        // Inside a tab, an active search can outlive this pushed page; keep it in the page's navigation bar and end it on pick.
        .searchable(text: $model.query, isPresented: $searchPresented,
                    placement: .navigationBarDrawer(displayMode: .always), prompt: "Address or place")
        .onDisappear { searchPresented = false }
        #else
        .searchable(text: $model.query, prompt: "Address or place")
        #endif
        .autocorrectionDisabled()
        .onSubmit(of: .search) { Task { await model.submit() } }
    }

    @ViewBuilder private var placeholder: some View {
        switch model.phase {
        case .hint:
            ContentUnavailableView("Find a place", systemImage: "magnifyingglass",
                                   description: Text("Search for an address, business or landmark. Suggestions appear as you type."))
        case .noResults:
            ContentUnavailableView.search(text: model.query)
        case .failed(let message):
            ContentUnavailableView {
                Label("Search unavailable", systemImage: "exclamationmark.magnifyingglass")
            } description: {
                Text(message)
            } actions: {
                Button("Try again") { Task { await model.submit() } }
            }
        case .suggesting:
            if model.showsNoSuggestions { ContentUnavailableView.search(text: model.query) }
        case .results:
            EmptyView()
        }
    }

    private func suggestionRow(_ suggestion: PlaceSuggestion) -> some View {
        Button {
            Task { if let place = await model.select(suggestion) { finish(place) } }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(suggestion.title).foregroundStyle(Color.primary)
                if !suggestion.plainSubtitle.isEmpty {
                    Text(suggestion.subtitle).font(.subheadline).foregroundStyle(RideTheme.secondaryText)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .disabled(model.isBusy)
        .accessibilityIdentifier("placeSuggestion")
    }

    private func resultRow(_ place: PlaceChoice) -> some View {
        Button {
            finish(place)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(place.name).foregroundStyle(Color.primary)
                    if !place.detail.isEmpty {
                        Text(place.detail).font(.subheadline).foregroundStyle(RideTheme.secondaryText)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if let distance = model.distance(to: place) {
                    Text(distance).font(.subheadline).foregroundStyle(RideTheme.secondaryText)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .accessibilityIdentifier("placeResult")
    }

    private func finish(_ place: PlaceChoice) {
        searchPresented = false
        onPick(place)
        if dismissesOnPick { dismiss() }
    }
}
