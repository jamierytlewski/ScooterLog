import Foundation

public enum RideSpeedBand: String, CaseIterable, Sendable {
    case slow, cruising, brisk, fast, unknown

    public init(speed: Double) {
        guard speed.isFinite, speed >= 0 else { self = .unknown; return }
        switch speed {
        case ..<(5 * RideUnits.metersPerMile / 3600): self = .slow
        case ..<(10 * RideUnits.metersPerMile / 3600): self = .cruising
        case ..<(15 * RideUnits.metersPerMile / 3600): self = .brisk
        default: self = .fast
        }
    }
}

public struct RideSpeedSegment: Identifiable, Sendable {
    public let id: Int
    public let band: RideSpeedBand
    public var samples: [LocationSample]
}

extension Ride {
    public var routeSegments: [[LocationSample]] {
        var segments: [[LocationSample]] = []
        for sample in samples {
            if let previous = segments.last?.last,
               (0...15).contains(sample.timestamp.timeIntervalSince(previous.timestamp)) {
                segments[segments.count - 1].append(sample)
            } else { segments.append([sample]) }
        }
        return segments
    }

    public var speedSegments: [RideSpeedSegment] {
        var segments: [RideSpeedSegment] = []
        var index = 0
        for route in routeSegments where route.count > 1 {
            for pair in zip(route, route.dropFirst()) {
                let band = RideSpeedBand(speed: pair.1.speed)
                if let last = segments.last, last.band == band, last.samples.last == pair.0 {
                    segments[segments.count - 1].samples.append(pair.1)
                } else {
                    segments.append(RideSpeedSegment(id: index, band: band, samples: [pair.0, pair.1]))
                }
                index += 1
            }
        }
        return segments
    }
}

public enum RideExport {
    public enum PrivateRouteError: Error, Equatable {
        case invalidPrivacyRadius
        case insufficientRoute
    }

    /// Shared geometry for image and GPX exports. A nil radius explicitly includes the whole route.
    public static func sharedRouteSegments(_ ride: Ride, privacyRadius: Double? = 200) throws -> [[LocationSample]] {
        if let privacyRadius, !privacyRadius.isFinite || privacyRadius <= 0 {
            throw PrivateRouteError.invalidPrivacyRadius
        }
        guard ride.endedAt != nil, let first = ride.samples.first, let last = ride.samples.last,
              ride.samples.count >= 2 else { throw PrivateRouteError.insufficientRoute }
        guard let privacyRadius else {
            let segments = ride.routeSegments.filter { $0.count > 1 }
            guard !segments.isEmpty else { throw PrivateRouteError.insufficientRoute }
            return segments
        }
        var segments: [[LocationSample]] = []
        var current: [LocationSample] = []
        func outside(_ sample: LocationSample) -> Bool {
            sample.distance(to: first) > privacyRadius && sample.distance(to: last) > privacyRadius
        }
        for sample in ride.samples {
            guard outside(sample) else {
                if current.count > 1 { segments.append(current) }
                current = []
                continue
            }
            if let previous = current.last {
                let gap = sample.timestamp.timeIntervalSince(previous.timestamp)
                let length = previous.distance(to: sample)
                // Triangle inequality keeps the entire connecting segment outside the privacy zones.
                let clearance = min(previous.distance(to: first), previous.distance(to: last),
                                    sample.distance(to: first), sample.distance(to: last))
                if !(0...15).contains(gap) || clearance - length <= privacyRadius {
                    if current.count > 1 { segments.append(current) }
                    current = []
                }
            }
            current.append(sample)
        }
        if current.count > 1 { segments.append(current) }
        guard !segments.isEmpty else { throw PrivateRouteError.insufficientRoute }
        return segments
    }

    /// A route-only GPX with no timestamps, owner, ride identifier, or original endpoints.
    /// Every retained point is outside the radius of both endpoints, including revisits.
    public static func privateRouteGPX(_ ride: Ride, privacyRadius: Double = 200) throws -> String {
        let segments = try sharedRouteSegments(ride, privacyRadius: privacyRadius)
        var lines = [
            #"<?xml version="1.0" encoding="UTF-8"?>"#,
            #"<gpx version="1.1" creator="ScooterLog" xmlns="http://www.topografix.com/GPX/1/1">"#,
            "<trk><name>Shared ride</name>"
        ]
        for segment in segments {
            lines.append("<trkseg>")
            for sample in segment {
                lines.append("<trkpt lat=\"\(sample.latitude)\" lon=\"\(sample.longitude)\"/>")
            }
            lines.append("</trkseg>")
        }
        lines.append("</trk></gpx>")
        return lines.joined(separator: "\n")
    }

    private struct Archive: Encodable {
        let schemaVersion = 1
        let exportedAt: Date
        let distanceUnit = "meters"
        let speedUnit = "meters per second"
        let durationUnit = "seconds"
        let rides: [Ride]
    }

    public static func json(_ rides: [Ride], exportedAt: Date = .now) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(Archive(exportedAt: exportedAt, rides: completed(rides)))
    }

    public static func gpx(_ rides: [Ride], exportedAt: Date = .now) -> String {
        let date = ISO8601DateFormatter()
        var lines = [
            #"<?xml version="1.0" encoding="UTF-8"?>"#,
            #"<gpx version="1.1" creator="ScooterLog" xmlns="http://www.topografix.com/GPX/1/1" xmlns:scooterlog="urn:scooterlog:export:1">"#,
            "<metadata><name>ScooterLog activities</name><time>\(date.string(from: exportedAt))</time></metadata>"
        ]
        for ride in completed(rides) {
            lines.append("<trk><name>\(escape("\(ride.owner) ride \(date.string(from: ride.startedAt))"))</name>")
            lines.append("<desc>\(ride.id.uuidString)</desc>")
            for segment in ride.routeSegments {
                lines.append("<trkseg>")
                for sample in segment {
                    lines.append("<trkpt lat=\"\(sample.latitude)\" lon=\"\(sample.longitude)\"><time>\(date.string(from: sample.timestamp))</time>")
                    if sample.speed.isFinite, sample.speed >= 0 {
                        lines.append("<extensions><scooterlog:speed>\(sample.speed)</scooterlog:speed></extensions>")
                    }
                    lines.append("</trkpt>")
                }
                lines.append("</trkseg>")
            }
            lines.append("</trk>")
        }
        lines.append("</gpx>")
        return lines.joined(separator: "\n")
    }

    public static func write(_ rides: [Ride], to directory: URL) throws -> [URL] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let jsonURL = directory.appendingPathComponent("ScooterLog-activities.json")
        let gpxURL = directory.appendingPathComponent("ScooterLog-activities.gpx")
        try json(rides).write(to: jsonURL, options: .atomic)
        try gpx(rides).write(to: gpxURL, atomically: true, encoding: .utf8)
        return [jsonURL, gpxURL]
    }

    private static func completed(_ rides: [Ride]) -> [Ride] {
        rides.filter { $0.endedAt != nil }.sorted {
            $0.startedAt == $1.startedAt ? $0.id.uuidString < $1.id.uuidString : $0.startedAt < $1.startedAt
        }
    }

    private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}
