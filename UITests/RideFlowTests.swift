import XCTest

final class RideFlowTests: XCTestCase {
    @MainActor
    func testStartRecoverEndAndHistory() throws {
        let app = XCUIApplication()
        app.launch()
        let start = app.buttons["Start ride here"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        start.tap()
        let end = app.buttons["End ride"]
        XCTAssertTrue(end.waitForExistence(timeout: 5))
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
}
