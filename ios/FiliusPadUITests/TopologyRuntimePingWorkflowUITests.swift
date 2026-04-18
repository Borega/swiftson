import CoreGraphics
import XCTest

final class TopologyRuntimePingWorkflowUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-ui-testing"]
        app.launch()

        _ = requireElement(app.otherElements["canvas.surface"], named: "canvas.surface")
        _ = requireElement(app.buttons["palette.tool.place.pc"], named: "palette.tool.place.pc")
        _ = requireElement(app.buttons["palette.tool.place.switch"], named: "palette.tool.place.switch")
        _ = requireElement(app.buttons["palette.tool.connect"], named: "palette.tool.connect")
        _ = requireElement(app.buttons["runtime.control.start"], named: "runtime.control.start")
        _ = requireElement(app.staticTexts["debug.simulationPhase"], named: "debug.simulationPhase")
        _ = requireElement(app.staticTexts["debug.lastRuntimeEvent"], named: "debug.lastRuntimeEvent")
        _ = requireElement(app.staticTexts["debug.lastRuntimeRoute"], named: "debug.lastRuntimeRoute")
        _ = requireElement(app.staticTexts["debug.lastRuntimeFault"], named: "debug.lastRuntimeFault")
        _ = requireElement(app.staticTexts["debug.lastPingEvent"], named: "debug.lastPingEvent")
        _ = requireElement(app.staticTexts["debug.lastPingFault"], named: "debug.lastPingFault")
        _ = requireElement(app.staticTexts["debug.openedRuntimeDevice"], named: "debug.openedRuntimeDevice")
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

    private func tapButton(_ identifier: String) {
        let button = requireElement(app.buttons[identifier], named: identifier)
        XCTAssertTrue(button.isEnabled, "Button '\(identifier)' must be enabled before tapping")
        button.tap()
    }

    private func tapCanvas(at normalizedOffset: CGVector) {
        let canvas = requireElement(app.otherElements["canvas.surface"], named: "canvas.surface")
        canvas.coordinate(withNormalizedOffset: normalizedOffset).tap()
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
        XCTAssertFalse(
            app.otherElements["runtime.device.sheet"].exists,
            "Expected runtime device sheet to dismiss after tapping Done"
        )
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
        let element = requireElement(app.staticTexts[identifier], named: identifier)
        return element.label
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
