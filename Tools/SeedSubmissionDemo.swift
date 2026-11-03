import Foundation

/// Compile with Sources/ScooterCore/*.swift. Only writes to an empty simulator app's store.
@main
enum SeedSubmissionDemo {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            throw failure("Pass the simulator app's Library/Application Support/ScooterLog directory.")
        }
        let directory = URL(fileURLWithPath: CommandLine.arguments[1]).standardizedFileURL
        guard directory.path.contains("/CoreSimulator/Devices/"),
              directory.lastPathComponent == "ScooterLog",
              !FileManager.default.fileExists(atPath: directory.path) else {
            throw failure("Demo seeding requires a new, empty ScooterLog store in an isolated simulator.")
        }
        let repository = RideRepository(directory: directory)
        // Synthetic rides between public Hudson River waterfront landmarks, never personal GPS data.
        let points: [(Double, Double)] = [
            (40.7133, -74.0168), (40.7195, -74.0132), (40.7260, -74.0112),
            (40.7325, -74.0105), (40.7390, -74.0100), (40.7454, -74.0087),
            (40.7517, -74.0082)
        ]
        let speeds = [2.0, 3.5, 5.2, 6.8, 4.1, 3.0]
        for day in 0..<3 {
            let start = Date.now.addingTimeInterval(-Double(day * 86_400 + 3_600))
            var ride = Ride(owner: "iPhone", startedAt: start)
            var time = start
            for segment in 0..<(points.count - 1 - day) {
                for step in 0..<40 {
                    let fraction = Double(step) / 40
                    let from = points[segment], to = points[segment + 1]
                    var sample = LocationSample(
                        latitude: from.0 + (to.0 - from.0) * fraction,
                        longitude: from.1 + (to.1 - from.1) * fraction,
                        timestamp: time, accuracy: 5, speed: speeds[segment])
                    if let previous = ride.samples.last {
                        time = time.addingTimeInterval(previous.distance(to: sample) / sample.speed)
                        sample = LocationSample(latitude: sample.latitude, longitude: sample.longitude,
                                                timestamp: time, accuracy: 5, speed: sample.speed)
                    }
                    guard ride.append(sample, receivedAt: time) else {
                        throw failure("A synthetic route sample was rejected.")
                    }
                }
            }
            ride.end(at: time)
            guard ride.distance > 1_000, ride.unknownDuration(at: time) < 1 else {
                throw failure("The demo ride must contain a continuous, accounted-for route.")
            }
            try repository.saveCompleted(ride)
        }
        var places = SavedPlaces()
        try places.merge([
            SavedPlace(name: "Hudson River Park", latitude: 40.7330, longitude: -74.0112),
            SavedPlace(name: "Little Island", latitude: 40.7420, longitude: -74.0101),
            SavedPlace(name: "Pier 57", latitude: 40.7437, longitude: -74.0092)
        ])
        try places.save(to: directory.appendingPathComponent("places.json"))
        print("Created three synthetic rides and three public destinations in \(directory.path).")
    }

    private static func failure(_ message: String) -> NSError {
        NSError(domain: "SubmissionDemo", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
