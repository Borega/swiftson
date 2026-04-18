import CoreGraphics
import Foundation
import XCTest

final class TopologyProjectPersistenceWorkflowUITests: XCTestCase {
    private var app: XCUIApplication!
    private var autosaveFileURLs: [URL] = []

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        app?.terminate()
        app = nil

        for fileURL in autosaveFileURLs {
            try? FileManager.default.removeItem(at: fileURL)
        }
        autosaveFileURLs.removeAll()
    }

    func testAutosaveRoundTripRestoresTopologyAndRuntimeConfiguration() {
        let autosaveURL = makeAutosaveURL()

        app = launchApp(
            autosaveURL: autosaveURL,
            additionalArguments: ["-ui-testing"]
        )

        seedTwoNodeTopologyWithRuntimeConfiguration()

        let saveMarker = requireElement(app.staticTexts["debug.lastPersistenceSaveAt"], named: "debug.lastPersistenceSaveAt")
        waitForLabelNotContaining(saveMarker, forbiddenSubstring: "none", timeout: 4)

        let revisionBeforeRelaunch = persistenceRevisionValue()
        XCTAssertGreaterThan(revisionBeforeRelaunch, 0, "Expected durable edits to advance persistence revision")

        app.terminate()

        app = launchApp(
            autosaveURL: autosaveURL,
            additionalArguments: ["-ui-testing"]
        )

        assertDiagnosticContains("debug.nodeCount", expectedSubstring: "Nodes: 2")
        assertDiagnosticContains("debug.lastPersistenceLoadAt", expectedSubstring: "T")
        assertDiagnosticContains("debug.lastPersistenceError", expectedSubstring: "none")

        tapButton("runtime.control.start")
        tapCanvas(at: CGVector(dx: 0.25, dy: 0.30))
        _ = requireElement(app.otherElements["runtime.device.sheet"], named: "runtime.device.sheet")

        assertTextFieldValue("runtime.device.ip", expected: "192.168.10.10")
        assertTextFieldValue("runtime.device.subnet", expected: "255.255.255.0")

        tapButton("runtime.device.close")

        let revisionAfterRelaunch = persistenceRevisionValue()
        XCTAssertEqual(
            revisionAfterRelaunch,
            revisionBeforeRelaunch,
            "Reloading autosave should restore persisted durable revision baseline"
        )
    }

    func testMalformedAutosaveShowsPersistenceAlertAndKeepsEditorUsable() {
        let autosaveURL = makeAutosaveURL()

        app = launchApp(
            autosaveURL: autosaveURL,
            additionalArguments: ["-ui-testing", "-inject-malformed-autosave"]
        )

        let alert = app.alerts["Persistence error"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5), "Expected persistence error alert when autosave payload is malformed")

        let alertMessage = requireElement(app.staticTexts["persistence.error.alert"], named: "persistence.error.alert")
        XCTAssertTrue(alertMessage.label.contains("Operation: load"))
        XCTAssertTrue(
            alertMessage.label.contains("Code: corruptedPayload") || alertMessage.label.contains("Code: malformedPayload"),
            "Expected deterministic load failure code in alert message"
        )

        alert.buttons["Dismiss"].tap()
        XCTAssertFalse(alert.waitForExistence(timeout: 2), "Persistence alert should dismiss when requested")

        assertDiagnosticContains("debug.lastPersistenceError", expectedSubstring: "none")

        tapButton("palette.tool.place.pc")
        tapCanvas(at: CGVector(dx: 0.45, dy: 0.45))
        assertDiagnosticContains("debug.nodeCount", expectedSubstring: "Nodes: 1")
    }

    // MARK: - Helpers

    @discardableResult
    private func launchApp(autosaveURL: URL, additionalArguments: [String]) -> XCUIApplication {
        if FileManager.default.fileExists(atPath: autosaveURL.path) {
            try? FileManager.default.removeItem(at: autosaveURL)
        }

        autosaveFileURLs.append(autosaveURL)

        let app = XCUIApplication()
        app.launchArguments = additionalArguments
        app.launchEnvironment["FILIUSPAD_AUTOSAVE_FILE"] = autosaveURL.path
        app.launch()

        _ = requireElement(app.otherElements["canvas.surface"], named: "canvas.surface")
        _ = requireElement(app.staticTexts["debug.persistenceRevision"], named: "debug.persistenceRevision")
        _ = requireElement(app.staticTexts["debug.lastPersistenceSaveAt"], named: "debug.lastPersistenceSaveAt")
        _ = requireElement(app.staticTexts["debug.lastPersistenceLoadAt"], named: "debug.lastPersistenceLoadAt")
        _ = requireElement(app.staticTexts["debug.lastPersistenceError"], named: "debug.lastPersistenceError")
        _ = requireElement(app.buttons["palette.tool.place.pc"], named: "palette.tool.place.pc")
        _ = requireElement(app.buttons["palette.tool.place.switch"], named: "palette.tool.place.switch")
        _ = requireElement(app.buttons["runtime.control.start"], named: "runtime.control.start")

        return app
    }

    private func seedTwoNodeTopologyWithRuntimeConfiguration() {
        tapButton("palette.tool.place.pc")
        tapCanvas(at: CGVector(dx: 0.25, dy: 0.30))

        tapButton("palette.tool.place.switch")
        tapCanvas(at: CGVector(dx: 0.70, dy: 0.30))

        tapButton("runtime.control.start")

        tapCanvas(at: CGVector(dx: 0.25, dy: 0.30))
        _ = requireElement(app.otherElements["runtime.device.sheet"], named: "runtime.device.sheet")

        replaceTextField("runtime.device.ip", with: "192.168.10.10")
        replaceTextField("runtime.device.subnet", with: "255.255.255.0")
        tapButton("runtime.device.save")

        tapButton("runtime.device.close")
        XCTAssertFalse(
            app.otherElements["runtime.device.sheet"].exists,
            "Runtime device sheet should dismiss after tapping Done"
        )

        tapButton("runtime.control.stop")
    }

    @discardableResult
    private func requireElement(
        _ element: XCUIElement,
        named identifier: String,
        timeout: TimeInterval = 5
    ) -> XCUIElement {
        XCTAssertTrue(
            element.waitForExistence(timeout: timeout),
            "Missing required accessibility identifier '\(identifier)'"
        )
        return element
    }

    private func tapButton(_ identifier: String) {
        let button = requireElement(app.buttons[identifier], named: identifier)
        XCTAssertTrue(button.isEnabled, "Button '\(identifier)' must be enabled before tapping")
        button.tap()
    }

    private func tapCanvas(at normalizedOffset: CGVector) {
        let canvas = requireElement(app.otherElements["canvas.surface"], named: "canvas.surface")
        canvas.coordinate(withNormalizedOffset: normalizedOffset).tap()
    }

    private func replaceTextField(_ identifier: String, with text: String) {
        let field = requireElement(app.textFields[identifier], named: identifier)
        field.tap()

        if let currentValue = field.value as? String, !currentValue.isEmpty {
            field.press(forDuration: 0.5)
            let selectAll = app.menuItems["Select All"]
            if selectAll.waitForExistence(timeout: 1) {
                selectAll.tap()
            }
            field.typeText(XCUIKeyboardKey.delete.rawValue)
        }

        field.typeText(text)
    }

    private func assertTextFieldValue(_ identifier: String, expected: String) {
        let field = requireElement(app.textFields[identifier], named: identifier)
        let actual = (field.value as? String) ?? ""
        XCTAssertEqual(actual, expected, "Expected '\(identifier)' to restore persisted value")
    }

    private func waitForLabelNotContaining(
        _ element: XCUIElement,
        forbiddenSubstring: String,
        timeout: TimeInterval
    ) {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if !element.label.contains(forbiddenSubstring) {
                return
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }

        XCTFail("Timed out waiting for label '\(element.identifier)' to drop substring '\(forbiddenSubstring)'")
    }

    private func assertDiagnosticContains(_ identifier: String, expectedSubstring: String) {
        let element = requireElement(app.staticTexts[identifier], named: identifier)
        XCTAssertTrue(
            element.label.contains(expectedSubstring),
            "Expected '\(identifier)' to contain '\(expectedSubstring)' but found '\(element.label)'"
        )
    }

    private func persistenceRevisionValue() -> UInt64 {
        let label = requireElement(app.staticTexts["debug.persistenceRevision"], named: "debug.persistenceRevision").label
        let suffix = label.replacingOccurrences(of: "Persistence revision: ", with: "")
        return UInt64(suffix) ?? 0
    }

    private func makeAutosaveURL() -> URL {
        let filename = "TopologyProjectPersistenceWorkflowUITests-\(UUID().uuidString).json"
        return FileManager.default.temporaryDirectory.appendingPathComponent(filename)
    }
}
