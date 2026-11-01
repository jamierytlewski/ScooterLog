import Foundation

/// A place the rider explicitly picked from search. It is independent of MapKit so unusable results
/// can be rejected in one place and the value can cross actors.
public struct PlaceChoice: Equatable, Hashable, Identifiable, Sendable {
    public static let maxSavedNameLength = 100

    public let name: String
    public let address: String
    public let latitude: Double
    public let longitude: Double

    public var id: String { "\(latitude),\(longitude)|\(name)" }

    /// Returns nil when the result has no label or no usable coordinate, so it can never be routed to or saved.
    public init?(name: String?, address: String? = nil, latitude: Double, longitude: Double) {
        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let trimmedAddress = address?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard latitude.isFinite, longitude.isFinite, abs(latitude) <= 90, abs(longitude) <= 180 else { return nil }
        guard let label = [trimmedName, trimmedAddress].first(where: { !$0.isEmpty }) else { return nil }
        self.name = label
        self.address = trimmedAddress
        self.latitude = latitude
        self.longitude = longitude
    }

    public init?(_ place: SavedPlace) {
        self.init(name: place.name, latitude: place.latitude, longitude: place.longitude)
    }

    /// The address without a leading repeat of the name, e.g. "Springfield, IL" for "1 Main St, Springfield, IL".
    public var detail: String {
        guard let prefix = address.range(of: name, options: [.anchored, .caseInsensitive]) else { return address }
        let rest = address[prefix.upperBound...]
        guard let first = rest.first else { return "" }
        guard first == "," || first.isWhitespace else { return address }
        return String(rest.drop { $0 == "," || $0.isWhitespace })
    }

    /// A default for the saved-place name field that already satisfies the length limit.
    public var suggestedSavedName: String { String(name.prefix(Self.maxSavedNameLength)) }

    public func distance(fromLatitude latitude: Double, longitude: Double) -> Double {
        let origin = LocationSample(latitude: latitude, longitude: longitude, timestamp: .distantPast, accuracy: 0, speed: 0)
        let place = LocationSample(latitude: self.latitude, longitude: self.longitude, timestamp: .distantPast, accuracy: 0, speed: 0)
        return origin.distance(to: place)
    }
}
