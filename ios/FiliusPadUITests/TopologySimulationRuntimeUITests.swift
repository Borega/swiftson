import CoreGraphics
import XCTest

final class TopologySimulationRuntimeUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-ui-testing"]
        app.launch()

        _ = requireElement(app.buttons["runtime.control.start"], named: "runtime.control.start")
        _ = requireElement(app.buttons["runtime.control.stop"], named: "runtime.control.stop")
        _ = requireElement(app.staticTexts["debug.simulationPhase"], named: "debug.simulationPhase")
        _ = requireElement(app.staticTexts["debug.simulationTick"], named: "debug.simulationTick")
        _ = requireElement(app.staticTexts["debug.lastRuntimeEvent"], named: "debug.lastRuntimeEvent")
        _ = requireElement(app.staticTexts["debug.lastPingEvent"], named: "debug.lastPingEvent")
        _ = requireElement(app.staticTexts["debug.lastPingFault"], named: "debug.lastPingFault")
    }

    func testRuntimeStartStopAdvancesAndFreezesTick() {
        assertDiagnosticEquals("debug.simulationPhase", expected: "Simulation phase: stopped")
        XCTAssertTrue(requireElement(app.buttons["runtime.control.start"], named: "runtime.control.start").isEnabled)
        XCTAssertFalse(requireElement(app.buttons["runtime.control.stop"], named: "runtime.control.stop").isEnabled)

        let baselineTick = simulationTickValue()

        tapButton("runtime.control.start")
        assertDiagnosticEquals("debug.simulationPhase", expected: "Simulation phase: running")
        XCTAssertFalse(requireElement(app.buttons["runtime.control.start"], named: "runtime.control.start").isEnabled)
        XCTAssertTrue(requireElement(app.buttons["runtime.control.stop"], named: "runtime.control.stop").isEnabled)

        let advancedTick = waitForTickAdvance(from: baselineTick, timeout: 3)
        XCTAssertGreaterThan(advancedTick, baselineTick, "Expected simulation tick to advance while running")

        tapButton("runtime.control.stop")
        assertDiagnosticEquals("debug.simulationPhase", expected: "Simulation phase: stopped")
        XCTAssertTrue(requireElement(app.buttons["runtime.control.start"], named: "runtime.control.start").isEnabled)
        XCTAssertFalse(requireElement(app.buttons["runtime.control.stop"], named: "runtime.control.stop").isEnabled)

        let stoppedTick = simulationTickValue()
        XCTAssertGreaterThanOrEqual(stoppedTick, advancedTick)
        pause(seconds: 0.6)
        XCTAssertEqual(simulationTickValue(), stoppedTick, "Stopping should freeze tick progression")

        XCTAssertTrue(
            label(for: "debug.lastRuntimeEvent").contains("simulationStopped"),
            "Expected runtime event diagnostics to expose simulationStopped after stop"
        )
    }

    func testRuntimeControlsRemainCoherentAcrossInvalidAndRapidTransitions() {
        assertDiagnosticEquals("debug.simulationPhase", expected: "Simulation phase: stopped")
        XCTAssertFalse(requireElement(app.buttons["runtime.control.stop"], named: "runtime.control.stop").isEnabled)

        let initialTick = simulationTickValue()
        pause(seconds: 0.4)
        XCTAssertEqual(simulationTickValue(), initialTick, "Tick must not advance while stopped")

        var previousTick = initialTick

        for _ in 0..<3 {
            tapButton("runtime.control.start")
            assertDiagnosticEquals("debug.simulationPhase", expected: "Simulation phase: running")

            let progressedTick = waitForTickAdvance(from: previousTick, timeout: 2)
            XCTAssertGreaterThan(progressedTick, previousTick)

            tapButton("runtime.control.stop")
            assertDiagnosticEquals("debug.simulationPhase", expected: "Simulation phase: stopped")

            let stoppedTick = simulationTickValue()
            pause(seconds: 0.3)
            XCTAssertEqual(simulationTickValue(), stoppedTick, "Tick must remain frozen after each stop")

            previousTick = stoppedTick
            XCTAssertTrue(requireElement(app.buttons["runtime.control.start"], named: "runtime.control.start").isEnabled)
            XCTAssertFalse(requireElement(app.buttons["runtime.control.stop"], named: "runtime.control.stop").isEnabled)
        }
    }

    func testRunningTapOpensRuntimeDeviceSheetAndReportsMalformedPingDiagnostics() {
        tapButton("palette.tool.place.pc")
        tapCanvas(at: CGVector(dx: 0.35, dy: 0.35))

        tapButton("runtime.control.start")
        assertDiagnosticEquals("debug.simulationPhase", expected: "Simulation phase: running")

        tapCanvas(at: CGVector(dx: 0.35, dy: 0.35))
        _ = requireElement(app.otherElements["runtime.device.sheet"], named: "runtime.device.sheet")

        replaceTextField("runtime.device.ip", with: "192.168.0.10")
        replaceTextField("runtime.device.subnet", with: "255.255.255.0")
        tapButton("runtime.device.save")

        XCTAssertTrue(
            label(for: "debug.lastRuntimeEvent").contains("runtimeDeviceIPSaved"),
            "Saving IP should emit runtimeDeviceIPSaved diagnostics"
        )

        replaceTextField("runtime.device.command", with: "ping")
        tapButton("runtime.device.execute")

        XCTAssertTrue(
            label(for: "debug.lastPingEvent").contains("pingRejectedMalformedCommand"),
            "Malformed ping command should emit pingRejectedMalformedCommand diagnostics"
        )
        XCTAssertTrue(
            label(for: "debug.lastPingFault").contains("malformedPingCommand"),
            "Malformed ping command should expose deterministic fault code"
        )

        tapButton("runtime.device.close")
        XCTAssertFalse(
            app.otherElements["runtime.device.sheet"].exists,
            "Runtime sheet should close after tapping Done"
        )
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

    private func assertDiagnosticEquals(_ identifier: String, expected: String) {
        XCTAssertEqual(label(for: identifier), expected)
    }

    private func label(for identifier: String) -> String {
        let element = requireElement(app.staticTexts[identifier], named: identifier)
        return element.label
    }

    private func simulationTickValue() -> UInt64 {
        let labelText = label(for: "debug.simulationTick")
            .replacingOccurrences(of: "Simulation tick: ", with: "")
        return UInt64(labelText) ?? 0
    }

    private func waitForTickAdvance(from baseline: UInt64, timeout: TimeInterval) -> UInt64 {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            let current = simulationTickValue()
            if current > baseline {
                return current
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }

        return simulationTickValue()
    }

    private func pause(seconds: TimeInterval) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }
}
