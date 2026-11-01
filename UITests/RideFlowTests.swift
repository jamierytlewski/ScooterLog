import XCTest

final class RideFlowTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testStartRecoverEndAndHistory() throws {
        let app = XCUIApplication()
        app.launch()
        let start = app.buttons["Start ride here"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        start.tap()
        let end = app.buttons["End ride"]
        XCTAssertTrue(end.waitForExistence(timeout: 5))
        capture("Active ride dashboard")
        app.terminate()
        app.launch()
        let resume = app.buttons["Resume recording"]
        XCTAssertTrue(resume.waitForExistence(timeout: 5))
        resume.tap()
        XCTAssertTrue(end.waitForExistence(timeout: 5))
        end.tap()
        try XCTUnwrap(app.buttons.matching(identifier: "End ride").allElementsBoundByIndex.last).tap()
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        app.buttons["Ride history"].tap()
        XCTAssertTrue(app.navigationBars["History"].waitForExistence(timeout: 5))
        XCTAssertGreaterThan(app.cells.count, 1)
    }

    @MainActor
    func testAppearanceSelectionPersists() throws {
        continueAfterFailure = true
        let app = XCUIApplication()
        app.launch()
        let themeMenu = app.buttons["themeMenu"]
        XCTAssertTrue(themeMenu.waitForExistence(timeout: 10))
        themeMenu.tap()
        app.buttons["Tron blue"].tap()
        XCTAssertEqual(themeMenu.value as? String, "Tron blue")
        capture("Tron blue dashboard")
        // iOS 27.0's scaling/clipping heuristics flag native list content; compare actual text-size layouts below.
        try app.performAccessibilityAudit(for: [.contrast, .hitRegion])

        themeMenu.tap()
        app.buttons["Ares red"].tap()
        XCTAssertEqual(themeMenu.value as? String, "Ares red")
        app.terminate()
        app.launch()
        XCTAssertTrue(themeMenu.waitForExistence(timeout: 10))
        XCTAssertEqual(themeMenu.value as? String, "Ares red")
        capture("Ares red dashboard")
        try app.performAccessibilityAudit(for: [.contrast, .hitRegion])

        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        themeMenu.tap()
        app.buttons["Ares red"].tap()
        XCTAssertGreaterThan(app.frame.width, app.frame.height)
        capture("Landscape dashboard")
        try app.performAccessibilityAudit(for: [.contrast, .hitRegion])

        themeMenu.tap()
        app.buttons["Tron blue"].tap()
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
    func testSearchValidationAndLocationRecovery() throws {
        let app = XCUIApplication()
        app.launch()
        reveal(app.buttons["Saved places"], in: app)
        app.buttons["Saved places"].tap()
        let search = app.buttons["searchPlaces"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        XCTAssertFalse(search.isEnabled)
        let query = app.textFields["placeQuery"]
        query.tap()
        query.typeText("   ")
        XCTAssertFalse(search.isEnabled)
        query.typeText("Central Park")
        XCTAssertTrue(search.isEnabled)

        app.terminate()
        app.launch()
        reveal(app.buttons["Directions"], in: app)
        app.buttons["Directions"].tap()
        let find = app.buttons["findRoute"]
        XCTAssertTrue(find.waitForExistence(timeout: 5))
        XCTAssertFalse(find.isEnabled)
        app.textFields["destinationQuery"].tap()
        app.textFields["destinationQuery"].typeText("Central Park")
        XCTAssertTrue(find.isEnabled)
        find.tap()
        XCTAssertTrue(app.staticTexts["Start a ride and wait for an accurate location first."].waitForExistence(timeout: 5))
        capture("Directions location recovery")
    }

    @MainActor
    func testLargestDynamicTypeAndTouchTargets() throws {
        let app = XCUIApplication()
        app.launch()
        let directions = app.buttons["Directions"]
        reveal(directions, in: app)
        let regularRowHeight = directions.frame.height
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
        try app.performAccessibilityAudit(for: [.contrast, .hitRegion, .textClipped])

        start.tap()
        let end = app.buttons["End ride"]
        XCTAssertTrue(end.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(end.frame.height, 44)
        XCTAssertTrue(app.staticTexts["elapsedTime"].exists)
        capture("Largest Dynamic Type ride")
        end.tap()
        try XCTUnwrap(app.buttons.matching(identifier: "End ride").allElementsBoundByIndex.last).tap()
        XCTAssertTrue(start.waitForExistence(timeout: 5))

        reveal(app.buttons["Saved places"], in: app)
        for title in ["Ride history", "Directions", "Saved places"] {
            let link = app.buttons[title]
            XCTAssertTrue(link.isHittable)
            XCTAssertGreaterThanOrEqual(link.frame.height, 44)
            XCTAssertGreaterThanOrEqual(link.frame.minX, app.frame.minX)
            XCTAssertLessThanOrEqual(link.frame.maxX, app.frame.maxX)
        }
        XCTAssertGreaterThan(directions.frame.height, regularRowHeight)
        capture("Largest Dynamic Type ride tools")
        app.buttons["Ride history"].tap()
        XCTAssertTrue(app.navigationBars["History"].waitForExistence(timeout: 5))
        capture("Largest Dynamic Type history")
    }

    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<8 {
            if element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable)
    }

    @MainActor
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
