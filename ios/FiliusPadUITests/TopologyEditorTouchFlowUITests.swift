import XCTest

final class TopologyEditorTouchFlowUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false

        app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()

        _ = requireElement(app.otherElements["canvas.surface"], named: "canvas.surface")
        _ = requireElement(app.descendants(matching: .any)["palette.tool.select"], named: "palette.tool.select")
        _ = requireElement(app.descendants(matching: .any)["palette.tool.connect"], named: "palette.tool.connect")
        _ = requireElement(app.descendants(matching: .any)["palette.tool.place.pc"], named: "palette.tool.place.pc")
        _ = requireElement(app.descendants(matching: .any)["palette.tool.place.switch"], named: "palette.tool.place.switch")
    }

    func testFullTouchFlowMaintainsCoherentDiagnostics() {
        assertDiagnosticEquals("debug.nodeCount", expected: "Nodes: 0")
        assertDiagnosticEquals("debug.linkCount", expected: "Links: 0")
        assertDiagnosticEquals("debug.selectedNodeCount", expected: "Selected: 0")
        assertDiagnosticEquals("debug.lastValidationError", expected: "Last error: none")

        // Place first PC.
        tapButton("palette.tool.place.pc")
        XCTAssertEqual(label(for: "debug.lastInteractionMode"), "Last interaction mode: paletteTap:place:pc")
        tapCanvas(at: CGVector(dx: 0.25, dy: 0.30))
        XCTAssertEqual(label(for: "debug.lastInteractionMode"), "Last interaction mode: canvasTap:place:pc")
        assertDiagnosticEquals("debug.nodeCount", expected: "Nodes: 1")
        assertDiagnosticEquals("debug.selectedNodeCount", expected: "Selected: 1")
        assertDiagnosticEquals("debug.activeTool", expected: "Tool: select")

        // Place second PC.
        tapButton("palette.tool.place.pc")
        tapCanvas(at: CGVector(dx: 0.65, dy: 0.30))
        assertDiagnosticEquals("debug.nodeCount", expected: "Nodes: 2")
        assertDiagnosticEquals("debug.selectedNodeCount", expected: "Selected: 1")

        // Place switch endpoint.
        tapButton("palette.tool.place.switch")
        tapCanvas(at: CGVector(dx: 0.45, dy: 0.60))
        assertDiagnosticEquals("debug.nodeCount", expected: "Nodes: 3")

        // Negative/error path: invalid PC-to-PC connect must surface diagnostic error.
        tapButton("palette.tool.connect")
        tapCanvas(at: CGVector(dx: 0.25, dy: 0.30))
        tapCanvas(at: CGVector(dx: 0.65, dy: 0.30))
        assertDiagnosticEquals("debug.lastValidationError", expected: "Last error: incompatibleEndpoint")
        assertDiagnosticEquals("debug.linkCount", expected: "Links: 0")

        // Complete valid connect using current pending source and switch target.
        tapCanvas(at: CGVector(dx: 0.45, dy: 0.60))
        assertDiagnosticEquals("debug.lastValidationError", expected: "Last error: none")
        assertDiagnosticEquals("debug.linkCount", expected: "Links: 1")
        assertDiagnosticEquals("debug.selectedNodeCount", expected: "Selected: 2")

        // Select and move one node.
        tapButton("palette.tool.select")
        XCTAssertEqual(label(for: "debug.lastInteractionMode"), "Last interaction mode: paletteTap:select")
        tapCanvas(at: CGVector(dx: 0.45, dy: 0.60))
        assertDiagnosticEquals("debug.selectedNodeCount", expected: "Selected: 1")
        dragOnCanvas(from: CGVector(dx: 0.45, dy: 0.60), to: CGVector(dx: 0.68, dy: 0.48))
        XCTAssertEqual(label(for: "debug.lastAction"), "Last action: moveSelectedNodes")

        // Boundary condition: select empty area then drag to pan near limits.
        tapCanvas(at: CGVector(dx: 0.08, dy: 0.92))
        assertDiagnosticEquals("debug.selectedNodeCount", expected: "Selected: 0")
        let cameraBeforePan = label(for: "debug.cameraOffset")
        dragOnCanvas(from: CGVector(dx: 0.95, dy: 0.95), to: CGVector(dx: 0.05, dy: 0.05))
        let cameraAfterPan = label(for: "debug.cameraOffset")
        XCTAssertNotEqual(cameraAfterPan, cameraBeforePan, "Expected pan gesture to update camera offset")

        // Boundary condition: zoom gestures should stay clamped in viewport bounds.
        let canvas = app.otherElements["canvas.surface"]
        canvas.pinch(withScale: 8.0, velocity: 2.0)
        canvas.pinch(withScale: 0.02, velocity: -2.0)

        let zoom = zoomValue()
        XCTAssertGreaterThanOrEqual(zoom, 0.5)
        XCTAssertLessThanOrEqual(zoom, 4.0)
    }

    func testMissingIdentifiersAreDetectedExplicitly() {
        let missingPaletteTool = app.descendants(matching: .any)["palette.tool.place.router"]
        XCTAssertFalse(
            missingPaletteTool.waitForExistence(timeout: 1),
            "Malformed input guard failed: unexpected element resolved for missing identifier"
        )

        let staleCanvasReference = app.descendants(matching: .any)["canvas.surface.stale"]
        XCTAssertFalse(
            staleCanvasReference.waitForExistence(timeout: 1),
            "Malformed input guard failed: stale canvas identifier should not resolve"
        )
    }

    override func tearDownWithError() throws {
        app?.terminate()
        app = nil
    }

    // MARK: - Helpers

    @discardableResult
    private func requireElement(
        _ element: XCUIElement,
        named identifier: String,
        timeout: TimeInterval = 5
    ) -> XCUIElement {
        XCTAssertTrue(
            element.waitForExistence(timeout: timeout),
            "Setup failure: missing required accessibility identifier '\(identifier)'"
        )
        return element
    }

    private func tapButton(_ identifier: String) {
        let button = requireElement(app.descendants(matching: .any)[identifier], named: identifier)
        button.tap()
    }

    private func tapCanvas(at normalizedOffset: CGVector) {
        let canvas = requireElement(app.otherElements["canvas.surface"], named: "canvas.surface")
        canvas.coordinate(withNormalizedOffset: normalizedOffset).tap()
    }

    private func dragOnCanvas(from start: CGVector, to end: CGVector) {
        let canvas = requireElement(app.otherElements["canvas.surface"], named: "canvas.surface")
        let startCoordinate = canvas.coordinate(withNormalizedOffset: start)
        let endCoordinate = canvas.coordinate(withNormalizedOffset: end)
        startCoordinate.press(forDuration: 0.1, thenDragTo: endCoordinate)
    }

    private func assertDiagnosticEquals(_ identifier: String, expected: String) {
        XCTAssertEqual(label(for: identifier), expected)
    }

    private func label(for identifier: String) -> String {
        let element = requireElement(app.staticTexts[identifier], named: identifier)
        return element.label
    }

    private func zoomValue() -> Double {
        let labelText = label(for: "debug.zoomScale")
            .replacingOccurrences(of: "Zoom: ", with: "")
        return Double(labelText) ?? 0
    }
}
