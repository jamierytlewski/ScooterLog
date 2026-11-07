import MapKit
import ScooterCore
import SwiftUI
import UIKit

enum RideShareRoute: String, CaseIterable, Identifiable {
    case protected = "Protected endpoints"
    case whole = "Whole route"
    case none = "Stats only"

    var id: Self { self }

    var explanation: String {
        switch self {
        case .protected:
            "Hides route points and connecting lines within 200 meters of both endpoints, including revisits. Remaining roads and map labels can still reveal where you rode."
        case .whole:
            "Includes your precise start, end, and all recorded route segments. Only share this if you are comfortable revealing those locations."
        case .none:
            "No map or location. Just your ride stats."
        }
    }
}

enum RideShareFormat: String, CaseIterable, Identifiable {
    case portrait = "Portrait 4:5"
    case square = "Square 1:1"

    var id: Self { self }
    var size: CGSize { CGSize(width: 540, height: self == .portrait ? 675 : 540) }
    func mapSize(showsLegend: Bool) -> CGSize {
        self == .portrait
            ? CGSize(width: 492, height: showsLegend ? 320 : 344)
            : CGSize(width: 238, height: showsLegend ? 360 : 392)
    }
}

struct RideShareView: View {
    let ride: Ride
    @State private var route: RideShareRoute = .protected
    @State private var showSpeedMap = true
    @State private var format: RideShareFormat = .portrait
    @State private var image: UIImage?
    @State private var imageID: String?
    @State private var error: String?
    @State private var isSharing = false
    @State private var retry = 0
    @AppStorage(RideTheme.preferenceKey) private var theme: RideTheme = .tronBlue

    private var renderID: String {
        "\(route.rawValue)-\(showSpeedMap)-\(format.rawValue)-\(theme.rawValue)-\(RideUnitSystem.selected.rawValue)-\(retry)"
    }

    private var currentImage: UIImage? { imageID == renderID ? image : nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Picker("Route visibility", selection: $route) {
                    ForEach(RideShareRoute.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .frame(minHeight: 44)
                .accessibilityIdentifier("shareRouteVisibility")

                Text(route.explanation)
                    .font(.footnote)
                    .foregroundStyle(RideTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                Toggle("Speed heat map", isOn: $showSpeedMap)
                    .disabled(route == .none)
                    .accessibilityIdentifier("shareSpeedHeatMap")

                Picker("Image layout", selection: $format) {
                    ForEach(RideShareFormat.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("shareImageLayout")

                if let image = currentImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .accessibilityLabel(previewDescription)
                        .accessibilityIdentifier("rideScorecardPreview")
                } else if let error {
                    ContentUnavailableView {
                        Label("Scorecard unavailable", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Try again") { retry += 1 }
                    }
                } else {
                    ProgressView("Preparing your scorecard...")
                        .frame(maxWidth: .infinity, minHeight: 260)
                }

                Button("Share image", systemImage: "square.and.arrow.up") {
                    isSharing = true
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(currentImage == nil)
                .accessibilityIdentifier("shareScorecardImage")

                Text("The image includes no ride date, owner, heart rate, or GPS timestamps. Stats describe the entire ride even when endpoints are hidden.")
                    .font(.footnote)
                    .foregroundStyle(RideTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding()
        }
        .background(RideTheme.canvas)
        .navigationTitle("Share ride")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: renderID) { await prepareImage() }
        .sheet(isPresented: $isSharing) {
            if let image = currentImage {
                RideImageShareSheet(image: image) { shareError in
                    if let shareError {
                        error = "Could not share image: \(shareError.localizedDescription)"
                        self.image = nil
                    }
                    isSharing = false
                }
            }
        }
    }

    private var previewDescription: String {
        "Arcade ride scorecard. \(RideUnits.distance(ride.distance)), elapsed \(RideFormat.spokenDuration(ride.elapsed(at: .now))), average speed \(RideUnits.speed(ride.averageSpeed(at: .now))). \(route.rawValue). \(showSpeedMap && route != .none ? "Route coloured by GPS speed." : "") \(format.rawValue)."
    }

    @MainActor
    private func prepareImage() async {
        image = nil
        imageID = nil
        error = nil
        let requestedID = renderID
        let requestedRoute = route
        let requestedTheme = theme
        let requestedSpeedMap = showSpeedMap
        let requestedFormat = format
        do {
            let map: UIImage?
            if requestedRoute == .none {
                map = nil
            } else {
                let segments = try RideExport.sharedSpeedSegments(
                    ride, privacyRadius: requestedRoute == .protected ? 200 : nil
                )
                map = try await RideShareMap.image(segments: segments, theme: requestedTheme,
                                                   showSpeedMap: requestedSpeedMap,
                                                   size: requestedFormat.mapSize(showsLegend: requestedSpeedMap))
            }
            try Task.checkCancellation()
            let renderer = ImageRenderer(content: RideScorecard(
                ride: ride, theme: requestedTheme, units: .selected, route: requestedRoute,
                map: map, showSpeedMap: requestedSpeedMap, format: requestedFormat
            ))
            renderer.scale = 2
            renderer.isOpaque = true
            guard let rendered = renderer.uiImage else { throw RideShareMap.RenderError.imageUnavailable }
            guard requestedID == renderID else { return }
            image = rendered
            imageID = requestedID
        } catch is CancellationError {
            // A changed privacy choice must never publish the previous map.
        } catch {
            guard !Task.isCancelled else { return }
            if let routeError = error as? RideExport.PrivateRouteError, routeError == .insufficientRoute {
                self.error = requestedRoute == .protected
                    ? "Not enough route remains outside the protected endpoints. Choose Stats only, or deliberately choose Whole route."
                    : "This ride has no continuous GPS route. Choose Stats only."
            } else {
                self.error = "Could not prepare the image: \(error.localizedDescription). Try again, or choose Stats only to share without a map."
            }
        }
    }
}

private struct RideImageShareSheet: UIViewControllerRepresentable {
    let image: UIImage
    let completion: @MainActor (Error?) -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [image], applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, error in
            Task { @MainActor in completion(error) }
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

@MainActor
private enum RideShareMap {
    enum RenderError: LocalizedError {
        case imageUnavailable
        var errorDescription: String? { "The scorecard image could not be rendered." }
    }

    static func image(segments: [RideSpeedSegment], theme: RideTheme,
                      showSpeedMap: Bool, size: CGSize) async throws -> UIImage {
        let coordinates = segments.map { segment in
            segment.samples.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
        }
        let points = coordinates.flatMap { $0 }.map { MKMapPoint($0) }
        guard let origin = points.first else { throw RideExport.PrivateRouteError.insufficientRoute }
        let worldWidth = MKMapRect.world.size.width
        let unwrapped = points.map { point in
            var x = point.x
            if x - origin.x > worldWidth / 2 { x -= worldWidth }
            if origin.x - x > worldWidth / 2 { x += worldWidth }
            return MKMapPoint(x: x, y: point.y)
        }
        let minX = unwrapped.map(\.x).min() ?? origin.x
        let maxX = unwrapped.map(\.x).max() ?? origin.x
        let minY = unwrapped.map(\.y).min() ?? origin.y
        let maxY = unwrapped.map(\.y).max() ?? origin.y
        var width = max(500, maxX - minX)
        var height = max(500, maxY - minY)
        let aspect = size.width / size.height
        if width / height < aspect { width = height * aspect }
        else { height = width / aspect }
        let rect = MKMapRect(x: (minX + maxX - width) / 2, y: (minY + maxY - height) / 2,
                             width: width, height: height)
        let options = MKMapSnapshotter.Options()
        options.mapRect = rect.insetBy(dx: -width * 0.18, dy: -height * 0.18)
        options.size = size
        options.scale = 2
        options.traitCollection = UITraitCollection(userInterfaceStyle: .dark)
        let configuration = MKStandardMapConfiguration(elevationStyle: .flat)
        configuration.pointOfInterestFilter = .excludingAll
        configuration.showsTraffic = false
        options.preferredConfiguration = configuration
        let snapshot = try await MKMapSnapshotter(options: options).start()
        try Task.checkCancellation()
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        format.opaque = true
        return UIGraphicsImageRenderer(size: options.size, format: format).image { _ in
            snapshot.image.draw(at: .zero)
            // Keep MapKit's map and attribution intact; only draw the retained route geometry.
            for (segmentIndex, segment) in coordinates.enumerated() {
                let path = UIBezierPath()
                for (index, coordinate) in segment.enumerated() {
                    let point = snapshot.point(for: coordinate)
                    if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
                }
                path.lineCapStyle = .round
                path.lineJoinStyle = .round
                UIColor.black.withAlphaComponent(0.8).setStroke()
                path.lineWidth = 8
                path.stroke()
                UIColor(showSpeedMap ? segments[segmentIndex].band.color : (theme == .tronBlue
                        ? Color(red: 0.3, green: 0.9, blue: 1)
                        : Color(red: 1, green: 0.4, blue: 0.5))).setStroke()
                path.lineWidth = 4
                path.stroke()
            }
        }
    }
}

struct RideScorecard: View {
    let ride: Ride
    let theme: RideTheme
    let units: RideUnitSystem
    let route: RideShareRoute
    let map: UIImage?
    var showSpeedMap = true
    var format: RideShareFormat = .portrait

    private let ink = Color(red: 0.77, green: 0.88, blue: 0.95)
    private var accent: Color {
        theme == .tronBlue
            ? Color(red: 0.3, green: 0.9, blue: 1)
            : Color(red: 1, green: 0.4, blue: 0.5)
    }

    var body: some View {
        VStack(spacing: 10) {
            ArcadeRideTitle(color: accent)
                .frame(width: 358, height: 28)

            if format == .portrait {
                distance
                LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading),
                                    GridItem(.flexible(), alignment: .leading)], spacing: 8) {
                    metrics
                }
                .overlay(alignment: .bottom) {
                    Rectangle().fill(accent.opacity(0.5)).frame(height: 1).offset(y: 5)
                }
                mapArtwork
            } else {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 18) {
                        distance
                        metrics
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    mapArtwork
                }
            }

            if showSpeedMap, map != nil {
                speedLegend
            }

            Spacer(minLength: 0)
            HStack(alignment: .center) {
                Text("ScooterLog")
                    .font(.system(size: 21, weight: .bold, design: .rounded))
                    .foregroundStyle(accent)
                Spacer()
                Text(route == .protected ? "ENDPOINTS HIDDEN"
                     : route == .whole ? "WHOLE ROUTE" : "STATS ONLY")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(ink)
            }
        }
        .padding(24)
        .frame(width: format.size.width, height: format.size.height)
        .background(RideTheme.artworkBackground)
        .overlay {
            Rectangle().strokeBorder(accent.opacity(0.65), lineWidth: 2).padding(12)
        }
        .environment(\.colorScheme, .dark)
        .environment(\.dynamicTypeSize, .medium)
    }

    private var distance: some View {
        VStack(alignment: format == .portrait ? .center : .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(String(format: "%.2f", ride.distance / units.metersPerUnit))
                    .font(.system(size: format == .portrait ? 42 : 40, weight: .black, design: .monospaced))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .foregroundStyle(accent)
                Text(units.distanceSymbol.uppercased())
                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                    .foregroundStyle(ink)
            }
            Text(ride.isTrimmedEstimate == true ? "ESTIMATED DISTANCE" : "DISTANCE")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .tracking(2)
                .foregroundStyle(ink)
        }
    }

    @ViewBuilder
    private var metrics: some View {
        score("ELAPSED", RideFormat.duration(ride.elapsed(at: .now)))
        score(ride.isTrimmedEstimate == true ? "EST. AVG SPEED" : "AVG SPEED",
              RideUnits.speed(ride.averageSpeed(at: .now), units: units))
        score("MOVING AVG", ride.isTrimmedEstimate == true ? "UNAVAILABLE"
              : RideUnits.speed(ride.movingAverageSpeed, units: units))
        score("MOVING TIME", ride.isTrimmedEstimate == true ? "UNAVAILABLE"
              : RideFormat.duration(ride.movingDuration))
    }

    private func score(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundStyle(ink)
            Text(value).font(.system(size: format == .portrait ? 17 : 19, weight: .bold, design: .monospaced))
                .foregroundStyle(.white).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.7)
        }
    }

    @ViewBuilder
    private var mapArtwork: some View {
        let size = format.mapSize(showsLegend: showSpeedMap && map != nil)
        if let map {
            Image(uiImage: map).resizable()
                .frame(width: size.width, height: size.height)
        } else {
            ScooterArtwork(theme: theme)
                .frame(width: size.width, height: size.height)
        }
    }

    private var speedLegend: some View {
        HStack(spacing: 0) {
            ForEach(RideSpeedBand.allCases, id: \.self) { band in
                HStack(spacing: 4) {
                    Rectangle().fill(band.color).frame(width: 12, height: 4)
                    Text(speedRange(band))
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(ink)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .overlay(alignment: .bottom) {
            Text("GPS SPEED (\(units.speedSymbol.uppercased()))")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(ink)
                .offset(y: 16)
        }
        .padding(.bottom, 16)
    }

    private func speedRange(_ band: RideSpeedBand) -> String {
        func boundary(_ mph: Double) -> String {
            String(format: units == .metric ? "%.1f" : "%.0f",
                   mph * RideUnits.metersPerMile / units.metersPerUnit)
        }
        switch band {
        case .slow: return "<\(boundary(5))"
        case .cruising: return "\(boundary(5))-<\(boundary(10))"
        case .brisk: return "\(boundary(10))-<\(boundary(15))"
        case .fast: return "\(boundary(15))+"
        case .unknown: return "Unknown"
        }
    }
}

/// Original bitmap lettering for the share artifact, independent of installed fonts.
private struct ArcadeRideTitle: View {
    let color: Color

    var body: some View {
        Canvas { context, size in
            let glyphs: [String] = [
                "11110/10001/10001/11110/10100/10010/10001", // R
                "111/010/010/010/010/010/111", // I
                "11110/10001/10001/10001/10001/10001/11110", // D
                "11111/10000/10000/11110/10000/10000/11111", // E
                "",
                "01111/10000/10000/10000/10000/10000/01111", // C
                "01110/10001/10001/10001/10001/10001/01110", // O
                "10001/11011/10101/10101/10001/10001/10001", // M
                "11110/10001/10001/11110/10000/10000/10000", // P
                "10000/10000/10000/10000/10000/10000/11111", // L
                "11111/10000/10000/11110/10000/10000/11111", // E
                "11111/00100/00100/00100/00100/00100/00100", // T
                "11111/10000/10000/11110/10000/10000/11111"  // E
            ]
            let widths: [Int] = glyphs.map { glyph in
                if glyph.isEmpty { return 3 }
                return glyph.split(separator: "/").first?.count ?? 0
            }
            let glyphColumns: Int = widths.reduce(0, +)
            let gapColumns: Int = (glyphs.count - 1) * 2
            let columns: Int = glyphColumns + gapColumns
            let pixel = min(size.width / CGFloat(columns), size.height / 7)
            var x = (size.width - CGFloat(columns) * pixel) / 2
            for (index, glyph) in glyphs.enumerated() {
                for (row, line) in glyph.split(separator: "/").enumerated() {
                    for (column, value) in line.enumerated() where value == "1" {
                        let rect = CGRect(x: x + CGFloat(column) * pixel, y: CGFloat(row) * pixel,
                                          width: pixel, height: pixel)
                        context.fill(Path(rect), with: .color(color))
                    }
                }
                x += CGFloat(widths[index] + 2) * pixel
            }
        }
    }
}

#if DEBUG
private enum RideSharePreview {
    static var ride: Ride {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        var ride = Ride(owner: "Synthetic preview", startedAt: start)
        for index in 0...120 {
            let time = start.addingTimeInterval(Double(index * 4))
            let sample = LocationSample(
                latitude: 40.7195 + Double(index) * 0.00025,
                longitude: -74.0132 + sin(Double(index) * 0.04) * 0.0015,
                timestamp: time, accuracy: 5, speed: [2.0, 3.5, 5.2, 8.0, -1.0][index / 25]
            )
            precondition(ride.append(sample, receivedAt: time))
        }
        ride.end(at: start.addingTimeInterval(480))
        return ride
    }
}

#Preview("Arcade scorecard", traits: .sizeThatFitsLayout) {
    RideScorecard(ride: RideSharePreview.ride, theme: .tronBlue, units: .imperial, route: .none, map: nil)
}

#Preview("Share composer") {
    NavigationStack {
        RideShareView(ride: RideSharePreview.ride)
    }
}
#endif
