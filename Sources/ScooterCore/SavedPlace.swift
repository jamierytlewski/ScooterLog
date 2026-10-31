import Foundation

public struct SavedPlace: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var latitude: Double
    public var longitude: Double
    public var modifiedAt: Date
    public var deleted: Bool

    public init(id: UUID = UUID(), name: String, latitude: Double, longitude: Double,
                modifiedAt: Date = .now, deleted: Bool = false) {
        self.id = id
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.modifiedAt = modifiedAt
        self.deleted = deleted
    }

    public var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && name.count <= 100
            && latitude.isFinite && longitude.isFinite && abs(latitude) <= 90 && abs(longitude) <= 180
    }

    fileprivate func preferred(over other: SavedPlace) -> Bool {
        if modifiedAt != other.modifiedAt { return modifiedAt > other.modifiedAt }
        if deleted != other.deleted { return deleted }
        // Deterministic convergence if two devices edit within the same timestamp.
        return "\(name)|\(latitude)|\(longitude)" > "\(other.name)|\(other.latitude)|\(other.longitude)"
    }
}

public struct SavedPlaces: Codable, Equatable, Sendable {
    public private(set) var records: [SavedPlace] = []
    public var visible: [SavedPlace] {
        records.filter { !$0.deleted }.sorted {
            $0.name == $1.name ? $0.id.uuidString < $1.id.uuidString : $0.name < $1.name
        }
    }

    public init() {}

    public mutating func merge(_ places: [SavedPlace]) throws {
        guard places.allSatisfy(\.isValid) else { throw CocoaError(.fileReadCorruptFile) }
        var merged = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
        for place in places {
            if let old = merged[place.id], !place.preferred(over: old) { continue }
            merged[place.id] = place
        }
        records = merged.values.sorted { $0.id.uuidString < $1.id.uuidString }
    }

    public mutating func delete(id: UUID, at date: Date = .now) throws {
        guard var place = records.first(where: { $0.id == id }) else { return }
        place.deleted = true
        place.modifiedAt = max(date, place.modifiedAt)
        try merge([place])
    }

    public static func load(from url: URL) throws -> SavedPlaces {
        guard FileManager.default.fileExists(atPath: url.path) else { return SavedPlaces() }
        let decoded = try JSONDecoder().decode(SavedPlaces.self, from: Data(contentsOf: url))
        var validated = SavedPlaces()
        try validated.merge(decoded.records)
        return validated
    }

    public func save(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
    }
}
