import XCTest

final class FiliusPadUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testLaunchesEditorScreen() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.staticTexts["FiliusPad"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.otherElements["canvas.surface"].exists)
        XCTAssertTrue(app.staticTexts["debug.activeTool"].exists)
        XCTAssertTrue(app.staticTexts["debug.zoomScale"].exists)
    }
}
