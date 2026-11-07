import Combine
import CoreLocation
import Foundation
import OSLog
import ScooterCore
import WatchConnectivity
#if os(iOS)
import UIKit
#else
import WatchKit
#endif

enum RideFailure: LocalizedError {
    case foreground, permission, remoteRide, noRide, storage, unreachable

    var errorDescription: String? {
        switch self {
        case .foreground: "Open ScooterLog on this device to start location recording."
        case .permission: "Allow location access in Settings, then return to ScooterLog and start again."
        case .remoteRide: "The other device owns this ride. End it there or use the connected End button."
        case .noRide: "There is no active ride on this device."
        case .storage: "Ride storage is unavailable. Resolve the storage error before recording."
        case .unreachable: "The recording device is unreachable. The ride has not been ended."
        }
    }
}

@MainActor
final class RideController: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    static let shared = RideController()

    @Published private(set) var archive = RideArchive()
    @Published private(set) var recording = false
    @Published private(set) var peer: PeerSnapshot?
    @Published private(set) var reachable = false
    @Published private(set) var commandPending = false
    @Published private(set) var places = SavedPlaces()
    @Published var errorMessage: String?
    @Published private(set) var locationStatus = "Location permission is required."
    @Published private(set) var locationAuthorization: CLAuthorizationStatus = .notDetermined
    #if os(iOS)
    let owner = "iPhone"
    #else
    let owner = "Apple Watch"
    #endif
    private let manager = CLLocationManager()
    private let logger = Logger(subsystem: "com.scooterlog.app", category: "Recording")
    let directions = DirectionsModel()
    private var serviceSession: CLServiceSession?
    private var backgroundSession: CLBackgroundActivitySession?
    private var updatesTask: Task<Void, Never>?
    private var storageAvailable = true
    private var placesAvailable = true
    private var lastBroadcast = Date.distantPast
    private let storeURL: URL
    private var connectivity: WCSession?
    private var commandTimeout: Task<Void, Never>?
    #if os(iOS)
    private let liveActivity = LiveActivityManager()
    #endif

    var displayedRide: Ride? { archive.active ?? peer?.ride }
    var isRemote: Bool { archive.active == nil && peer?.ride != nil }
    var displayedGuidance: RideGuidance? {
        if let active = archive.active, directions.guidance?.rideID == active.id { return directions.guidance }
        return isRemote ? peer?.activeGuidance : nil
    }

    /// Where the rider last recorded a location. Place searches are centred here so nearby results rank first.
    var lastKnownCoordinate: CLLocationCoordinate2D? {
        let sample = displayedRide?.samples.last ?? archive.completed.lazy.compactMap { $0.samples.last }.first
        return sample.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
    }

    private override init() {
        storeURL = URL.applicationSupportDirectory.appendingPathComponent("ScooterLog/rides.json")
        super.init()
        do {
            archive = try RideRepository(directory: storeURL.deletingLastPathComponent()).load()
        } catch {
            storageAvailable = false
            errorMessage = "Could not read saved rides; the file has not been overwritten: \(error.localizedDescription)"
        }
        do {
            places = try SavedPlaces.load(from: placesURL)
        } catch {
            placesAvailable = false
            errorMessage = "Could not read saved places; original data is preserved: \(error.localizedDescription)"
        }
        manager.delegate = self
        refreshAuthorization()
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ScooterLogStubHistory"),
           let fixedID = UUID(uuidString: "7BACBC77-836C-4C1D-83BF-D3471E226EEF") {
            // A delete test may have tombstoned the fixed stub, which would block re-importing it.
            let id = archive.isDeleted(fixedID) ? UUID() : fixedID
            var ride = Ride(id: id,
                            owner: "Export preview", startedAt: Date.now.addingTimeInterval(-120))
            for (index, speed) in [2.0, 3.0, 4.0, 5.0, 7.0].enumerated() {
                let time = ride.startedAt.addingTimeInterval(Double(index * 5))
                _ = ride.append(LocationSample(latitude: 40.7527 + Double(index) * 0.0001,
                                               longitude: -73.9772, timestamp: time, accuracy: 5, speed: speed),
                                receivedAt: time)
            }
            ride.end(at: ride.startedAt.addingTimeInterval(25))
            perform {
                var next = archive
                next.importCompleted(ride)
                try persist(next)
            }
        }
        #endif
        directions.onGuidanceChange = { [weak self] in self?.broadcast() }
        if archive.shouldResumeRecording(on: owner), authorized {
            archive.active?.interrupt(at: .now)
            do {
                try persist(archive)
                beginUpdates()
                logger.notice("Resumed the previously requested recording session after launch.")
                #if os(iOS)
                if let ride = archive.active { liveActivity.start(ride, onError: report) }
                #endif
            } catch { report("Could not resume recording: \(error.localizedDescription). Resume or end the saved ride.") }
        }
        if WCSession.isSupported() {
            let session = WCSession.default
            connectivity = session
            session.delegate = self
            session.activate()
        }
    }

    func requestLocationPermission() {
        manager.requestWhenInUseAuthorization()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        refreshAuthorization()
        if recording && !authorized {
            stopUpdates()
            errorMessage = "Location access was removed. Ride timing remains open; resume or end it in ScooterLog."
            broadcast()
        }
    }

    private var authorized: Bool {
        manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways
    }

    private func refreshAuthorization() {
        locationAuthorization = manager.authorizationStatus
        switch locationAuthorization {
        case .authorizedAlways, .authorizedWhenInUse: locationStatus = "Location access ready"
        case .denied: locationStatus = "Location access denied. Enable it in Settings."
        case .restricted: locationStatus = "Location access is restricted by this device's settings."
        case .notDetermined: locationStatus = "Allow location before your first ride."
        @unknown default: locationStatus = "Location authorization is unavailable."
        }
    }

    func waitForForeground() async {
        for _ in 0..<60 {
            #if os(iOS)
            if UIApplication.shared.applicationState == .active { return }
            #else
            if WKApplication.shared().applicationState == .active { return }
            #endif
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    private func requireForeground() throws {
        #if os(iOS)
        guard UIApplication.shared.applicationState == .active else { throw RideFailure.foreground }
        #else
        guard WKApplication.shared().applicationState == .active else { throw RideFailure.foreground }
        #endif
    }

    func start() throws {
        try requireForeground()
        guard storageAvailable else { throw RideFailure.storage }
        guard authorized else {
            if manager.authorizationStatus == .notDetermined { requestLocationPermission() }
            throw RideFailure.permission
        }
        guard peer?.ride == nil || archive.active != nil else { throw RideFailure.remoteRide }
        if recording { return }
        var next = archive
        next.active?.interrupt(at: .now)
        _ = next.start(owner: owner, at: .now)
        next.recordingRequested = true
        try persist(next)
        beginUpdates()
        logger.notice("Started location recording on the owning device.")
        broadcast()
        #if os(iOS)
        if let ride = archive.active { liveActivity.start(ride, onError: report) }
        #endif
    }

    func end() throws {
        guard archive.active != nil else { throw RideFailure.noRide }
        var next = archive
        guard let completed = next.finish(at: .now) else { throw RideFailure.noRide }
        let repository = RideRepository(directory: storeURL.deletingLastPathComponent())
        // A durable completed route is the end boundary, even if checkpoint cleanup fails.
        try repository.saveCompleted(completed)
        stopUpdates(preserveCheckpoint: false)
        archive = next
        directions.stopGuidance()
        logger.notice("Ended and saved the local ride after an explicit end request.")
        do { try repository.checkpoint(nil) }
        catch { report("Ride saved and recording ended. Old checkpoint cleanup failed; recovery will prefer the saved ride: \(error.localizedDescription)") }
        broadcast()
        queueCompleted(completed)
        #if os(iOS)
        liveActivity.end(completed)
        #endif
    }

    func retrySave() {
        do {
            guard storageAvailable else { throw RideFailure.storage }
            try persist(archive)
        } catch { report(error.localizedDescription) }
    }

    func resendHistory() {
        for ride in archive.completed { queueCompleted(ride) }
    }

    func refreshConnection() {
        broadcast()
        flushOutbox()
        guard let session = companionSession, session.isReachable else { return }
        session.sendMessage(["requestSnapshot": true], replyHandler: { @Sendable reply in
            let snapshot = reply["snapshot"] as? Data
            let places = reply["places"] as? Data
            let error = reply["error"] as? String
            Task { @MainActor in
                if let snapshot { self.receiveSnapshot(snapshot) }
                if let places { self.receivePlaces(places) }
                if let error { self.report("Could not refresh companion: \(error)") }
            }
        }, errorHandler: { @Sendable error in
            let message = error.localizedDescription
            Task { @MainActor in self.report("Could not refresh companion: \(message)") }
        })
    }

    func refreshLiveActivityAppearance() {
        #if os(iOS)
        if let ride = archive.active { liveActivity.update(ride) }
        #endif
    }

    func forgetStalePeer() {
        guard !reachable, peer != nil else { return }
        self.peer = nil
    }

    func importCloudCompleted(_ ride: Ride) throws {
        guard storageAvailable else { throw RideFailure.storage }
        guard ride.endedAt != nil else { throw CocoaError(.fileReadCorruptFile) }
        var next = archive
        next.importCompleted(ride)
        try persist(next)
    }

    /// Permanently deletes completed rides here and, unless the request came from the companion,
    /// tells the paired device. Nothing changes if the deletion cannot be saved.
    func deleteRides(_ ids: Set<UUID>, propagate: Bool = true) throws {
        guard storageAvailable else { throw RideFailure.storage }
        var next = archive
        let removed = next.delete(ids)
        guard !removed.isEmpty else { return }
        let repository = RideRepository(directory: storeURL.deletingLastPathComponent())
        // The saved deletion is the durable boundary; leftover ride files are purged on the next launch.
        try repository.saveDeleted(removed)
        archive = next
        do { try repository.removeCompleted(removed) }
        catch { report("Removed from History, but a ride file could not be deleted. It stays hidden and is cleaned up on the next launch: \(error.localizedDescription)") }
        discardQueuedTransfers(of: removed)
        if propagate { notifyCompanion(deleted: removed) }
    }

    private var placesURL: URL { storeURL.deletingLastPathComponent().appendingPathComponent("places.json") }

    func mergePlaces(_ records: [SavedPlace]) throws {
        guard placesAvailable else { throw RideFailure.storage }
        var next = places
        try next.merge(records)
        guard next != places else { return }
        try next.save(to: placesURL)
        places = next
        broadcast()
    }

    func savePlace(_ place: SavedPlace) throws {
        guard place.isValid else {
            throw NSError(domain: "ScooterLog", code: 1, userInfo: [NSLocalizedDescriptionKey: "Use a nonempty name up to 100 characters and a valid map location."])
        }
        try mergePlaces([place])
    }

    func deletePlace(_ id: UUID) throws {
        var next = places
        try next.delete(id: id)
        try mergePlaces(next.records)
    }

    func perform(_ action: () throws -> Void) {
        do { try action() } catch { report(error.localizedDescription) }
    }

    func report(_ message: String) {
        logger.error("\(message)")
        errorMessage = message
    }

    private func persist(_ next: RideArchive) throws {
        let repository = RideRepository(directory: storeURL.deletingLastPathComponent())
        let existing = Dictionary(uniqueKeysWithValues: archive.completed.map { ($0.id, $0) })
        for ride in next.completed where existing[ride.id] != ride {
            try repository.saveCompleted(ride)
        }
        try repository.checkpoint(next.active, recordingRequested: next.recordingRequested)
        archive = next
    }

    private func beginUpdates() {
        guard !recording else { return }
        serviceSession = CLServiceSession(authorization: .whenInUse)
        backgroundSession = CLBackgroundActivitySession()
        recording = true
        updatesTask = Task { [weak self] in
            do {
                for try await update in CLLocationUpdate.liveUpdates(.otherNavigation) {
                    guard let self, !Task.isCancelled else { break }
                    if update.authorizationDenied || update.authorizationDeniedGlobally || update.authorizationRestricted {
                        self.stopUpdates()
                        self.report("Location authorization was denied; recording is paused.")
                        self.broadcast()
                        break
                    }
                    if update.insufficientlyInUse || update.serviceSessionRequired {
                        self.locationStatus = "Background GPS is unavailable. Reopen ScooterLog on the recording device."
                        self.report(self.locationStatus)
                        continue
                    }
                    if update.locationUnavailable {
                        self.updateStationarity(confirmed: false)
                        self.locationStatus = "Location unavailable. Unconfirmed time remains unknown."
                        continue
                    }
                    if !update.stationary, self.archive.active?.stationarySince != nil {
                        self.updateStationarity(confirmed: false)
                        guard self.recording else { break }
                    }
                    if let location = update.location { self.accept(location) }
                    guard self.recording else { break }
                    if update.stationary {
                        self.updateStationarity(confirmed: true)
                    } else if update.location == nil {
                        self.updateStationarity(confirmed: false)
                        self.locationStatus = "Location unavailable. Unconfirmed time remains unknown."
                    }
                }
                guard let self, !Task.isCancelled, self.recording else { return }
                self.stopUpdates()
                self.report("The GPS update stream ended unexpectedly. Resume or end this ride; its saved route is preserved.")
                self.broadcast()
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.stopUpdates()
                self.report("Location updates stopped: \(error.localizedDescription). Resume or end this ride.")
                self.broadcast()
            }
        }
    }

    private func stopUpdates(preserveCheckpoint: Bool = true) {
        #if os(watchOS)
        HealthReader.shared.stopLiveSession()
        #endif
        updatesTask?.cancel()
        updatesTask = nil
        backgroundSession?.invalidate()
        backgroundSession = nil
        serviceSession?.invalidate()
        serviceSession = nil
        recording = false
        archive.recordingRequested = false
        if preserveCheckpoint, var ride = archive.active {
            ride.finishStationary(at: .now)
            ride.interrupt(at: .now)
            archive.active = ride
            do { try RideRepository(directory: storeURL.deletingLastPathComponent()).checkpoint(ride, recordingRequested: false) }
            catch { report("Recording stopped, but the latest timing checkpoint could not be saved: \(error.localizedDescription)") }
        }
    }

    private func updateStationarity(confirmed: Bool) {
        guard var ride = archive.active else { return }
        if confirmed {
            ride.confirmStationary(at: .now)
            locationStatus = "Core Location confirmed stationary; stopped time continues during its automatic pause."
        } else {
            ride.finishStationary(at: .now)
            ride.interrupt(at: .now)
        }
        do {
            try RideRepository(directory: storeURL.deletingLastPathComponent()).checkpoint(ride, recordingRequested: recording)
            archive.active = ride
            broadcast()
            #if os(iOS)
            liveActivity.update(ride)
            #endif
        } catch {
            stopUpdates()
            report("Stationary timing could not be saved; recording stopped: \(error.localizedDescription)")
        }
    }

    private func accept(_ location: CLLocation) {
        guard recording, var ride = archive.active else { return }
        let sample = LocationSample(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude,
                                    timestamp: location.timestamp, accuracy: location.horizontalAccuracy, speed: location.speed)
        guard ride.append(sample, receivedAt: .now) else {
            locationStatus = "GPS fix rejected: waiting for a recent, accurate location. Unconfirmed time stays unknown."
            return
        }
        locationStatus = "GPS recording on \(owner)"
        var next = archive
        next.active = ride
        do {
            try RideRepository(directory: storeURL.deletingLastPathComponent()).checkpoint(ride, recordingRequested: recording)
            archive = next
        } catch {
            stopUpdates()
            report("Recording paused because the route could not be saved: \(error.localizedDescription)")
            broadcast()
            return
        }
        directions.updateGuidance(from: sample)
        if Date.now.timeIntervalSince(lastBroadcast) >= 5 {
            broadcast()
            #if os(iOS)
            liveActivity.update(ride)
            #endif
        }
    }

    func endRemote() {
        guard let ride = peer?.ride else { return }
        guard let session = connectivity, session.isReachable else {
            report(RideFailure.unreachable.localizedDescription)
            return
        }
        commandPending = true
        let requestID = UUID()
        pendingRequestID = requestID
        commandTimeout?.cancel()
        commandTimeout = Task {
            try? await Task.sleep(for: .seconds(12))
            guard !Task.isCancelled, pendingRequestID == requestID else { return }
            finishRemoteCommand(requestID, error: "No acknowledgement received. Check the recording device; the ride may still be running.")
        }
        session.sendMessage(["endRide": ride.id.uuidString], replyHandler: { @Sendable reply in
            let endedID = reply["ended"] as? String
            let message = reply["error"] as? String ?? (endedID == ride.id.uuidString ? nil : "The owner did not confirm ending this ride.")
            Task { @MainActor in
                if message == nil && self.peer?.ride?.id == ride.id { self.peer?.ride = nil }
                self.finishRemoteCommand(requestID, error: message)
            }
        }, errorHandler: { @Sendable error in
            let message = error.localizedDescription
            Task { @MainActor in self.finishRemoteCommand(requestID, error: message) }
        })
    }

    private var pendingRequestID: UUID?

    private func finishRemoteCommand(_ id: UUID, error: String?) {
        guard pendingRequestID == id else { return }
        commandTimeout?.cancel()
        pendingRequestID = nil
        commandPending = false
        if let error { report(error) }
        // A timeout never implies the owner stopped recording.
    }

    /// The companion session, only when it can currently carry data.
    private var companionSession: WCSession? {
        guard let session = connectivity, session.activationState == .activated else { return nil }
        #if os(iOS)
        guard session.isPaired, session.isWatchAppInstalled else { return nil }
        #endif
        return session
    }

    private func broadcast() {
        lastBroadcast = .now
        guard let session = companionSession else { return }
        do {
            let context = try companionContext()
            try session.updateApplicationContext(context)
            if session.isReachable {
                session.sendMessage(context, replyHandler: nil, errorHandler: { @Sendable error in
                    let message = error.localizedDescription
                    Task { @MainActor in
                        self.report("Live companion update delayed; queued context remains available: \(message)")
                    }
                })
            }
        } catch { report("Could not sync live ride: \(error.localizedDescription)") }
    }

    private func companionContext() throws -> [String: Any] {
        let snapshot = PeerSnapshot(ride: archive.active?.preview(), sentAt: .now, recording: recording,
                                    guidance: directions.guidance)
        return ["snapshot": try JSONEncoder().encode(snapshot), "places": try JSONEncoder().encode(places)]
    }

    private var outbox: URL { storeURL.deletingLastPathComponent().appendingPathComponent("Outbox") }

    private func queueCompleted(_ ride: Ride) {
        guard connectivity != nil else { return }
        do {
            try FileManager.default.createDirectory(at: outbox, withIntermediateDirectories: true)
            let url = outbox.appendingPathComponent("\(ride.id.uuidString).json")
            try JSONEncoder().encode(ride).write(to: url, options: .atomic)
            flushOutbox()
        } catch { report("Ride saved locally, but companion sync could not be queued: \(error.localizedDescription)") }
    }

    private func flushOutbox() {
        guard let session = connectivity, session.activationState == .activated else { return }
        do {
            guard FileManager.default.fileExists(atPath: outbox.path) else { return }
            let pending = Set(session.outstandingFileTransfers.map { $0.file.fileURL.lastPathComponent })
            for url in try FileManager.default.contentsOfDirectory(at: outbox, includingPropertiesForKeys: nil)
                where url.pathExtension == "json" && !pending.contains(url.lastPathComponent) {
                session.transferFile(url, metadata: ["kind": "completedRide"])
            }
        } catch { report("Could not read the companion sync queue: \(error.localizedDescription)") }
    }

    private func notifyCompanion(deleted ids: Set<UUID>) {
        companionSession?.transferUserInfo(["deletedRides": ids.map(\.uuidString).sorted()])
    }

    /// Stops deleted rides from being sent: removes their queued files and cancels transfers in flight.
    private func discardQueuedTransfers(of ids: Set<UUID>) {
        let names = Set(ids.map { "\($0.uuidString).json" })
        if let session = connectivity, session.activationState == .activated {
            for transfer in session.outstandingFileTransfers where names.contains(transfer.file.fileURL.lastPathComponent) {
                transfer.cancel()
            }
        }
        for name in names {
            let url = outbox.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            do { try FileManager.default.removeItem(at: url) }
            catch { report("Could not clear a deleted ride from the companion sync queue: \(error.localizedDescription)") }
        }
    }

    private func isDeletedRideFile(named name: String) -> Bool {
        guard let id = UUID(uuidString: URL(fileURLWithPath: name).deletingPathExtension().lastPathComponent) else { return false }
        return archive.isDeleted(id)
    }
}

extension RideController: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: (any Error)?) {
        let message = error?.localizedDescription
        let reachable = session.isReachable
        let snapshot = session.receivedApplicationContext["snapshot"] as? Data
        let places = session.receivedApplicationContext["places"] as? Data
        Task { @MainActor in
            if let message { self.report("Companion connection: \(message)") }
            self.reachable = reachable
            self.broadcast()
            self.flushOutbox()
            if let snapshot { self.receiveSnapshot(snapshot) }
            if let places { self.receivePlaces(places) }
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor in
            self.reachable = reachable
            self.broadcast()
            self.flushOutbox()
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        let data = applicationContext["snapshot"] as? Data
        let places = applicationContext["places"] as? Data
        Task { @MainActor in
            if let data { self.receiveSnapshot(data) }
            if let places { self.receivePlaces(places) }
        }
    }

    private func receivePlaces(_ data: Data) {
        do { try mergePlaces(JSONDecoder().decode(SavedPlaces.self, from: data).records) }
        catch { report("Saved-place sync failed: \(error.localizedDescription)") }
    }

    private func receiveSnapshot(_ data: Data) {
        do {
            var snapshot = try JSONDecoder().decode(PeerSnapshot.self, from: data)
            if let peer, peer.sentAt > snapshot.sentAt { return }
            if let ride = snapshot.ride, archive.completed.contains(where: { $0.id == ride.id }) || archive.isDeleted(ride.id) {
                snapshot.ride = nil
                snapshot.recording = false
            }
            peer = snapshot
            #if os(iOS)
            if archive.active == nil {
                if var ride = snapshot.ride {
                    // A delayed companion snapshot cannot confirm stationarity beyond its send time.
                    ride.finishStationary(at: snapshot.sentAt)
                    liveActivity.start(ride, onError: report)
                    liveActivity.update(ride)
                } else { liveActivity.endAll() }
            }
            #endif
        } catch { report("Could not decode companion ride: \(error.localizedDescription)") }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any],
                             replyHandler: @escaping ([String: Any]) -> Void) {
        let rideID = message["endRide"] as? String
        let requestsSnapshot = message["requestSnapshot"] as? Bool == true
        // WCSession owns the reply callback; it is called exactly once on the main actor.
        let reply = ReplyHandler(replyHandler)
        Task { @MainActor in
            if requestsSnapshot, rideID == nil {
                do { reply.call(try self.companionContext()) }
                catch { reply.call(["error": error.localizedDescription]) }
                return
            }
            guard !requestsSnapshot, let rideID, self.archive.active?.id.uuidString == rideID else {
                reply.call(["error": "That ride is no longer active on this device."])
                self.broadcast()
                return
            }

            do {
                try self.end()
                reply.call(["ended": rideID])
            } catch { reply.call(["error": error.localizedDescription]) }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        let data = message["snapshot"] as? Data
        let places = message["places"] as? Data
        Task { @MainActor in
            if let data { self.receiveSnapshot(data) }
            if let places { self.receivePlaces(places) }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        if let ids = userInfo["deletedRides"] as? [String] {
            let deleted = Set(ids.compactMap { UUID(uuidString: $0) })
            Task { @MainActor in
                do { try self.deleteRides(deleted, propagate: false) }
                catch { self.report("Could not apply a ride deletion from the companion: \(error.localizedDescription)") }
            }
            return
        }
        guard let id = userInfo["savedRide"] as? String, let uuid = UUID(uuidString: id) else { return }
        Task { @MainActor in
            let url = self.outbox.appendingPathComponent("\(uuid.uuidString).json")
            guard FileManager.default.fileExists(atPath: url.path) else { return }
            do { try FileManager.default.removeItem(at: url) }
            catch { self.report("Could not clear acknowledged companion transfer: \(error.localizedDescription)") }
        }
    }

    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        guard file.metadata?["kind"] as? String == "completedRide" else { return }
        // The temporary file is only valid for the duration of this delegate callback.
        let result = Result { try Data(contentsOf: file.fileURL) }
        Task { @MainActor in
            do {
                let ride = try JSONDecoder().decode(Ride.self, from: result.get())
                guard ride.endedAt != nil else { throw CocoaError(.fileReadCorruptFile) }
                guard self.storageAvailable else { throw RideFailure.storage }
                var next = self.archive
                next.importCompleted(ride)
                try self.persist(next)
                if self.peer?.ride?.id == ride.id { self.peer?.ride = nil }
                #if os(iOS)
                self.liveActivity.end(ride)
                #endif
                self.connectivity?.transferUserInfo(["savedRide": ride.id.uuidString])
                // The sender still has a ride that was deleted here (for example it was offline at the time).
                if self.archive.isDeleted(ride.id) { self.notifyCompanion(deleted: [ride.id]) }
            } catch { self.report("Could not save companion ride: \(error.localizedDescription). It remains on its recording device.") }
        }
    }

    nonisolated func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: (any Error)?) {
        let message = error?.localizedDescription
        let name = fileTransfer.file.fileURL.lastPathComponent
        Task { @MainActor in
            // Cancelling the transfer of a deleted ride is expected, not a failure.
            if let message, !self.isDeletedRideFile(named: name) {
                self.report("Companion transfer pending: \(message). It will retry on the next connection.")
            }
        }
    }

    #if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    #endif
}

// The framework callback is only transported across isolation, never invoked concurrently.
private final class ReplyHandler: @unchecked Sendable {
    private let callback: ([String: Any]) -> Void
    init(_ callback: @escaping ([String: Any]) -> Void) { self.callback = callback }
    func call(_ value: [String: Any]) { callback(value) }
}
