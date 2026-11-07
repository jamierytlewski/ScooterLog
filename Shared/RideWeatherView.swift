import CoreLocation
import OSLog
import ScooterCore
import SwiftUI
import WeatherKit

/// Fetches WeatherKit data for the current location and reduces it to a ride verdict.
@MainActor
final class RideWeatherModel: ObservableObject {
    enum State {
        case idle
        case loading
        case loaded(RideWeatherAssessment, updated: Date)
        case failed(String)
    }

    struct Attribution {
        var lightMark: URL
        var darkMark: URL
        var legalPage: URL
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var attribution: Attribution?
    /// The latest real forecast, shared with the widgets.
    @Published private(set) var widgetWeather: RideWidgetSnapshot.Weather?
    private let location = PlanningLocation(desiredAccuracy: kCLLocationAccuracyKilometer,
                                            maxAccuracy: 5_000,
                                            maxAge: 15 * 60)
    private let logger = Logger(subsystem: "com.scooterlog.app", category: "Weather")
    private var task: Task<Void, Never>?
    private static let freshness: TimeInterval = 15 * 60

    var isLoading: Bool { if case .loading = state { true } else { false } }

    /// Refreshes when the last result is missing or older than 15 minutes, unless forced.
    func refresh(force: Bool = false) {
        if !force, case let .loaded(_, updated) = state, Date.now.timeIntervalSince(updated) < Self.freshness { return }
        guard !isLoading else { return }
        if ProcessInfo.processInfo.arguments.contains("-ScooterLogStubWeather") {
            let report = WeatherReport(current: WeatherSample(date: .now, precipitation: .none, chance: 0, intensity: 0, temperature: 12),
                                       hours: [WeatherSample(date: .now.addingTimeInterval(5400), precipitation: .rain,
                                                             chance: 0.6, intensity: 1, temperature: 11)])
            state = .loaded(RideWeather.assess(report), updated: .now)
            return
        }
        state = .loading
        task = Task {
            do {
                let coordinate = try await location.coordinate()
                let report = try await RideWeatherService.report(for: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
                let assessment = RideWeather.assess(report)
                state = .loaded(assessment, updated: .now)
                widgetWeather = RideWidgetSnapshot.Weather(assessment, updated: .now, latitude: coordinate.latitude,
                                                           longitude: coordinate.longitude)
                if attribution == nil, let mark = try? await WeatherService.shared.attribution {
                    attribution = Attribution(lightMark: mark.combinedMarkLightURL, darkMark: mark.combinedMarkDarkURL,
                                              legalPage: mark.legalPageURL)
                }
            } catch is CancellationError {
                state = .idle
            } catch let error as PlanningLocationError {
                logger.error("Weather location failed: \(String(describing: error), privacy: .public)")
                state = .failed(error == .permission
                                ? "Allow location access to check the weather where you are."
                                : "Couldn't find your location. Try again outdoors.")
            } catch {
                logger.error("WeatherKit request failed: \(String(describing: error), privacy: .public)")
                #if DEBUG
                state = .failed("Weather is unavailable: \(error.localizedDescription)")
                #else
                state = .failed("Weather is unavailable right now. Try again later.")
                #endif
            }
        }
    }
}

struct RideWeatherSection: View {
    @ObservedObject var model: RideWeatherModel
    let locationAuthorization: CLAuthorizationStatus
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Section {
            content
            #if os(iOS)
            if let attribution = model.attribution { attributionRow(attribution) }
            #endif
        } header: {
            Text("Weather").foregroundStyle(RideTheme.secondaryText)
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text("A forecast, not a road-condition report. Bridges, shade, and painted lines can stay icy or slick.")
                #if os(watchOS)
                if let attribution = model.attribution { attributionRow(attribution) }
                #endif
            }
            .foregroundStyle(RideTheme.secondaryText)
        }
        .ridePanelRow()
        .id("ride-weather")
        .task(id: authorized) { if authorized { model.refresh() } }
    }

    private var authorized: Bool {
        locationAuthorization == .authorizedWhenInUse || locationAuthorization == .authorizedAlways
    }

    @ViewBuilder private var content: some View {
        switch model.state {
        case .idle where locationAuthorization == .denied || locationAuthorization == .restricted:
            message("Allow location access in Settings to check the weather where you are.", systemImage: "location.slash")
        case .idle:
            Button { model.refresh(force: true) } label: {
                Label("Check riding weather", systemImage: "cloud.sun")
            }
        case .loading:
            HStack(spacing: 8) {
                ProgressView()
                Text("Checking weather...").foregroundStyle(RideTheme.secondaryText)
            }
            .accessibilityElement(children: .combine)
        case let .failed(text):
            message(text, systemImage: "exclamationmark.icloud")
            refreshButton
        case let .loaded(assessment, updated):
            verdict(assessment, updated: updated)
            refreshButton
        }
    }

    private func verdict(_ assessment: RideWeatherAssessment, updated: Date) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol(assessment.verdict))
                .font(.title2)
                .foregroundStyle(color(assessment.verdict))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(assessment.verdict.title).font(.headline)
                    Spacer(minLength: 4)
                    if let temperature = assessment.temperature {
                        Text(RideWeather.temperature(temperature)).font(.headline).monospacedDigit()
                    }
                }
                Text(assessment.summary).font(.subheadline)
                ForEach(Array(assessment.reasons.dropFirst().prefix(extraReasons)), id: \.self) { reason in
                    Text(reason.text).font(.footnote)
                }
                Text("Updated \(updated, style: .time)").font(.caption2).foregroundStyle(RideTheme.secondaryText)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var extraReasons: Int {
        #if os(watchOS)
        1
        #else
        3
        #endif
    }

    private var refreshButton: some View {
        Button { model.refresh(force: true) } label: {
            Label("Refresh weather", systemImage: "arrow.clockwise")
        }
        .disabled(model.isLoading)
    }

    private func message(_ text: String, systemImage: String) -> some View {
        Label { Text(text).fixedSize(horizontal: false, vertical: true) } icon: { Image(systemName: systemImage) }
            .font(.footnote)
    }

    private func attributionRow(_ attribution: RideWeatherModel.Attribution) -> some View {
        HStack(spacing: 8) {
            AsyncImage(url: colorScheme == .dark ? attribution.darkMark : attribution.lightMark) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                Text("Weather").font(.caption2)
            }
            .frame(height: 12)
            .accessibilityLabel("Apple Weather")
            Link("Data sources", destination: attribution.legalPage).font(.caption2)
        }
    }

    private func symbol(_ verdict: RideWeatherVerdict) -> String {
        switch verdict {
        case .good: "checkmark.circle.fill"
        case .caution: "exclamationmark.triangle.fill"
        case .avoid: "xmark.octagon.fill"
        }
    }

    private func color(_ verdict: RideWeatherVerdict) -> Color {
        switch verdict {
        case .good: .green
        case .caution: .orange
        case .avoid: .red
        }
    }
}
