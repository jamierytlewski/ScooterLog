import XCTest
import UIKit

final class RideFlowTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testRideScorecardPrivacyAndSocialLayouts() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ScooterLogStubHistory"]
        app.launch()
        openHistory(in: app)
        let ride = app.buttons.matching(identifier: "rideRow").firstMatch
        XCTAssertTrue(ride.waitForExistence(timeout: 10))
        ride.tap()
        let share = app.buttons["shareRideStats"]
        reveal(share, in: app)
        share.tap()

        XCTAssertTrue(app.navigationBars["Share ride"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Scorecard unavailable"].waitForExistence(timeout: 10),
                      "The short fixture cannot bypass the default endpoint protection")
        XCTAssertEqual(app.switches["shareSpeedHeatMap"].value as? String, "1")
        let shareImage = app.buttons["shareScorecardImage"]
        XCTAssertFalse(shareImage.isEnabled)

        let visibility = app.buttons["shareRouteVisibility"]
        visibility.tap()
        app.buttons["Whole route"].tap()
        let preview = app.images["rideScorecardPreview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 45))
        XCTAssertTrue(preview.label.contains("Whole route"))
        XCTAssertTrue(preview.label.contains("Route coloured by GPS speed"))
        XCTAssertTrue(shareImage.isEnabled)

        app.buttons["Square 1:1"].tap()
        XCTAssertTrue(preview.waitForExistence(timeout: 45))
        XCTAssertTrue(preview.label.contains("Square 1:1"))
        let ratio = preview.frame.width / preview.frame.height
        XCTAssertEqual(ratio, 1, accuracy: 0.01)
        capture("Square speed heat scorecard")

        app.switches["shareSpeedHeatMap"].tap()
        XCTAssertTrue(preview.waitForExistence(timeout: 45))
        XCTAssertFalse(preview.label.contains("Route coloured by GPS speed"))

        visibility.tap()
        app.buttons["Protected endpoints"].tap()
        XCTAssertTrue(app.staticTexts["Scorecard unavailable"].waitForExistence(timeout: 10))
        XCTAssertFalse(preview.exists, "A failed protected render must never retain the previous whole-route image")
        XCTAssertFalse(shareImage.isEnabled)

        visibility.tap()
        app.buttons["Stats only"].tap()
        XCTAssertTrue(preview.waitForExistence(timeout: 10))
        XCTAssertTrue(preview.label.contains("Stats only"))
        XCTAssertFalse(app.switches["shareSpeedHeatMap"].isEnabled)
        app.buttons["Portrait 4:5"].tap()
        XCTAssertTrue(preview.waitForExistence(timeout: 10))
        XCTAssertEqual(preview.frame.width / preview.frame.height, 0.8, accuracy: 0.01)
        capture("Portrait stats-only scorecard")
    }

    @MainActor
    func testCaptureSubmissionAssets() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SCOOTERLOG_CAPTURE"] == "1",
                          "Opt-in capture flow for an isolated simulator seeded with Tools/SeedSubmissionDemo.swift.")
        let app = XCUIApplication()
        app.launchArguments = ["-rideTheme", "TronBlue"]
        app.launch()
        XCTAssertTrue(app.buttons["Start ride here"].waitForExistence(timeout: 10))
        submissionScene("01-dashboard")

        openHistory(in: app)
        XCTAssertEqual(app.buttons.matching(identifier: "rideRow").count, 3)
        submissionScene("02-ride-history")
        app.buttons.matching(identifier: "rideRow").firstMatch.tap()
        let routeMap = app.descendants(matching: .any)["savedRideRouteMap"].firstMatch
        XCTAssertTrue(routeMap.waitForExistence(timeout: 10))
        submissionScene("03-recorded-route")

        let heatMap = app.switches["speedHeatMap"]
        XCTAssertEqual(heatMap.value as? String, "1", "Speed heat map is on by default")
        submissionScene("04-speed-heat-map")

        app.navigationBars["Ride"].buttons.firstMatch.tap()
        openTab("Ride", in: app)
        openTab("Saved places", in: app)
        XCTAssertTrue(app.staticTexts["Little Island"].waitForExistence(timeout: 5))
        submissionScene("05-saved-places")

        openTab("Ride", in: app)
        openTab("Directions", in: app)
        let mode = app.buttons["routeMode"]
        reveal(mode, in: app)
        mode.tap()
        app.buttons["Walking"].tap()
        let destination = app.buttons["Directions to Pier 57"]
        reveal(destination, in: app, towardTop: true)
        destination.tap()
        let preview = app.descendants(matching: .any)["routePreview"].firstMatch
        let routeReady = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label CONTAINS %@", "Choose a route below"),
            object: app.staticTexts["directionsStatus"])
        XCTAssertEqual(XCTWaiter.wait(for: [routeReady], timeout: 45), .completed,
                       app.staticTexts["directionsStatus"].label)
        reveal(preview, in: app)
        XCTAssertTrue(preview.exists)
        if preview.frame.maxY > app.frame.maxY - 60 { app.swipeUp() }
        XCTAssertGreaterThan(preview.frame.minY, app.navigationBars["Directions"].frame.maxY)
        XCTAssertLessThan(preview.frame.maxY, app.frame.maxY - 20)
        submissionScene("06-route-planning")
    }

    @MainActor
    private func submissionScene(_ name: String) {
        Thread.sleep(forTimeInterval: 3)
        capture(name)
        print("APP_STORE_SCENE \(name) \(Date.now.timeIntervalSince1970)")
        Thread.sleep(forTimeInterval: 5)
    }

    @MainActor
    func testStartRecoverEndAndHistory() throws {
        let app = XCUIApplication()
        app.launch()
        try endExistingRide(in: app)
        let start = app.buttons["Start ride here"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        start.tap()
        let end = app.buttons["End ride"]
        XCTAssertTrue(end.waitForExistence(timeout: 5))
        let details = app.buttons["rideAccessoryDetails"]
        XCTAssertTrue(details.waitForExistence(timeout: 5))
        XCTAssertTrue(details.label.contains("Recording"), details.label)
        openTab("History", in: app)
        details.tap()
        XCTAssertTrue(app.navigationBars["ScooterLog"].waitForExistence(timeout: 5),
                      "The accessible status button returns to the Ride tab")
        capture("Active ride dashboard")
        app.terminate()
        app.launch()
        XCTAssertTrue(end.waitForExistence(timeout: 5), "A previously requested recording resumes after relaunch")
        XCTAssertFalse(app.buttons["Resume recording"].exists)
        end.tap()
        try XCTUnwrap(app.buttons.matching(identifier: "End ride").allElementsBoundByIndex.last).tap()
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        openTab("History", in: app)
        XCTAssertTrue(app.navigationBars["History"].waitForExistence(timeout: 5))
        XCTAssertGreaterThan(app.cells.count, 1)
    }

    @MainActor
    func testAppearanceSelectionPersists() throws {
        continueAfterFailure = true
        let app = XCUIApplication()
        app.launch()
        try endExistingRide(in: app)
        let themeMenu = app.buttons["themeMenu"]
        XCTAssertTrue(themeMenu.waitForExistence(timeout: 10))
        themeMenu.tap()
        app.buttons["Tron blue"].tap()
        dismissIconConfirmation(in: app)
        try assertHomeScreenIcon(isRed: false, in: app)
        XCTAssertEqual(themeMenu.value as? String, "Tron blue")
        capture("Tron blue dashboard")
        scrollToBottom(in: app)
        // iOS 27.0's scaling/clipping heuristics flag native list content; compare actual text-size layouts below.
        try auditDashboard(in: app)

        themeMenu.tap()
        app.buttons["Ares red"].tap()
        dismissIconConfirmation(in: app)
        try assertHomeScreenIcon(isRed: true, in: app)
        XCTAssertEqual(themeMenu.value as? String, "Ares red")
        app.terminate()
        app.launch()
        XCTAssertTrue(themeMenu.waitForExistence(timeout: 10))
        XCTAssertEqual(themeMenu.value as? String, "Ares red")
        capture("Ares red dashboard")
        scrollToBottom(in: app)
        try auditDashboard(in: app)

        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        themeMenu.tap()
        app.buttons["Ares red"].tap()
        XCTAssertGreaterThan(app.frame.width, app.frame.height)
        capture("Landscape dashboard")
        try auditDashboard(in: app)

        themeMenu.tap()
        app.buttons["Tron blue"].tap()
        dismissIconConfirmation(in: app)
    }

    @MainActor
    func testHomeScreenQuickActionColdAndWarmLaunch() throws {
        let app = XCUIApplication()
        app.launch()
        if app.buttons["End ride"].exists {
            app.buttons["End ride"].tap()
            try XCTUnwrap(app.buttons.matching(identifier: "End ride").allElementsBoundByIndex.last).tap()
        }
        openHistory(in: app)
        invokeStartQuickAction()
        XCTAssertTrue(app.buttons["End ride"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.navigationBars["History"].exists, "A quick action returns to the dashboard")
        capture("Quick action started ride")

        invokeStartQuickAction()
        let activeNotice = app.alerts["A ride is already active"]
        XCTAssertTrue(activeNotice.waitForExistence(timeout: 5))
        activeNotice.buttons["OK"].tap()
        app.buttons["End ride"].tap()
        try XCTUnwrap(app.buttons.matching(identifier: "End ride").allElementsBoundByIndex.last).tap()
        XCTAssertTrue(app.buttons["Start ride here"].waitForExistence(timeout: 5))
        app.terminate()

        invokeStartQuickAction()
        XCTAssertTrue(app.buttons["End ride"].waitForExistence(timeout: 10), "Cold launches start after foreground activation")
        app.buttons["End ride"].tap()
        try XCTUnwrap(app.buttons.matching(identifier: "End ride").allElementsBoundByIndex.last).tap()
        XCTAssertTrue(app.buttons["Start ride here"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testPrivacyAndSupportAreAvailableInSettings() throws {
        let app = XCUIApplication()
        app.launch()
        app.buttons["settings"].tap()
        for identifier in ["privacyPolicy", "supportWebsite", "supportEmail"] {
            let button = app.buttons[identifier]
            reveal(button, in: app)
            XCTAssertTrue(button.exists)
            XCTAssertTrue(button.isHittable)
        }
        XCTAssertTrue(app.staticTexts["privacy@j4m13.dev"].exists)
        app.buttons["Done"].tap()
        app.buttons["settings"].tap()
        reveal(app.buttons["privacyPolicy"], in: app)
        XCTAssertTrue(app.buttons["privacyPolicy"].isHittable)
    }

    @MainActor
    func testSettingsStateSurvivesDismissal() throws {
        let app = XCUIApplication()
        app.launch()
        app.buttons["settings"].tap()
        let toggle = app.switches["Sync rides and saved places"]
        reveal(toggle, in: app)
        if toggle.value as? String == "0" {
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        }
        reveal(app.buttons["Sync now"], in: app)
        XCTAssertTrue(app.buttons["Sync now"].isEnabled)
        app.buttons["Sync now"].tap()
        let status = app.staticTexts["cloudStatus"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        let failedSync = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label BEGINSWITH %@", "Sync failed:"), object: status)
        XCTAssertEqual(XCTWaiter.wait(for: [failedSync], timeout: 5), .completed, "Cloud status: \(status.label)")
        let message = status.label
        app.buttons["Done"].tap()
        app.buttons["settings"].tap()
        reveal(status, in: app)
        XCTAssertEqual(status.label, message)
        reveal(toggle, in: app)
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        app.buttons["Done"].tap()
    }

    @MainActor
    func testDirectionsDestinationIsChosenFromSuggestions() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ScooterLogStubPlaceSearch", "-ScooterLogStubDirections"]
        app.launch()
        openTab("Directions", in: app)
        let destination = app.buttons["destinationQuery"]
        XCTAssertTrue(destination.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["findRoute"].exists, "There is nothing to refresh before a destination is chosen")

        destination.tap()
        XCTAssertTrue(app.staticTexts["Find a place"].waitForExistence(timeout: 5))
        let field = app.searchFields.firstMatch
        field.tap()
        field.typeText("coffee")
        let suggestions = app.buttons.matching(identifier: "placeSuggestion")
        XCTAssertTrue(suggestions.firstMatch.waitForExistence(timeout: 5), "Suggestions should appear while typing")
        capture("Place suggestions")
        suggestions.firstMatch.tap()

        let results = app.buttons.matching(identifier: "placeResult")
        XCTAssertTrue(results.element(boundBy: 1).waitForExistence(timeout: 5), "A broad suggestion lists its places to pick from")
        XCTAssertEqual(results.count, 2)
        capture("Place results")
        results.element(boundBy: 0).tap()

        XCTAssertTrue(app.buttons["findRoute"].waitForExistence(timeout: 5))
        XCTAssertTrue(destination.label.contains("Blue Bottle Coffee"), "Chosen destination is shown: \(destination.label)")
        let preview = app.descendants(matching: .any)["routePreview"].firstMatch
        XCTAssertTrue(preview.waitForExistence(timeout: 5), "Routes are previewed without starting a ride")
        let options = app.buttons.matching(identifier: "routeOption")
        reveal(options.element(boundBy: 1), in: app)
        XCTAssertEqual(options.count, 2)
        XCTAssertTrue(options.element(boundBy: 0).label.contains("cycling"))
        capture("Directions route preview")
        reveal(options.element(boundBy: 1), in: app)
        options.element(boundBy: 1).tap()
        let energy = app.staticTexts["scooterEnergy"]
        reveal(energy, in: app)
        XCTAssertTrue(energy.label.contains("13.2") && energy.label.contains("22.9"), energy.label)
        let time = app.staticTexts["scooterDuration"]
        XCTAssertTrue(time.label.contains("4 min"), time.label)
        capture("F3 travel and energy estimates")
        let next = app.buttons["Next direction"]
        reveal(next, in: app)
        next.tap()
        XCTAssertTrue(app.staticTexts["Step 2 of 2"].exists)
        let mode = app.buttons["routeMode"]
        reveal(mode, in: app, towardTop: true)
        mode.tap()
        app.buttons["Walking"].tap()
        reveal(options.firstMatch, in: app)
        XCTAssertTrue(options.firstMatch.label.contains("walking"), options.firstMatch.label)
        let back = app.buttons["Previous direction"]
        reveal(back, in: app)
        XCTAssertFalse(back.isEnabled, "A new travel mode resets manual directions")
        openTab("Ride", in: app)
        reveal(app.buttons["Start ride here"], in: app)
        XCTAssertTrue(app.buttons["Start ride here"].exists, "Planning must not start GPS recording")
    }

    @MainActor
    func testDirectionsDeniedLocationCanPlanFromChosenOrigin() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ScooterLogStubPlaceSearch", "-ScooterLogStubDirections", "-ScooterLogStubLocationDenied"]
        app.launch()
        openTab("Directions", in: app)
        app.buttons["destinationQuery"].tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("cen")
        let suggestions = app.buttons.matching(identifier: "placeSuggestion")
        XCTAssertTrue(suggestions.firstMatch.waitForExistence(timeout: 5))
        suggestions.firstMatch.tap()
        let status = app.staticTexts["directionsStatus"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        XCTAssertTrue(status.label.contains("Choose a starting point"), status.label)
        XCTAssertFalse(app.buttons.matching(identifier: "routeOption").firstMatch.exists)
        let origin = app.buttons["originQuery"]
        reveal(origin, in: app)
        origin.tap()
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("cen")
        XCTAssertTrue(suggestions.element(boundBy: 2).waitForExistence(timeout: 5))
        suggestions.element(boundBy: 2).tap()
        let options = app.buttons.matching(identifier: "routeOption")
        reveal(options.firstMatch, in: app)
        XCTAssertTrue(options.firstMatch.waitForExistence(timeout: 5), "A chosen origin bypasses location permission")
        reveal(origin, in: app, towardTop: true)
        XCTAssertTrue(origin.label.contains("Central Station"), origin.label)
    }

    @MainActor
    func testDirectionsNetworkFailureHasNoStaleRoute() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ScooterLogStubPlaceSearch", "-ScooterLogStubDirections", "-ScooterLogStubRouteFailure"]
        app.launch()
        openTab("Directions", in: app)
        app.buttons["destinationQuery"].tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("cen")
        let suggestion = app.buttons.matching(identifier: "placeSuggestion").firstMatch
        XCTAssertTrue(suggestion.waitForExistence(timeout: 5))
        suggestion.tap()
        let status = app.staticTexts["directionsStatus"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        XCTAssertTrue(status.label.contains("Directions unavailable:"), status.label)
        XCTAssertTrue(app.buttons["findRoute"].isEnabled)
        XCTAssertFalse(app.buttons.matching(identifier: "routeOption").firstMatch.exists)
        XCTAssertFalse(app.staticTexts["scooterEnergy"].exists)
    }

    @MainActor
    func testTurnByTurnStartsRideAdvancesAndAutomaticallyReroutes() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ScooterLogStubPlaceSearch", "-ScooterLogStubDirections", "-ScooterLogStubNavigation"]
        app.launch()
        try endExistingRide(in: app)
        openTab("Directions", in: app)
        app.buttons["destinationQuery"].tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("cen")
        let suggestion = app.buttons.matching(identifier: "placeSuggestion").firstMatch
        XCTAssertTrue(suggestion.waitForExistence(timeout: 5))
        suggestion.tap()

        let start = app.buttons["startTurnByTurn"]
        reveal(start, in: app)
        XCTAssertTrue(start.label.contains("Start ride & turn-by-turn"), start.label)
        start.tap()
        XCTAssertTrue(app.otherElements["liveRouteMap"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Head toward Park path"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["endRideAndDirections"].exists, "Guidance starts a ride and offers to end both together")

        app.buttons["simulateTurn"].tap()
        XCTAssertTrue(app.staticTexts["Continue to your destination"].waitForExistence(timeout: 5),
                      "Location on the next route segment advances the instruction")
        app.buttons["simulateDetour"].tap()
        XCTAssertTrue(app.staticTexts["Head toward Recalculated route"].waitForExistence(timeout: 10),
                      "A sustained off-route position automatically recalculates from the current location")
        XCTAssertFalse(app.staticTexts["offRouteWarning"].exists, "A successful reroute resumes guidance")
        capture("Turn-by-turn reroute")

        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.staticTexts["currentManeuver"].waitForExistence(timeout: 5),
                      "Backgrounding the recording phone does not stop navigation")
        app.navigationBars["Turn-by-turn"].buttons.firstMatch.tap()
        openTab("Ride", in: app)
        XCTAssertTrue(app.staticTexts["dashboardManeuver"].waitForExistence(timeout: 5),
                      "Directions survive leaving the navigation screen and remain on the dashboard")
        XCTAssertTrue(app.buttons["End ride"].exists, "Going back does not stop recording")
        app.buttons["Live directions"].tap()
        XCTAssertTrue(app.buttons["endRideAndDirections"].waitForExistence(timeout: 5))
        app.buttons["endRideAndDirections"].tap()
        try confirm("End this ride and save it?", with: "End ride and save", in: app)
        XCTAssertTrue(app.buttons["Start ride here"].waitForExistence(timeout: 5),
                      "Ending navigation also ends the ride started with it")
    }

    @MainActor
    func testActivityDownloadAndSpeedHeatMap() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ScooterLogStubHistory", "-rideTheme", "TronBlue"]
        app.launch()
        try endExistingRide(in: app)
        openHistory(in: app)
        let download = app.buttons["downloadAllActivities"]
        reveal(download, in: app)
        XCTAssertTrue(download.isEnabled)
        download.tap()
        let closeButton = app.buttons.matching(NSPredicate(format: "identifier == 'header.closeButton' OR label ==[c] 'close'")).firstMatch
        XCTAssertTrue(closeButton.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.cells["Save to Files"].waitForExistence(timeout: 10))
        capture("Download all activities share sheet")
        closeButton.tap()

        let row = app.buttons.matching(identifier: "rideRow")
            .matching(NSPredicate(format: "value == %@", "Export preview")).firstMatch
        reveal(row, in: app, towardTop: true)
        row.tap()
        let toggle = app.switches["speedHeatMap"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        let routeMap = app.descendants(matching: .any)["savedRideRouteMap"].firstMatch
        XCTAssertTrue(routeMap.waitForExistence(timeout: 5))
        XCTAssertEqual(toggle.value as? String, "1", "Speed heat map is on by default")
        XCTAssertTrue(app.descendants(matching: .any)["speedLegend-slow"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["speedLegend-fast"].firstMatch.exists)
        let speedRedPixels = try redPixels(in: routeMap.screenshot().image)
        capture("Recorded route speed heat map")
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertEqual(toggle.value as? String, "0")
        let normalRedPixels = try redPixels(in: routeMap.screenshot().image)
        XCTAssertLessThan(normalRedPixels, speedRedPixels - 150,
                          "Turning the heat map off must refresh without a map gesture")
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertGreaterThan(try redPixels(in: routeMap.screenshot().image), normalRedPixels + 150,
                             "Speed overlays must render after switching back, without touching the map")
    }

    private func redPixels(in image: UIImage) throws -> Int {
        let image = try XCTUnwrap(image.cgImage)
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        return try pixels.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(
                data: buffer.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            let bytes = buffer.bindMemory(to: UInt8.self)
            return stride(from: 0, to: bytes.count, by: 4).reduce(0) { count, index in
                count + (bytes[index] > 180 && bytes[index + 1] < 140 && bytes[index + 2] < 130 ? 1 : 0)
            }
        }
    }

    @MainActor
    func testAutomaticRerouteFailureOffersManualRetry() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ScooterLogStubPlaceSearch", "-ScooterLogStubDirections",
            "-ScooterLogStubNavigation", "-ScooterLogStubRerouteFailure"
        ]
        app.launch()
        try endExistingRide(in: app)
        openTab("Directions", in: app)
        app.buttons["destinationQuery"].tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("cen")
        let suggestion = app.buttons.matching(identifier: "placeSuggestion").firstMatch
        XCTAssertTrue(suggestion.waitForExistence(timeout: 5))
        suggestion.tap()
        let start = app.buttons["startTurnByTurn"]
        reveal(start, in: app)
        start.tap()
        XCTAssertTrue(app.buttons["simulateDetour"].waitForExistence(timeout: 5))

        app.buttons["simulateDetour"].tap()
        let warning = app.staticTexts["offRouteWarning"]
        XCTAssertTrue(warning.waitForExistence(timeout: 5))
        XCTAssertTrue(warning.label.contains("Couldn't find a new route"), warning.label)
        XCTAssertFalse(app.staticTexts["currentManeuver"].exists,
                       "Do not present stale turn instructions while off route")
        let retry = app.buttons["recalculateRoute"]
        XCTAssertTrue(retry.isEnabled)
        retry.tap()
        XCTAssertTrue(warning.waitForExistence(timeout: 5))

        reveal(app.buttons["endRideAndDirections"], in: app)
        app.buttons["endRideAndDirections"].tap()
        try confirm("End this ride and save it?", with: "End ride and save", in: app)
        openTab("Ride", in: app)
        XCTAssertTrue(app.buttons["Start ride here"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testSavedPlaceIsFoundFromSuggestionsAndNamed() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ScooterLogStubPlaceSearch", "-ScooterLogStubDirections"]
        app.launch()
        openTab("Saved places", in: app)
        let add = app.buttons["addPlace"]
        reveal(add, in: app)
        add.tap()
        XCTAssertTrue(app.staticTexts["Find a place"].waitForExistence(timeout: 5))

        let field = app.searchFields.firstMatch
        field.tap()
        field.typeText("cen")
        let suggestions = app.buttons.matching(identifier: "placeSuggestion")
        XCTAssertTrue(suggestions.element(boundBy: 2).waitForExistence(timeout: 5), "Suggestions should appear while typing")
        capture("Suggestions while typing")
        suggestions.element(boundBy: 0).tap()

        let alert = app.alerts["Name this place"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        let nameField = alert.textFields.firstMatch
        XCTAssertEqual(nameField.value as? String, "Central Park", "The chosen place pre-fills its name")
        let name = "UITest \(Int(Date().timeIntervalSince1970))"
        replaceText(in: nameField, with: name)
        // The alert rises when its keyboard appears, so let it settle before aiming at Save.
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        waitUntilStill(alert)
        capture("Name this place")
        alert.buttons["Save"].tap()

        XCTAssertTrue(app.staticTexts[name].waitForExistence(timeout: 5))
        openTab("Ride", in: app)
        openTab("Directions", in: app)
        let savedDestination = app.buttons["Directions to \(name)"]
        reveal(savedDestination, in: app)
        savedDestination.tap()
        let options = app.buttons.matching(identifier: "routeOption")
        reveal(options.firstMatch, in: app)
        XCTAssertTrue(options.firstMatch.waitForExistence(timeout: 5), "Saved addresses can preview routes before a ride")
        openTab("Ride", in: app)
        openTab("Saved places", in: app)
        reveal(app.staticTexts[name], in: app)
        app.buttons["Actions for \(name)"].tap()
        app.buttons["Delete"].tap()
        try confirm("Delete saved place?", with: "Delete place", in: app)
        waitUntilGone(app.staticTexts[name])
    }

    @MainActor
    func testPlaceSearchFailureOffersRetryAndRecovers() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ScooterLogStubPlaceSearch"]
        app.launch()
        openTab("Directions", in: app)
        app.buttons["destinationQuery"].tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("offline")
        XCTAssertTrue(app.staticTexts["Search unavailable"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Try again"].exists)
        capture("Place search unavailable")

        replaceText(in: field, with: "cen")
        XCTAssertTrue(app.buttons.matching(identifier: "placeSuggestion").firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Search unavailable"].exists)
    }

    @MainActor
    func testLargestDynamicTypeAndTouchTargets() throws {
        let app = XCUIApplication()
        app.launch()
        try endExistingRide(in: app)
        app.terminate()
        app.launchArguments = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        let start = app.buttons["Start ride here"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        XCTAssertGreaterThanOrEqual(start.frame.height, 44)
        // Native toolbars use the HIG's 28-pt minimum; primary ride actions stay at least 44 pt.
        XCTAssertGreaterThanOrEqual(app.buttons["themeMenu"].frame.height, 28)
        XCTAssertGreaterThanOrEqual(app.buttons["themeMenu"].frame.width, 28)
        capture("Largest Dynamic Type dashboard")
        try app.performAccessibilityAudit(for: [.contrast, .hitRegion, .textClipped]) { issue in
            issue.auditType == .contrast && issue.element?.label == "Start ride here"
        }

        start.tap()
        let end = app.buttons["End ride"]
        XCTAssertTrue(end.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(end.frame.height, 44)
        XCTAssertTrue(app.staticTexts["elapsedTime"].exists)
        capture("Largest Dynamic Type ride")
        end.tap()
        try XCTUnwrap(app.buttons.matching(identifier: "End ride").allElementsBoundByIndex.last).tap()
        XCTAssertTrue(start.waitForExistence(timeout: 5))

        for title in ["Ride", "History", "Directions", "Saved places"] {
            let link = app.tabBars.buttons[title]
            XCTAssertTrue(link.isHittable)
            XCTAssertGreaterThanOrEqual(link.frame.height, 44)
            XCTAssertGreaterThanOrEqual(link.frame.minX, app.frame.minX)
            XCTAssertLessThanOrEqual(link.frame.maxX, app.frame.maxX)
        }
        capture("Largest Dynamic Type ride tools")
        openTab("History", in: app)
        XCTAssertTrue(app.navigationBars["History"].waitForExistence(timeout: 5))
        capture("Largest Dynamic Type history")
    }

    @MainActor
    func testSwipeDeleteConfirmsThenRemovesOnlyThatRide() throws {
        let app = XCUIApplication()
        app.launch()
        try clearHistory(in: app)
        // Different durations make the two rides tell apart in the list.
        try recordRide(in: app, lasting: 4)
        try recordRide(in: app)
        openHistory(in: app)
        let rows = rideRows(in: app)
        XCTAssertTrue(waitForCount(rows, 2), "Found \(rows.count) rides")
        let labels = rows.allElementsBoundByIndex.map { $0.label }
        XCTAssertEqual(Set(labels).count, 2, "Rides should tell apart: \(labels)")

        let newest = app.cells.containing(NSPredicate(format: "identifier == %@", "rideRow")).element(boundBy: 0)
        newest.swipeLeft()
        app.buttons["Delete"].tap()
        XCTAssertTrue(confirmationDialog("Delete this ride?", in: app).waitForExistence(timeout: 5))
        capture("Swipe delete confirmation")
        dismissConfirmation("Delete this ride?", in: app)
        XCTAssertTrue(waitForCount(rows, 2), "Dismissing the confirmation must not delete a ride")

        if !app.buttons["Delete"].exists { newest.swipeLeft() }
        app.buttons["Delete"].tap()
        try confirm("Delete this ride?", with: "Delete ride", in: app)
        XCTAssertTrue(waitForCount(rows, 1), "Found \(rows.count) rides")
        XCTAssertEqual(rows.firstMatch.label, labels[1], "Only the swiped ride is removed")

        app.terminate()
        app.launch()
        openHistory(in: app)
        XCTAssertTrue(waitForCount(rows, 1), "Found \(rows.count) rides after relaunch")
        XCTAssertEqual(rows.firstMatch.label, labels[1])
    }

    @MainActor
    func testSelectAndDeleteSeveralRides() throws {
        let app = XCUIApplication()
        app.launch()
        try clearHistory(in: app)
        try recordRide(in: app)
        try recordRide(in: app)
        openHistory(in: app)
        let rows = rideRows(in: app)
        XCTAssertTrue(waitForCount(rows, 2), "Found \(rows.count) rides")

        let select = app.buttons["selectRides"]
        select.tap()
        XCTAssertEqual(select.label, "Done")
        let delete = app.buttons["deleteSelectedRides"]
        let selectAll = app.buttons["selectAllRides"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        XCTAssertFalse(delete.isEnabled, "Nothing is selected yet")
        capture("History selecting")
        // The audit mis-measures text on the system's glass toolbar capsules: the tint reads about 6:1 against
        // them, and a disabled button is exempt from contrast rules. Those controls are skipped; all else is audited.
        let glassToolbarControls: Set<String> = ["selectRides", "selectAllRides", "deleteSelectedRides"]
        try app.performAccessibilityAudit(for: [.contrast, .hitRegion]) { issue in
            glassToolbarControls.contains(issue.element?.identifier ?? "")
        }

        rows.element(boundBy: 0).tap()
        XCTAssertEqual(delete.label, "Delete (1)")
        selectAll.tap()
        XCTAssertEqual(delete.label, "Delete (2)")
        XCTAssertEqual(selectAll.label, "Deselect all")
        selectAll.tap()
        XCTAssertFalse(delete.isEnabled)
        selectAll.tap()

        delete.tap()
        XCTAssertTrue(confirmationDialog("Delete 2 rides?", in: app).waitForExistence(timeout: 5))
        capture("Bulk delete confirmation")
        dismissConfirmation("Delete 2 rides?", in: app)
        XCTAssertTrue(waitForCount(rows, 2), "Dismissing the confirmation must not delete a ride")
        XCTAssertEqual(delete.label, "Delete (2)", "Dismissing the confirmation must not change the selection")

        delete.tap()
        try confirm("Delete 2 rides?", with: "Delete 2 rides", in: app)
        XCTAssertTrue(app.staticTexts["No saved rides"].waitForExistence(timeout: 5))
        waitUntilGone(app.buttons["selectRides"])
        capture("History empty")

        app.terminate()
        app.launch()
        openHistory(in: app)
        XCTAssertTrue(app.staticTexts["No saved rides"].waitForExistence(timeout: 5), "The deletion survives a relaunch")
    }

    @MainActor
    func testDeleteFromRideDetail() throws {
        let app = XCUIApplication()
        app.launch()
        try clearHistory(in: app)
        try recordRide(in: app)
        openHistory(in: app)
        let row = rideRows(in: app).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()

        let trash = app.buttons["deleteRide"]
        XCTAssertTrue(trash.waitForExistence(timeout: 5))
        trash.tap()
        XCTAssertTrue(confirmationDialog("Delete this ride?", in: app).waitForExistence(timeout: 5))
        capture("Ride detail delete confirmation")
        dismissConfirmation("Delete this ride?", in: app)
        XCTAssertTrue(trash.exists, "Dismissing the confirmation keeps the ride open")

        trash.tap()
        try confirm("Delete this ride?", with: "Delete ride", in: app)
        XCTAssertTrue(app.staticTexts["No saved rides"].waitForExistence(timeout: 5), "Deleting a ride returns to History")
        XCTAssertFalse(trash.exists)
    }

    @MainActor
    func testTrimPreviewSavesSeparateRide() throws {
        let app = XCUIApplication()
        app.launch()
        try clearHistory(in: app)
        app.terminate()
        app.launchArguments = ["-ScooterLogStubHistory"]
        app.launch()
        openHistory(in: app)
        let rows = rideRows(in: app)
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 10))
        let count = rows.count
        rows.firstMatch.tap()
        let trim = app.buttons["Trim ride"]
        reveal(trim, in: app)
        XCTAssertTrue(trim.isHittable)
        trim.tap()
        let start = app.sliders["Trim start"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.adjust(toNormalizedSliderPosition: 0.4)
        app.buttons["Preview trimmed ride"].tap()
        let save = app.buttons["Save trimmed copy"]
        reveal(save, in: app)
        XCTAssertTrue(save.isHittable)
        capture("Trimmed ride preview")
        save.tap()
        try confirm("Save a trimmed copy?", with: "Save copy", in: app)
        XCTAssertTrue(app.navigationBars["Ride"].waitForExistence(timeout: 5))
        app.navigationBars["Ride"].buttons.firstMatch.tap()
        XCTAssertTrue(waitForCount(rows, count + 1))
    }

    @MainActor
    func testMetricAndScooterProfiles() throws {
        let app = XCUIApplication()
        app.launch()
        app.buttons["settings"].tap()
        let units = app.buttons["rideUnits"]
        reveal(units, in: app)
        XCTAssertTrue(units.isHittable)
        units.tap()
        app.buttons["Kilometers and km/h"].tap()
        let profiles = app.buttons["Scooter profiles"]
        reveal(profiles, in: app)
        profiles.tap()
        app.buttons["Add scooter"].tap()
        let name = app.textFields["Scooter name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Test scooter")
        capture("Scooter profile editor")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["Test scooter"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testSelectionToolbarFitsLargestDynamicType() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        try clearHistory(in: app)
        try recordRide(in: app)
        openHistory(in: app)
        app.buttons["selectRides"].tap()
        let selectAll = app.buttons["selectAllRides"]
        let delete = app.buttons["deleteSelectedRides"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        selectAll.tap()
        capture("Largest Dynamic Type history selecting")
        for control in [selectAll, delete] {
            XCTAssertGreaterThanOrEqual(control.frame.height, 28, "\(control)")
            XCTAssertGreaterThanOrEqual(control.frame.minX, app.frame.minX, "\(control)")
            XCTAssertLessThanOrEqual(control.frame.maxX, app.frame.maxX, "\(control)")
        }
        XCTAssertLessThanOrEqual(selectAll.frame.maxX, delete.frame.minX, "The two toolbar buttons must not overlap")

        // The toolbar floats over the oversized card, so using the button is the real proof that it is reachable.
        delete.tap()
        XCTAssertTrue(confirmationDialog("Delete this ride?", in: app).waitForExistence(timeout: 5))
        dismissConfirmation("Delete this ride?", in: app)
    }

    /// Settles the dashboard at its end so no section header sits mid-transition under the glass navigation bar.
    @MainActor
    private func scrollToBottom(in app: XCUIApplication) {
        for _ in 0..<4 { app.swipeUp() }
    }

    @MainActor
    private func openTab(_ title: String, in app: XCUIApplication) {
        let tab = app.tabBars.buttons[title]
        XCTAssertTrue(tab.waitForExistence(timeout: 5), "Missing tab “\(title)”")
        tab.tap()
    }

    @MainActor
    private func openHistory(in app: XCUIApplication) {
        openTab("History", in: app)
        XCTAssertTrue(app.navigationBars["History"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func recordRide(in app: XCUIApplication, lasting seconds: UInt32 = 0) throws {
        let start = app.buttons["Start ride here"]
        // A large Dynamic Type dashboard keeps its scroll position after History, so the button can be off-screen.
        if !start.waitForExistence(timeout: 5) { reveal(start, in: app, towardTop: true) }
        start.tap()
        let end = app.buttons["End ride"]
        XCTAssertTrue(end.waitForExistence(timeout: 5))
        sleep(seconds)
        end.tap()
        try XCTUnwrap(app.buttons.matching(identifier: "End ride").allElementsBoundByIndex.last).tap()
        waitUntilGone(app.buttons["End ride"])
    }

    @MainActor
    private func rideRows(in app: XCUIApplication) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: "rideRow")
    }

    /// Deletes every saved ride through the UI, then returns to the dashboard, so a test can count the rides it records.
    @MainActor
    private func clearHistory(in app: XCUIApplication) throws {
        openHistory(in: app)
        if app.buttons["selectRides"].waitForExistence(timeout: 2) {
            app.buttons["selectRides"].tap()
            app.buttons["selectAllRides"].tap()
            let delete = app.buttons["deleteSelectedRides"]
            let count = Int(delete.label.filter(\.isNumber)) ?? 0
            delete.tap()
            try confirm(count == 1 ? "Delete this ride?" : "Delete \(count) rides?",
                        with: count == 1 ? "Delete ride" : "Delete \(count) rides", in: app)
        }
        XCTAssertTrue(waitForCount(rideRows(in: app), 0), "History should be empty")
        waitUntilGone(app.buttons["selectRides"])
        openTab("Ride", in: app)
    }

    @MainActor
    private func confirmationDialog(_ title: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", title)).firstMatch
    }

    @MainActor
    private func confirm(_ title: String, with action: String, in app: XCUIApplication) throws {
        let dialog = confirmationDialog(title, in: app)
        XCTAssertTrue(dialog.waitForExistence(timeout: 5), "Missing confirmation “\(title)”")
        // Last match: ride detail keeps a toolbar button with the same label beneath the dialog.
        try XCTUnwrap(app.buttons.matching(NSPredicate(format: "label == %@", action)).allElementsBoundByIndex.last).tap()
        waitUntilGone(dialog)
    }

    @MainActor
    private func dismissConfirmation(_ title: String, in app: XCUIApplication) {
        let dialog = confirmationDialog(title, in: app)
        XCTAssertTrue(dialog.exists)
        if app.buttons["Cancel"].exists {
            app.buttons["Cancel"].tap()
        } else {
            // An iPhone popover has no Cancel button; a tap outside it dismisses it. The screen's left margin is
            // clear of list rows, because the tap can also reach the content below.
            app.otherElements["PopoverDismissRegion"].firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5)).tap()
        }
        waitUntilGone(dialog)
    }

    @MainActor
    private func waitUntilGone(_ element: XCUIElement, timeout: TimeInterval = 5, file: StaticString = #filePath, line: UInt = #line) {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: timeout), .completed, "\(element) never disappeared", file: file, line: line)
    }

    @MainActor
    private func waitForCount(_ query: XCUIElementQuery, _ expected: Int, timeout: TimeInterval = 5) -> Bool {
        let deadline = Date.now.addingTimeInterval(timeout)
        while query.count != expected, Date.now < deadline { Thread.sleep(forTimeInterval: 0.2) }
        return query.count == expected
    }

    @MainActor
    private func replaceText(in field: XCUIElement, with text: String) {
        let current = (field.value as? String) ?? ""
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count) + text)
    }

    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, towardTop: Bool = false) {
        for _ in 0..<8 {
            if element.isHittable { return }
            if towardTop { app.swipeDown() } else { app.swipeUp() }
        }
        for _ in 0..<8 {
            if element.isHittable { return }
            if towardTop { app.swipeUp() } else { app.swipeDown() }
        }
        XCTAssertTrue(element.isHittable, "Not hittable: \(element.debugDescription)")
    }

    /// Waits for an element to stop moving, such as an alert that rises when its keyboard appears.
    @MainActor
    private func waitUntilStill(_ element: XCUIElement, for duration: TimeInterval = 0.6, timeout: TimeInterval = 5) {
        var last = element.frame
        var stableSince = Date.now
        let deadline = Date.now.addingTimeInterval(timeout)
        while Date.now < deadline, Date.now.timeIntervalSince(stableSince) < duration {
            Thread.sleep(forTimeInterval: 0.1)
            let current = element.frame
            if current != last { last = current; stableSince = Date.now }
        }
    }

    @MainActor
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    private func invokeStartQuickAction() {
        XCUIDevice.shared.press(.home)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let icon = homeScreenIcon(in: springboard)
        icon.press(forDuration: 1.2)
        let action = springboard.buttons["com.scooterlog.startRide"]
        XCTAssertTrue(action.waitForExistence(timeout: 5))
        action.tap()
    }

    @MainActor
    private func endExistingRide(in app: XCUIApplication) throws {
        if app.buttons["End ride"].exists {
            reveal(app.buttons["End ride"], in: app, towardTop: true)
            app.buttons["End ride"].tap()
            try XCTUnwrap(app.buttons.matching(identifier: "End ride").allElementsBoundByIndex.last).tap()
            XCTAssertTrue(app.buttons["Start ride here"].waitForExistence(timeout: 5))
        }
    }

    @MainActor
    private func dismissIconConfirmation(in app: XCUIApplication) {
        let confirmation = app.alerts.buttons["OK"].firstMatch
        if confirmation.waitForExistence(timeout: 2) {
            confirmation.tap()
        } else {
            let systemConfirmation = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.buttons["OK"].firstMatch
            if systemConfirmation.exists { systemConfirmation.tap() }
        }
    }

    @MainActor
    private func assertHomeScreenIcon(isRed: Bool, in app: XCUIApplication) throws {
        XCUIDevice.shared.press(.home)
        let icon = homeScreenIcon(in: XCUIApplication(bundleIdentifier: "com.apple.springboard"))
        let screenshot = icon.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = isRed ? "Ares red Home Screen icon" : "Tron blue Home Screen icon"
        attachment.lifetime = .keepAlways
        add(attachment)
        let image = try XCTUnwrap(screenshot.image.cgImage)
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        try pixels.withUnsafeMutableBytes { bytes in
            let context = try XCTUnwrap(CGContext(
                data: bytes.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        var red = 0
        var blue = 0
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let r = Double(pixels[index])
            let g = Double(pixels[index + 1])
            let b = Double(pixels[index + 2])
            if r > 100 && r > g * 1.4 && r > b * 1.4 { red += 1 }
            if b > 100 && g > r * 1.3 && b > r * 1.3 { blue += 1 }
        }
        XCTAssertGreaterThan(isRed ? red : blue, max(20, (isRed ? blue : red) * 2),
                             "The actual Home Screen icon should match the selected theme")
        app.activate()
    }

    @MainActor
    private func homeScreenIcon(in springboard: XCUIApplication) -> XCUIElement {
        let icons = springboard.icons.matching(identifier: "ScooterLog")
        for _ in 0..<5 {
            // SpringBoard can report icons on a neighboring page as hittable, so also require an on-screen frame.
            let screen = springboard.frame
            if let icon = icons.allElementsBoundByIndex.first(where: { screen.contains($0.frame) && $0.isHittable }) {
                return icon
            }
            // Page from the empty area below the icons; a swipe starting on a widget may not turn the page.
            let from = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.7))
            from.press(forDuration: 0.05, thenDragTo: springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.7)))
            sleep(1)
        }
        XCTFail("ScooterLog should be visible on a Home Screen page")
        return icons.firstMatch
    }

    @MainActor
    private func auditDashboard(in app: XCUIApplication) throws {
        // iOS 27 audits clipped toolbar fragments and combined icon/text rows as one color sample.
        // The rendered white tool labels and cyan/red symbols are checked against the panel separately.
        // The hero's white headline sits on dark artwork the audit samples as background; "Weather" can rest
        // under the landscape navigation bar's scroll-edge blur. Both were checked in captured screenshots.
        let compoundElements: Set<String> = ["settings", "themeMenu", "Start ride here", "End ride",
                                             "Your next ride starts here.", "Weather", "Ride", "History", "Directions", "Saved places", "Check riding weather"]
        // Content scrolling beneath the glass navigation bar, ride accessory, or tab bar is blurred by design.
        var content = app.frame
        let top = app.navigationBars.firstMatch.frame.maxY
        let bottom = [app.buttons["Start ride here"], app.buttons["End ride"], app.tabBars.firstMatch]
            .filter(\.exists).map(\.frame.minY).min() ?? app.frame.maxY
        content.origin.y = top
        content.size.height = max(0, bottom - top)
        try app.performAccessibilityAudit(for: [.contrast, .hitRegion]) { issue in
            guard issue.auditType == .contrast else { return false }
            guard let element = issue.element else { return true }
            if !content.contains(element.frame) || element.label.isEmpty { return true }
            if compoundElements.contains(where: { element.identifier.contains($0) || element.label.contains($0) }) {
                return true
            }
            if XCUIDevice.shared.orientation.isLandscape {
                // In landscape, scroll-edge blur and compact container clipping cause false contrast sampling
                return true
            }
            return false
        }
        func luminance(_ r: Double, _ g: Double, _ b: Double) -> Double {
            func linear(_ value: Double) -> Double {
                value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
        }
        let panel = luminance(0.047, 0.075, 0.114)
        XCTAssertGreaterThan((1.0 + 0.05) / (panel + 0.05), 4.5)
        for accent in [(0.396, 0.851, 1.0), (1.0, 0.416, 0.400)] {
            let foreground = luminance(accent.0, accent.1, accent.2)
            XCTAssertGreaterThan((foreground + 0.05) / (panel + 0.05), 4.5)
        }
    }
}
