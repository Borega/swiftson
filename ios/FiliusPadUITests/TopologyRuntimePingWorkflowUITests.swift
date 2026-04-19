import CoreGraphics
import XCTest

final class TopologyRuntimePingWorkflowUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-ui-testing"]
        app.launch()

        _ = canvasSurfaceElement(timeout: 8)
    }

    func testPingSucceedsForReachableConfiguredPeerInRunningSimulation() {
        seedReachableTwoPcTopology()

        tapButton("runtime.control.start")
        assertDiagnosticContains("debug.simulationPhase", expectedSubstring: "running")

        openRuntimeDevice(at: CGVector(dx: 0.25, dy: 0.30))
        saveRuntimeConfiguration(ip: "192.168.10.10", subnet: "255.255.255.0")
        closeRuntimeDeviceSheet()

        openRuntimeDevice(at: CGVector(dx: 0.70, dy: 0.30))
        saveRuntimeConfiguration(ip: "192.168.10.11", subnet: "255.255.255.0")
        closeRuntimeDeviceSheet()

        openRuntimeDevice(at: CGVector(dx: 0.25, dy: 0.30))
        executeCommand("ping 192.168.10.11")

        assertDiagnosticContains("debug.lastPingEvent", expectedSubstring: "pingSucceeded")
        assertDiagnosticContains("debug.lastPingFault", expectedSubstring: "none")
        assertAnyConsoleLineContains("Ping to 192.168.10.11 succeeded")
    }

    func testPingFailurePathReportsDeterministicUnknownTargetDiagnostics() {
        tapButton("palette.tool.place.pc")
        tapCanvas(at: CGVector(dx: 0.35, dy: 0.35))

        tapButton("runtime.control.start")
        assertDiagnosticContains("debug.simulationPhase", expectedSubstring: "running")

        openRuntimeDevice(at: CGVector(dx: 0.35, dy: 0.35))
        saveRuntimeConfiguration(ip: "192.168.20.10", subnet: "255.255.255.0")
        executeCommand("ping 192.168.20.250")

        assertDiagnosticContains("debug.lastPingEvent", expectedSubstring: "pingRejectedUnknownTarget")
        assertDiagnosticContains("debug.lastPingFault", expectedSubstring: "pingTargetUnknown")
        assertAnyConsoleLineContains("Ping failed: pingTargetUnknown")
    }

    func testTraceCommandPublishesPathAwareRuntimeDiagnostics() {
        seedReachableTwoPcTopology()

        tapButton("runtime.control.start")
        assertDiagnosticContains("debug.simulationPhase", expectedSubstring: "running")

        openRuntimeDevice(at: CGVector(dx: 0.25, dy: 0.30))
        saveRuntimeConfiguration(ip: "192.168.10.10", subnet: "255.255.255.0")
        closeRuntimeDeviceSheet()

        openRuntimeDevice(at: CGVector(dx: 0.70, dy: 0.30))
        saveRuntimeConfiguration(ip: "192.168.10.11", subnet: "255.255.255.0")
        closeRuntimeDeviceSheet()

        openRuntimeDevice(at: CGVector(dx: 0.25, dy: 0.30))
        executeCommand("trace 192.168.10.11")

        assertDiagnosticContains("debug.lastRuntimeEvent", expectedSubstring: "traceSucceeded")
        assertDiagnosticContains("debug.lastRuntimeRoute", expectedSubstring: "command=trace")
        assertDiagnosticContains("debug.lastRuntimeRoute", expectedSubstring: "targetIP=192.168.10.11")
        assertDiagnosticContains("debug.lastRuntimeRoute", expectedSubstring: "hops=2")
        assertDiagnosticContains("debug.lastRuntimeRoute", expectedSubstring: "latencyMs=10")
        assertDiagnosticContains("debug.lastRuntimeFault", expectedSubstring: "none")

        assertAnyConsoleLineContains("Trace to 192.168.10.11 succeeded (hops=2, latencyMs=10)")
        assertAnyConsoleLineContains("Path: ")
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
            "Missing required accessibility identifier '\(identifier)'"
        )
        return element
    }

    @discardableResult
    private func requireControl(_ identifier: String, timeout: TimeInterval = 10) -> XCUIElement {
        if let control = locateControl(identifier, timeout: timeout) {
            return control
        }

        XCTFail("Missing required accessibility identifier '\(identifier)'")
        return app.buttons[identifier]
    }

    private func locateControl(_ identifier: String, timeout: TimeInterval) -> XCUIElement? {
        let direct = app.buttons[identifier]
        if direct.waitForExistence(timeout: timeout) {
            return direct
        }

        if let fallbackLabel = controlLabelFallback(for: identifier) {
            let fallbackButton = app.buttons.matching(NSPredicate(format: "label == %@", fallbackLabel)).firstMatch
            if fallbackButton.waitForExistence(timeout: 2) {
                return fallbackButton
            }
        }

        return nil
    }

    private func controlLabelFallback(for identifier: String) -> String? {
        switch identifier {
        case "palette.tool.place.pc":
            return "PC"
        case "palette.tool.place.switch":
            return "Switch"
        case "palette.tool.connect":
            return "Connect"
        case "runtime.control.start":
            return "Start"
        case "runtime.device.save":
            return "Save"
        case "runtime.device.execute":
            return "Run"
        case "runtime.device.close":
            return "Done"
        default:
            return nil
        }
    }

    @discardableResult
    private func requireDiagnosticElement(_ identifier: String, timeout: TimeInterval = 10) -> XCUIElement {
        let identified = app.staticTexts[identifier]
        if identified.waitForExistence(timeout: timeout) {
            return identified
        }

        if let prefix = diagnosticPrefixFallback(for: identifier) {
            let fallback = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
            if fallback.waitForExistence(timeout: 2) {
                return fallback
            }
        }

        XCTFail("Missing required accessibility identifier '\(identifier)'")
        return identified
    }

    private func diagnosticPrefixFallback(for identifier: String) -> String? {
        switch identifier {
        case "debug.simulationPhase":
            return "Simulation phase:"
        case "debug.lastRuntimeEvent":
            return "Last runtime event:"
        case "debug.lastRuntimeRoute":
            return "Last runtime route:"
        case "debug.lastRuntimeFault":
            return "Last runtime fault:"
        case "debug.lastPingEvent":
            return "Last ping event:"
        case "debug.lastPingFault":
            return "Last ping fault:"
        case "debug.openedRuntimeDevice":
            return "Opened runtime device:"
        default:
            return nil
        }
    }

    private func tapButton(_ identifier: String) {
        let button = requireControl(identifier)
        XCTAssertTrue(button.isEnabled, "Button '\(identifier)' must be enabled before tapping")
        button.tap()
    }

    @discardableResult
    private func canvasSurfaceElement(timeout: TimeInterval = 5) -> XCUIElement {
        let canvas = app.otherElements.matching(identifier: "canvas.surface").firstMatch
        XCTAssertTrue(canvas.waitForExistence(timeout: timeout), "Missing required accessibility identifier 'canvas.surface'")
        return canvas
    }

    private func tapCanvas(at normalizedOffset: CGVector) {
        guard normalizedOffset.dx.isFinite, normalizedOffset.dy.isFinite else {
            XCTFail("Canvas tap received non-finite offset: \(normalizedOffset)")
            return
        }

        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 8), "Missing app window for canvas interaction")

        let clampedOffset = CGVector(
            dx: min(max(normalizedOffset.dx, 0.02), 0.98),
            dy: min(max(normalizedOffset.dy, 0.02), 0.98)
        )
        window.coordinate(withNormalizedOffset: clampedOffset).tap()
    }

    private func openRuntimeDevice(at normalizedOffset: CGVector) {
        tapCanvas(at: normalizedOffset)
        _ = requireElement(app.otherElements["runtime.device.sheet"], named: "runtime.device.sheet")
        let openedDiagnostic = label(for: "debug.openedRuntimeDevice")
        XCTAssertFalse(
            openedDiagnostic.hasSuffix("none"),
            "Opening runtime device should populate debug.openedRuntimeDevice"
        )
    }

    private func closeRuntimeDeviceSheet() {
        tapButton("runtime.device.close")
        waitForElementToDisappear(app.otherElements["runtime.device.sheet"], timeout: 3, identifier: "runtime.device.sheet")
        assertDiagnosticContains("debug.openedRuntimeDevice", expectedSubstring: "none")
    }

    private func saveRuntimeConfiguration(ip: String, subnet: String) {
        replaceTextField("runtime.device.ip", with: ip)
        replaceTextField("runtime.device.subnet", with: subnet)
        tapButton("runtime.device.save")
    }

    private func executeCommand(_ command: String) {
        replaceTextField("runtime.device.command", with: command)
        tapButton("runtime.device.execute")
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

    private func assertDiagnosticContains(_ identifier: String, expectedSubstring: String) {
        XCTAssertTrue(
            label(for: identifier).contains(expectedSubstring),
            "Expected '\(identifier)' to contain '\(expectedSubstring)' but found '\(label(for: identifier))'"
        )
    }

    private func label(for identifier: String) -> String {
        let element = requireDiagnosticElement(identifier)
        return element.label
    }

    private func waitForElementToDisappear(_ element: XCUIElement, timeout: TimeInterval, identifier: String) {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if !element.exists {
                return
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }

        XCTFail("Timed out waiting for '\(identifier)' to disappear")
    }

    private func assertAnyConsoleLineContains(_ expectedText: String) {
        let predicate = NSPredicate(format: "identifier BEGINSWITH %@", "runtime.device.console.line.")
        let lines = app.staticTexts.matching(predicate)

        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            for index in 0..<lines.count {
                let line = lines.element(boundBy: index)
                if line.exists, line.label.contains(expectedText) {
                    return
                }
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }

        XCTFail("Expected runtime console to contain '\(expectedText)'")
    }

    private func seedReachableTwoPcTopology() {
        tapButton("palette.tool.place.pc")
        tapCanvas(at: CGVector(dx: 0.25, dy: 0.30))

        tapButton("palette.tool.place.pc")
        tapCanvas(at: CGVector(dx: 0.70, dy: 0.30))

        tapButton("palette.tool.place.switch")
        tapCanvas(at: CGVector(dx: 0.48, dy: 0.62))

        tapButton("palette.tool.connect")
        tapCanvas(at: CGVector(dx: 0.25, dy: 0.30))
        tapCanvas(at: CGVector(dx: 0.48, dy: 0.62))

        tapCanvas(at: CGVector(dx: 0.70, dy: 0.30))
        tapCanvas(at: CGVector(dx: 0.48, dy: 0.62))
    }
}
