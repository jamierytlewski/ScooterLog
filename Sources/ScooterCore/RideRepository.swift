import Foundation

/// Separate active checkpoints from immutable completed routes to bound per-fix writes.
public struct RideRepository: Sendable {
    public let directory: URL
    private var activeURL: URL { directory.appendingPathComponent("active.json") }
    private var historyURL: URL { directory.appendingPathComponent("History") }
    private var deletedURL: URL { directory.appendingPathComponent("deleted-rides.json") }

    public init(directory: URL) { self.directory = directory }

    public func load() throws -> RideArchive {
        var archive = try RideDisk.load(from: activeURL)
        archive.deleted = try loadDeleted()
        if FileManager.default.fileExists(atPath: historyURL.path) {
            for url in try FileManager.default.contentsOfDirectory(at: historyURL, includingPropertiesForKeys: nil)
                where url.pathExtension == "json" {
                // An interrupted delete leaves the file behind; finish it. The tombstone already hides
                // the ride, so a failed purge is harmless and is retried on the next load.
                if let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent), archive.isDeleted(id) {
                    try? FileManager.default.removeItem(at: url)
                    continue
                }
                archive.importCompleted(try JSONDecoder().decode(Ride.self, from: Data(contentsOf: url)))
            }
        }
        // A crash between saving the completed route and clearing the checkpoint is recoverable.
        if let active = archive.active,
           archive.completed.contains(where: { $0.id == active.id }) || archive.isDeleted(active.id) {
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

    /// Durably records deletions in one atomic write. Do this before `removeCompleted`: a crash in
    /// between leaves only files that the next `load()` purges, never a deletion that comes back.
    public func saveDeleted(_ ids: Set<UUID>) throws {
        let merged = try loadDeleted().union(ids)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(merged).write(to: deletedURL, options: .atomic)
    }

    /// Removes saved ride files, attempting every id even if one fails, then reports the first failure.
    public func removeCompleted(_ ids: Set<UUID>) throws {
        var firstError: Error?
        for id in ids {
            let url = historyURL.appendingPathComponent("\(id.uuidString).json")
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            do { try FileManager.default.removeItem(at: url) }
            catch { firstError = firstError ?? error }
        }
        if let firstError { throw firstError }
    }

    private func loadDeleted() throws -> Set<UUID> {
        guard FileManager.default.fileExists(atPath: deletedURL.path) else { return [] }
        return try JSONDecoder().decode(Set<UUID>.self, from: Data(contentsOf: deletedURL))
    }
}
