import Combine
import Foundation
import HealthKit

@MainActor
final class HealthReader: NSObject, ObservableObject {
    static let shared = HealthReader()
    @Published private(set) var beatsPerMinute: Double?
    @Published private(set) var measuredAt: Date?
    @Published private(set) var status = "Optional: show available heart-rate samples."
    @Published private(set) var enabled = false
    private let store = HKHealthStore()
    private var query: HKSampleQuery?
    private var generation = UUID()
    private var authorizationGeneration = UUID()
    #if os(watchOS)
    @Published private(set) var liveStarting = false
    @Published private(set) var liveActive = false
    private var workout: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var discarding = false
    #endif

    func enable() async {
        let authorizationToken = UUID()
        authorizationGeneration = authorizationToken
        guard HKHealthStore.isHealthDataAvailable(),
              let type = HKObjectType.quantityType(forIdentifier: .heartRate) else {
            status = "Health data is not available on this device."
            return
        }
        do {
            try await store.requestAuthorization(toShare: [], read: [type])
            guard authorizationGeneration == authorizationToken else { return }
            enabled = true
            refresh()
        } catch { status = "Health request failed: \(error.localizedDescription)" }
    }

    func refresh() {
        guard enabled, let type = HKObjectType.quantityType(forIdentifier: .heartRate) else { return }
        #if os(watchOS)
        guard !liveActive else { return }
        #endif
        let token = UUID()
        generation = token
        if let query { store.stop(query) }
        let predicate = HKQuery.predicateForSamples(withStart: Date.now.addingTimeInterval(-3600), end: .now)
        let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: 1,
                                  sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]) { @Sendable _, samples, error in
            let message = error?.localizedDescription
            let sample = samples?.first as? HKQuantitySample
            let bpm = sample?.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
            let date = sample?.endDate
            Task { @MainActor in
                guard self.enabled, self.generation == token else { return }
                self.beatsPerMinute = bpm
                self.measuredAt = date
                self.status = message.map { "Health query failed: \($0)" }
                    ?? (bpm == nil ? "No readable heart-rate samples in the last hour (no data or read access unavailable)." : "Available sample, not continuous monitoring")
            }
        }
        self.query = query
        store.execute(query)
    }

    func disable() {
        authorizationGeneration = UUID()
        generation = UUID()
        if let query { store.stop(query) }
        query = nil
        enabled = false
        beatsPerMinute = nil
        measuredAt = nil
        status = "Heart-rate display off. Manage permissions in Health or Settings."
        #if os(watchOS)
        stopLiveSession()
        #endif
    }

    #if os(watchOS)
    func startLiveSession() async {
        let controller = RideController.shared
        guard controller.recording, let rideID = controller.archive.active?.id else {
            status = "Start a local GPS ride before requesting live heart rate."
            return
        }
        guard !liveActive, !liveStarting, workout == nil, HKHealthStore.isHealthDataAvailable(),
              let heartRate = HKObjectType.quantityType(forIdentifier: .heartRate) else { return }
        liveStarting = true
        let token = UUID()
        authorizationGeneration = token
        defer { liveStarting = false }
        do {
            try await store.requestAuthorization(toShare: [HKObjectType.workoutType()], read: [heartRate])
            guard authorizationGeneration == token, controller.recording,
                  controller.archive.active?.id == rideID else { return }
            generation = UUID()
            if let query { store.stop(query) }
            let configuration = HKWorkoutConfiguration()
            configuration.activityType = .other
            configuration.locationType = .outdoor
            let session = try HKWorkoutSession(healthStore: store, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: configuration)
            session.delegate = self
            builder.delegate = self
            workout = session
            self.builder = builder
            enabled = true
            beatsPerMinute = nil
            measuredAt = nil
            let start = Date.now
            session.startActivity(with: start)
            try await builder.beginCollection(at: start)
            guard authorizationGeneration == token, controller.recording,
                  controller.archive.active?.id == rideID else {
                stopLiveSession()
                return
            }
            liveActive = true
            status = "Other session active. Waiting for available sensor samples; no guaranteed frequency."
        } catch {
            stopLiveSession()
            status = "Live HR unavailable: \(error.localizedDescription). GPS recording is unaffected."
        }
    }

    func stopLiveSession() {
        authorizationGeneration = UUID()
        guard let workout, workout.state != .ended else { return }
        workout.end()
        status = "Ending Other session and discarding workout results."
    }

    private func discardResults(at date: Date) async {
        guard let builder, !discarding else { return }
        discarding = true
        defer { discarding = false }
        do { try await builder.endCollection(at: date) }
        catch { status = "Collection ended with an error: \(error.localizedDescription). Discarding results." }
        builder.discardWorkout()
        self.builder = nil
        workout = nil
        liveActive = false
        status = "Other session discarded; ScooterLog did not save a workout. watchOS may retain Health samples or ring effects."
    }
    #endif
}

#if os(watchOS)
extension HealthReader: HKWorkoutSessionDelegate, HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState,
                                    from fromState: HKWorkoutSessionState, date: Date) {
        guard toState == .ended else { return }
        let id = ObjectIdentifier(workoutSession)
        Task { @MainActor in
            guard self.workout.map(ObjectIdentifier.init) == id else { return }
            await self.discardResults(at: date)
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: any Error) {
        let message = error.localizedDescription
        let id = ObjectIdentifier(workoutSession)
        Task { @MainActor in
            guard self.workout.map(ObjectIdentifier.init) == id else { return }
            self.stopLiveSession()
            await self.discardResults(at: .now)
            self.status = "Other session failed: \(message). Results discarded; GPS recording is unaffected."
        }
    }

    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        let hasHeartRate = collectedTypes.contains { $0.identifier == HKQuantityTypeIdentifier.heartRate.rawValue }
        let id = ObjectIdentifier(workoutBuilder)
        guard hasHeartRate else { return }
        Task { @MainActor in
            guard self.enabled, self.liveActive, self.builder.map(ObjectIdentifier.init) == id,
                  self.workout?.state == .running,
                  let type = HKObjectType.quantityType(forIdentifier: .heartRate),
                  let statistics = self.builder?.statistics(for: type),
                  let quantity = statistics.mostRecentQuantity() else { return }
            self.beatsPerMinute = quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
            self.measuredAt = statistics.mostRecentQuantityDateInterval()?.end
            self.status = "Live sensor sample from an explicitly started Other session."
        }
    }
}
#endif
