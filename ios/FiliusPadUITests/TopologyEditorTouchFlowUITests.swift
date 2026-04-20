import Foundation
import XCTest

final class TopologyEditorTouchFlowUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false

        app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()

        _ = requireElement(canvasElement(), named: "canvas.surface")
        _ = requireControl("palette.tool.select")
        _ = requireControl("palette.tool.connect")
        _ = requireControl("palette.tool.place.pc")
        _ = requireControl("palette.tool.place.switch")
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
        let canvas = canvasElement()
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
    private func requireControl(_ identifier: String, timeout: TimeInterval = 5) -> XCUIElement {
        let identified = app.descendants(matching: .any)[identifier]
        let directTimeout = min(timeout, 2)
        if identified.waitForExistence(timeout: directTimeout) {
            return identified
        }

        if let fallbackLabel = fallbackLabel(for: identifier) {
            let scopedPredicate = NSPredicate(
                format: "label == %@ AND identifier != %@",
                fallbackLabel,
                "palette.toolbar.content"
            )
            let scopedFallback = app.buttons.matching(scopedPredicate).firstMatch
            if scopedFallback.waitForExistence(timeout: 2) {
                return scopedFallback
            }

            let broadFallback = app.buttons.matching(NSPredicate(format: "label == %@", fallbackLabel)).firstMatch
            if broadFallback.waitForExistence(timeout: 1) {
                return broadFallback
            }
        }

        XCTFail("Setup failure: missing required accessibility identifier '\(identifier)'")
        return identified
    }

    private func fallbackLabel(for identifier: String) -> String? {
        switch identifier {
        case "palette.tool.select":
            return "Select"
        case "palette.tool.connect":
            return "Connect"
        case "palette.tool.place.pc":
            return "PC"
        case "palette.tool.place.switch":
            return "Switch"
        default:
            return nil
        }
    }

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
        let button = requireControl(identifier)
        button.tap()
    }

    private func canvasElement() -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "canvas.surface").firstMatch
    }

    private func tapCanvas(at normalizedOffset: CGVector) {
        let canvas = requireElement(canvasElement(), named: "canvas.surface")
        canvas.coordinate(withNormalizedOffset: normalizedOffset).tap()
    }

    private func dragOnCanvas(from start: CGVector, to end: CGVector) {
        let canvas = requireElement(canvasElement(), named: "canvas.surface")
        let startCoordinate = canvas.coordinate(withNormalizedOffset: start)
        let endCoordinate = canvas.coordinate(withNormalizedOffset: end)
        startCoordinate.press(forDuration: 0.1, thenDragTo: endCoordinate)
    }

    private func assertDiagnosticEquals(_ identifier: String, expected: String) {
        XCTAssertEqual(label(for: identifier), expected)
    }

    private func label(for identifier: String) -> String {
        let element = diagnosticElement(for: identifier)
        return element.label
    }

    private func diagnosticElement(for identifier: String, timeout: TimeInterval = 5) -> XCUIElement {
        let identified = app.staticTexts[identifier]
        if identified.waitForExistence(timeout: timeout) {
            return identified
        }

        if let prefix = diagnosticPrefixFallback(for: identifier) {
            let predicate = NSPredicate(format: "label BEGINSWITH %@", prefix)
            let fallback = app.staticTexts.matching(predicate).firstMatch
            if fallback.waitForExistence(timeout: 2) {
                return fallback
            }
        }

        XCTFail("Setup failure: missing required accessibility identifier '\(identifier)'")
        return identified
    }

    private func diagnosticPrefixFallback(for identifier: String) -> String? {
        switch identifier {
        case "debug.activeTool":
            return "Tool:"
        case "debug.nodeCount":
            return "Nodes:"
        case "debug.linkCount":
            return "Links:"
        case "debug.selectedNodeCount":
            return "Selected:"
        case "debug.zoomScale":
            return "Zoom:"
        case "debug.lastValidationError":
            return "Last error:"
        case "debug.lastAction":
            return "Last action:"
        case "debug.lastInteractionMode":
            return "Last interaction mode:"
        case "debug.cameraOffset":
            return "Camera:"
        default:
            return nil
        }
    }

    private func zoomValue() -> Double {
        let labelText = label(for: "debug.zoomScale")
            .replacingOccurrences(of: "Zoom: ", with: "")
        return Double(labelText) ?? 0
    }
}
