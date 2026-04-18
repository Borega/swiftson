import XCTest

final class FiliusPadUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testLaunchesBootstrapScreen() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.staticTexts["FiliusPad"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Topology editor bootstrap ready."].exists)
    }
}
