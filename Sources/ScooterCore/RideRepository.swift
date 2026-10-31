import Foundation

/// Separate active checkpoints from immutable completed routes to bound per-fix writes.
public struct RideRepository: Sendable {
    public let directory: URL
    private var activeURL: URL { directory.appendingPathComponent("active.json") }
    private var historyURL: URL { directory.appendingPathComponent("History") }

    public init(directory: URL) { self.directory = directory }

    public func load() throws -> RideArchive {
        var archive = try RideDisk.load(from: activeURL)
        if FileManager.default.fileExists(atPath: historyURL.path) {
            for url in try FileManager.default.contentsOfDirectory(at: historyURL, includingPropertiesForKeys: nil)
                where url.pathExtension == "json" {
                archive.importCompleted(try JSONDecoder().decode(Ride.self, from: Data(contentsOf: url)))
            }
        }
        // A crash between saving the completed route and clearing the checkpoint is recoverable.
        if let active = archive.active, archive.completed.contains(where: { $0.id == active.id }) {
            archive.active = nil
        }
        if archive.active?.stationarySince != nil {
            archive.active?.interrupt(at: .now)
        }
        return archive
    }

    public func checkpoint(_ active: Ride?) throws {
        try RideDisk.save(RideArchive(active: active), to: activeURL)
    }

    public func saveCompleted(_ ride: Ride) throws {
        guard ride.endedAt != nil else { return }
        try FileManager.default.createDirectory(at: historyURL, withIntermediateDirectories: true)
        try JSONEncoder().encode(ride).write(to: historyURL.appendingPathComponent("\(ride.id.uuidString).json"), options: .atomic)
    }
}
