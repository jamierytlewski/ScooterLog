import CloudKit
import Combine
import ScooterCore
import SwiftUI

enum CloudRideError: LocalizedError {
    case configuration, account, invalidRide, simulator

    var errorDescription: String? {
        switch self {
        case .configuration: "Configure the private CloudKit container in Xcode before syncing."
        case .account: "iCloud is unavailable. Sign in, check iCloud access and try again. Local rides are unaffected."
        case .invalidRide: "iCloud returned invalid ride/place data. Local originals are preserved."
        case .simulator: "CloudKit sync is disabled in this simulator starter. Use a provisioned, signed-in device with a matching CloudKit container."
        }
    }
}

@MainActor
final class CloudRideSync: ObservableObject {
    @Published private(set) var enabled = UserDefaults.standard.bool(forKey: "privateRideSyncEnabled")
    @Published private(set) var busy = false
    @Published private(set) var status = "Optional private iCloud sync. No Health data is uploaded."
    private let recordType = "CompletedRide"

    func setEnabled(_ enabled: Bool) {
        self.enabled = enabled
        UserDefaults.standard.set(enabled, forKey: "privateRideSyncEnabled")
        status = enabled ? "Enabled. Tap Sync now to sync completed routes and saved places."
            : "Sync off. Existing iCloud records are retained; local rides remain on this device."
    }

    private func database() async throws -> CKDatabase {
        #if targetEnvironment(simulator)
        throw CloudRideError.simulator
        #else
        guard let identifier = Bundle.main.object(forInfoDictionaryKey: "ScooterCloudContainer") as? String,
              identifier.hasPrefix("iCloud.") else { throw CloudRideError.configuration }
        let container = CKContainer(identifier: identifier)
        guard try await container.accountStatus() == .available else { throw CloudRideError.account }
        return container.privateCloudDatabase
        #endif
    }

    func sync(with controller: RideController) async {
        guard enabled, !busy else { return }
        busy = true
        defer { busy = false }
        do {
            let database = try await database()
            try await syncPlaces(database: database, controller: controller)
            let uploadDirectory = URL.cachesDirectory.appendingPathComponent("CloudRideUploads")
            try FileManager.default.createDirectory(at: uploadDirectory, withIntermediateDirectories: true)
            let rides = controller.archive.completed
            for ride in rides {
                try checkEnabled()
                let id = CKRecord.ID(recordName: ride.id.uuidString)
                let record: CKRecord
                do { record = try await database.record(for: id) }
                catch let error as CKError where error.code == .unknownItem {
                    record = CKRecord(recordType: recordType, recordID: id)
                }
                try checkEnabled()
                let url = uploadDirectory.appendingPathComponent("\(ride.id.uuidString).json")
                try JSONEncoder().encode(ride).write(to: url, options: .atomic)
                do {
                    record["route"] = CKAsset(fileURL: url)
                    record["startedAt"] = ride.startedAt
                    record["schemaVersion"] = 1
                    _ = try await database.save(record)
                } catch {
                    // This is a regenerable upload copy, never the canonical local ride.
                    do { try FileManager.default.removeItem(at: url) }
                    catch { controller.report("Could not remove temporary iCloud upload: \(error.localizedDescription)") }
                    throw error
                }
                try FileManager.default.removeItem(at: url)
            }
            try checkEnabled()
            var page = try await database.records(matching: CKQuery(recordType: recordType, predicate: NSPredicate(value: true)),
                                                   resultsLimit: 100)
            var downloaded = 0
            while true {
                for (id, result) in page.matchResults {
                    try checkEnabled()
                    let record = try result.get()
                    guard let version = record["schemaVersion"] as? Int, version == 1,
                          let asset = record["route"] as? CKAsset, let url = asset.fileURL else {
                        throw CloudRideError.invalidRide
                    }
                    let ride = try JSONDecoder().decode(Ride.self, from: Data(contentsOf: url))
                    guard ride.endedAt != nil, ride.id.uuidString == id.recordName else { throw CloudRideError.invalidRide }
                    try controller.importCloudCompleted(ride)
                    downloaded += 1
                }
                guard let cursor = page.queryCursor else { break }
                page = try await database.records(continuingMatchFrom: cursor, resultsLimit: 100)
            }
            status = "Synced \(rides.count) local and \(downloaded) private iCloud rides plus \(controller.places.visible.count) saved places. Last sync \(Date.now.formatted(date: .omitted, time: .shortened))."
        } catch is CancellationError {
            status = "Sync stopped. Any already uploaded rides remain in your private iCloud database."
        } catch {
            status = "Sync failed: \(error.localizedDescription). Local rides are safe. Check account/container/network and retry."
        }
    }

    func deleteCloudRides() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            let database = try await database()
            var ids: [CKRecord.ID] = []
            for type in [recordType, "SavedPlace"] {
                var page = try await database.records(matching: CKQuery(recordType: type, predicate: NSPredicate(value: true)),
                                                       desiredKeys: [], resultsLimit: 100)
                while true {
                    for (id, result) in page.matchResults {
                        _ = try result.get()
                        ids.append(id)
                    }
                    guard let cursor = page.queryCursor else { break }
                    page = try await database.records(continuingMatchFrom: cursor, desiredKeys: [], resultsLimit: 100)
                }
            }
            for id in ids { _ = try await database.deleteRecord(withID: id) }
            setEnabled(false)
            status = "Deleted \(ids.count) private iCloud ride/place records. Local data is unchanged; sync is now off."
        } catch {
            status = "iCloud deletion incomplete: \(error.localizedDescription). Retry to delete remaining records."
        }
    }

    private func checkEnabled() throws {
        try Task.checkCancellation()
        guard enabled else { throw CancellationError() }
    }

    private func syncPlaces(database: CKDatabase, controller: RideController) async throws {
        try checkEnabled()
        var page = try await database.records(matching: CKQuery(recordType: "SavedPlace", predicate: NSPredicate(value: true)),
                                               resultsLimit: 100)
        while true {
            for (id, result) in page.matchResults {
                try checkEnabled()
                let record = try result.get()
                guard let data = record["place"] as? Data else { throw CloudRideError.invalidRide }
                let place = try JSONDecoder().decode(SavedPlace.self, from: data)
                guard id.recordName == "place-\(place.id.uuidString)" else { throw CloudRideError.invalidRide }
                try controller.mergePlaces([place])
            }
            guard let cursor = page.queryCursor else { break }
            page = try await database.records(continuingMatchFrom: cursor, resultsLimit: 100)
        }
        for place in controller.places.records {
            try checkEnabled()
            let id = CKRecord.ID(recordName: "place-\(place.id.uuidString)")
            var record: CKRecord
            do {
                record = try await database.record(for: id)
                guard let data = record["place"] as? Data else { throw CloudRideError.invalidRide }
                let remote = try JSONDecoder().decode(SavedPlace.self, from: data)
                guard remote.id == place.id else { throw CloudRideError.invalidRide }
                try controller.mergePlaces([remote])
            } catch let error as CKError where error.code == .unknownItem {
                record = CKRecord(recordType: "SavedPlace", recordID: id)
            }
            try checkEnabled()
            guard let merged = controller.places.records.first(where: { $0.id == place.id }) else { throw CloudRideError.invalidRide }
            record["place"] = try JSONEncoder().encode(merged)
            _ = try await database.save(record)
        }
    }
}

struct CloudSyncView: View {
    @ObservedObject var controller: RideController
    @StateObject private var cloud = CloudRideSync()
    @State private var confirmDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Private iCloud sync").font(.headline)
            Toggle("Sync rides and saved places", isOn: Binding(get: { cloud.enabled }, set: cloud.setEnabled))
            Text("Opt-in: uploads completed GPS routes/timing and saved-place names/coordinates (including deletion markers) to your private CloudKit database. No heart-rate samples. Active recording stays local.")
                .font(.caption)
            Text(cloud.status).font(.caption)
            Button(cloud.busy ? "Working..." : "Sync now") { Task { await cloud.sync(with: controller) } }
                .disabled(!cloud.enabled || cloud.busy)
            Button("Delete private iCloud data", role: .destructive) { confirmDelete = true }
                .disabled(cloud.busy)
        }
        .confirmationDialog("Delete all ScooterLog rides and places from your private iCloud database?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete iCloud data", role: .destructive) { Task { await cloud.deleteCloudRides() } }
        } message: {
            Text("Local and companion copies are not deleted. Sync will turn off after successful deletion; enabling it again can re-upload local history.")
        }
    }
}
