import CoreGraphics
import Foundation
import XCTest

final class TopologyIntegratedAcceptanceUITests: XCTestCase {
    private enum CanvasPoint {
        static let pc1 = CGVector(dx: 0.12, dy: 0.20)
        static let pc2 = CGVector(dx: 0.22, dy: 0.20)
        static let pc3 = CGVector(dx: 0.32, dy: 0.20)
        static let pc4 = CGVector(dx: 0.62, dy: 0.20)
        static let pc5 = CGVector(dx: 0.72, dy: 0.20)
        static let pc6 = CGVector(dx: 0.82, dy: 0.20)

        static let switch1 = CGVector(dx: 0.22, dy: 0.55)
        static let switch2 = CGVector(dx: 0.42, dy: 0.55)
        static let switch3 = CGVector(dx: 0.62, dy: 0.55)
        static let switch4 = CGVector(dx: 0.78, dy: 0.55)

        static let runtimeDepthPCs: [CGVector] = [
            CGVector(dx: 0.08, dy: 0.18),
            CGVector(dx: 0.16, dy: 0.18),
            CGVector(dx: 0.24, dy: 0.18),
            CGVector(dx: 0.32, dy: 0.18),
            CGVector(dx: 0.40, dy: 0.18),
            CGVector(dx: 0.48, dy: 0.18),
            CGVector(dx: 0.56, dy: 0.18),
            CGVector(dx: 0.64, dy: 0.18),
            CGVector(dx: 0.72, dy: 0.18),
            CGVector(dx: 0.80, dy: 0.18)
        ]

        static let runtimeDepthSwitches: [CGVector] = [
            CGVector(dx: 0.08, dy: 0.62),
            CGVector(dx: 0.16, dy: 0.62),
            CGVector(dx: 0.24, dy: 0.62),
            CGVector(dx: 0.32, dy: 0.62),
            CGVector(dx: 0.40, dy: 0.62),
            CGVector(dx: 0.48, dy: 0.62),
            CGVector(dx: 0.56, dy: 0.62),
            CGVector(dx: 0.64, dy: 0.62),
            CGVector(dx: 0.72, dy: 0.62),
            CGVector(dx: 0.80, dy: 0.62)
        ]
    }

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

    func testIntegratedClassroomFlowWithDiagnosticsAndRelaunchContinuity() {
        let autosaveURL = makeAutosaveURL()

        app = launchApp(
            autosaveURL: autosaveURL,
            clearExistingAutosave: true,
            additionalArguments: ["-ui-testing"]
        )

        seedTenNodeClassroomTopology()

        assertDiagnosticEquals("debug.nodeCount", expected: "Nodes: 10")
        assertDiagnosticEquals("debug.linkCount", expected: "Links: 9")

        tapButton("runtime.control.start")
        waitForDiagnosticContains("debug.simulationPhase", expectedSubstring: "running", timeout: 3)
        assertRuntimeControlState(startEnabled: false, stopEnabled: true)

        assertRuntimeControlsRemainResponsiveAtScale(scaleDescriptor: "~10-node")

        // Boundary condition: repeated runtime sheet open/close under ~10-node load.
        openRuntimeDevice(at: CanvasPoint.pc1)
        closeRuntimeDeviceSheet()
        openRuntimeDevice(at: CanvasPoint.pc2)
        closeRuntimeDeviceSheet()
        openRuntimeDevice(at: CanvasPoint.pc3)
        closeRuntimeDeviceSheet()

        openRuntimeDevice(at: CanvasPoint.pc1)
        saveRuntimeConfiguration(ip: "10.1.0.10", subnet: "255.255.255.0")
        closeRuntimeDeviceSheet()

        openRuntimeDevice(at: CanvasPoint.pc2)
        saveRuntimeConfiguration(ip: "10.1.0.11", subnet: "255.255.255.0")
        closeRuntimeDeviceSheet()

        openRuntimeDevice(at: CanvasPoint.pc1)

        executeCommand("ping 10.1.0.11")
        waitForDiagnosticContains("debug.lastPingEvent", expectedSubstring: "pingSucceeded", timeout: 3)
        assertDiagnosticContains("debug.lastPingFault", expectedSubstring: "none")
        assertAnyConsoleLineContains("Ping to 10.1.0.11 succeeded")

        // Negative test: invalid/unreachable target path must expose deterministic failure diagnostics.
        executeCommand("ping 10.1.0.250")
        waitForDiagnosticContains("debug.lastPingEvent", expectedSubstring: "pingRejectedUnknownTarget", timeout: 3)
        assertDiagnosticContains("debug.lastPingFault", expectedSubstring: "pingTargetUnknown")
        assertAnyConsoleLineContains("Ping failed: pingTargetUnknown")

        // Negative test: malformed command must expose deterministic malformed diagnostics.
        executeCommand("ping")
        waitForDiagnosticContains("debug.lastPingEvent", expectedSubstring: "pingRejectedMalformedCommand", timeout: 3)
        assertDiagnosticContains("debug.lastPingFault", expectedSubstring: "malformedPingCommand")
        assertAnyConsoleLineContains("Ping failed: malformedPingCommand")

        assertRuntimeConsoleCount(atLeast: 6)
        closeRuntimeDeviceSheet()

        waitForDiagnosticNotContaining("debug.lastPersistenceSaveAt", forbiddenSubstring: "none", timeout: 6)
        let lastPersistenceSaveMarker = label(for: "debug.lastPersistenceSaveAt")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: autosaveURL.path),
            "Autosave fixture path should exist after integrated edits and runtime configuration"
        )

        app.terminate()

        app = launchApp(
            autosaveURL: autosaveURL,
            clearExistingAutosave: false,
            additionalArguments: ["-ui-testing"]
        )

        assertDiagnosticEquals("debug.nodeCount", expected: "Nodes: 10")
        waitForDiagnosticNotContaining("debug.lastPersistenceLoadAt", forbiddenSubstring: "none", timeout: 4)
        assertDiagnosticContains("debug.lastPersistenceLoadAt", expectedSubstring: "T")
        assertDiagnosticContains("debug.lastPersistenceError", expectedSubstring: "none")
        XCTAssertEqual(
            label(for: "debug.lastPersistenceSaveAt"),
            lastPersistenceSaveMarker,
            "Relaunch should preserve last persistence save diagnostics from autosave snapshot"
        )

        tapButton("runtime.control.start")
        waitForDiagnosticContains("debug.simulationPhase", expectedSubstring: "running", timeout: 3)

        openRuntimeDevice(at: CanvasPoint.pc1)
        assertTextFieldValue("runtime.device.ip", expected: "10.1.0.10")
        assertTextFieldValue("runtime.device.subnet", expected: "255.255.255.0")

        executeCommand("ping 10.1.0.11")
        waitForDiagnosticContains("debug.lastPingEvent", expectedSubstring: "pingSucceeded", timeout: 3)
        assertDiagnosticContains("debug.lastPingFault", expectedSubstring: "none")
        assertAnyConsoleLineContains("Ping to 10.1.0.11 succeeded")
        assertRuntimeConsoleCount(atLeast: 2)

        closeRuntimeDeviceSheet()
    }

    func testTwentyNodeRuntimeDepthTraceContractsRemainDeterministic() {
        let phaseTag = "[M002/S03/T03 tests]"
        let autosaveURL = makeAutosaveURL()

        app = launchApp(
            autosaveURL: autosaveURL,
            clearExistingAutosave: true,
            additionalArguments: ["-ui-testing"]
        )

        seedTwentyNodeRuntimeDepthTopology()

        XCTAssertEqual(label(for: "debug.nodeCount"), "Nodes: 20", "\(phaseTag) expected deterministic 20-node fixture")
        XCTAssertEqual(label(for: "debug.linkCount"), "Links: 19", "\(phaseTag) expected deterministic 19-link chain")

        tapButton("runtime.control.start")
        waitForDiagnosticContains("debug.simulationPhase", expectedSubstring: "running", timeout: 3)
        assertRuntimeControlState(startEnabled: false, stopEnabled: true)

        assertRuntimeControlsRemainResponsiveAtScale(scaleDescriptor: "~20-node")

        let sourcePoint = CanvasPoint.runtimeDepthPCs[0]
        let targetPoint = CanvasPoint.runtimeDepthSwitches[9]

        openRuntimeDevice(at: sourcePoint)
        saveRuntimeConfiguration(ip: "10.2.0.10", subnet: "255.255.255.0")
        closeRuntimeDeviceSheet()

        openRuntimeDevice(at: targetPoint)
        saveRuntimeConfiguration(ip: "10.2.0.20", subnet: "255.255.255.0")
        closeRuntimeDeviceSheet()

        openRuntimeDevice(at: sourcePoint)
        executeCommand("trace 10.2.0.20")

        waitForDiagnosticContains("debug.lastRuntimeEvent", expectedSubstring: "traceSucceeded", timeout: 3)
        assertDiagnosticContains("debug.lastRuntimeRoute", expectedSubstring: "command=trace")
        assertDiagnosticContains("debug.lastRuntimeRoute", expectedSubstring: "targetIP=10.2.0.20")
        assertDiagnosticContains("debug.lastRuntimeRoute", expectedSubstring: "hops=19")
        assertDiagnosticContains("debug.lastRuntimeRoute", expectedSubstring: "latencyMs=78")
        assertDiagnosticContains("debug.lastRuntimeFault", expectedSubstring: "none")

        assertAnyConsoleLineContains("Trace to 10.2.0.20 succeeded (hops=19, latencyMs=78)")
        assertAnyConsoleLineContains("Path: ")
        assertRuntimeConsoleCount(atLeast: 3)

        closeRuntimeDeviceSheet()
    }

    // MARK: - Helpers

    @discardableResult
    private func launchApp(
        autosaveURL: URL,
        clearExistingAutosave: Bool,
        additionalArguments: [String]
    ) -> XCUIApplication {
        if clearExistingAutosave, FileManager.default.fileExists(atPath: autosaveURL.path) {
            try? FileManager.default.removeItem(at: autosaveURL)
        }

        if !autosaveFileURLs.contains(autosaveURL) {
            autosaveFileURLs.append(autosaveURL)
        }

        let app = XCUIApplication()
        app.launchArguments = additionalArguments
        app.launchEnvironment["FILIUSPAD_AUTOSAVE_FILE"] = autosaveURL.path
        app.launch()

        _ = canvasSurfaceElement(timeout: 10)
        _ = requireControl("palette.tool.place.pc")
        _ = requireControl("palette.tool.place.switch")
        _ = requireControl("palette.tool.connect")
        _ = requireControl("runtime.control.start")
        _ = requireControl("runtime.control.stop")
        _ = requireDiagnosticElement("debug.nodeCount")
        _ = requireDiagnosticElement("debug.linkCount")
        _ = requireDiagnosticElement("debug.simulationPhase")

        return app
    }

    private func seedTenNodeClassroomTopology() {
        tapButton("palette.tool.place.pc")
        tapCanvas(at: CanvasPoint.pc1)
        tapButton("palette.tool.place.pc")
        tapCanvas(at: CanvasPoint.pc2)
        tapButton("palette.tool.place.pc")
        tapCanvas(at: CanvasPoint.pc3)
        tapButton("palette.tool.place.pc")
        tapCanvas(at: CanvasPoint.pc4)
        tapButton("palette.tool.place.pc")
        tapCanvas(at: CanvasPoint.pc5)
        tapButton("palette.tool.place.pc")
        tapCanvas(at: CanvasPoint.pc6)

        tapButton("palette.tool.place.switch")
        tapCanvas(at: CanvasPoint.switch1)
        tapButton("palette.tool.place.switch")
        tapCanvas(at: CanvasPoint.switch2)
        tapButton("palette.tool.place.switch")
        tapCanvas(at: CanvasPoint.switch3)
        tapButton("palette.tool.place.switch")
        tapCanvas(at: CanvasPoint.switch4)

        tapButton("palette.tool.connect")
        connectNodes(from: CanvasPoint.pc1, to: CanvasPoint.switch1)
        connectNodes(from: CanvasPoint.pc2, to: CanvasPoint.switch1)
        connectNodes(from: CanvasPoint.pc3, to: CanvasPoint.switch1)
        connectNodes(from: CanvasPoint.pc4, to: CanvasPoint.switch4)
        connectNodes(from: CanvasPoint.pc5, to: CanvasPoint.switch4)
        connectNodes(from: CanvasPoint.pc6, to: CanvasPoint.switch4)
        connectNodes(from: CanvasPoint.switch1, to: CanvasPoint.switch2)
        connectNodes(from: CanvasPoint.switch2, to: CanvasPoint.switch3)
        connectNodes(from: CanvasPoint.switch3, to: CanvasPoint.switch4)
    }

    private func seedTwentyNodeRuntimeDepthTopology() {
        for point in CanvasPoint.runtimeDepthPCs {
            tapButton("palette.tool.place.pc")
            tapCanvas(at: point)
        }

        for point in CanvasPoint.runtimeDepthSwitches {
            tapButton("palette.tool.place.switch")
            tapCanvas(at: point)
        }

        tapButton("palette.tool.connect")
        connectNodes(from: CanvasPoint.runtimeDepthPCs[0], to: CanvasPoint.runtimeDepthSwitches[0])

        for index in 1..<CanvasPoint.runtimeDepthPCs.count {
            connectNodes(from: CanvasPoint.runtimeDepthSwitches[index - 1], to: CanvasPoint.runtimeDepthPCs[index])
            connectNodes(from: CanvasPoint.runtimeDepthPCs[index], to: CanvasPoint.runtimeDepthSwitches[index])
        }
    }

    private func assertRuntimeControlsRemainResponsiveAtScale(scaleDescriptor: String) {
        let runningTick = simulationTickValue()
        let advancedTick = waitForTickAdvance(from: runningTick, timeout: 2)
        XCTAssertGreaterThan(
            advancedTick,
            runningTick,
            "Simulation tick should advance while running at \(scaleDescriptor)"
        )

        tapButton("runtime.control.stop")
        waitForDiagnosticContains("debug.simulationPhase", expectedSubstring: "stopped", timeout: 3)
        assertRuntimeControlState(startEnabled: true, stopEnabled: false)

        let stoppedTick = simulationTickValue()
        pause(seconds: 0.5)
        XCTAssertEqual(simulationTickValue(), stoppedTick, "Simulation tick should remain frozen while stopped")

        tapButton("runtime.control.start")
        waitForDiagnosticContains("debug.simulationPhase", expectedSubstring: "running", timeout: 3)
        assertRuntimeControlState(startEnabled: false, stopEnabled: true)

        let resumedTick = waitForTickAdvance(from: stoppedTick, timeout: 2)
        XCTAssertGreaterThan(resumedTick, stoppedTick, "Simulation tick should resume after restarting runtime")
    }

    private func connectNodes(from source: CGVector, to destination: CGVector) {
        tapCanvas(at: source)
        tapCanvas(at: destination)
    }

    private func openRuntimeDevice(at normalizedOffset: CGVector) {
        tapCanvas(at: normalizedOffset)
        _ = requireElement(app.otherElements["runtime.device.sheet"], named: "runtime.device.sheet")

        XCTAssertFalse(
            label(for: "debug.openedRuntimeDevice").hasSuffix("none"),
            "Opening runtime device sheet must update debug.openedRuntimeDevice"
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

    private func assertTextFieldValue(_ identifier: String, expected: String) {
        let field = requireElement(app.textFields[identifier], named: identifier)
        let actual = (field.value as? String) ?? ""
        XCTAssertEqual(actual, expected, "Expected text field '\(identifier)' to contain restored value")
    }

    private func assertRuntimeControlState(startEnabled: Bool, stopEnabled: Bool) {
        XCTAssertEqual(
            requireControl("runtime.control.start").isEnabled,
            startEnabled,
            "runtime.control.start enabled state mismatch"
        )
        XCTAssertEqual(
            requireControl("runtime.control.stop").isEnabled,
            stopEnabled,
            "runtime.control.stop enabled state mismatch"
        )
    }

    private func assertRuntimeConsoleCount(atLeast minimum: Int) {
        let count = diagnosticIntegerValue(
            for: "debug.runtimeConsoleCount",
            prefix: "Opened runtime console entries: "
        )

        XCTAssertNotNil(count, "Expected debug.runtimeConsoleCount to expose an integer payload")
        XCTAssertGreaterThanOrEqual(
            count ?? 0,
            minimum,
            "Expected debug.runtimeConsoleCount to be at least \(minimum)"
        )
    }

    private func assertAnyConsoleLineContains(_ expectedText: String) {
        let predicate = NSPredicate(format: "identifier BEGINSWITH %@", "runtime.device.console.line.")
        let lines = app.staticTexts.matching(predicate)
        let deadline = Date().addingTimeInterval(3)

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

    private func waitForDiagnosticContains(
        _ identifier: String,
        expectedSubstring: String,
        timeout: TimeInterval
    ) {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if label(for: identifier).contains(expectedSubstring) {
                return
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }

        XCTFail("Timed out waiting for \(identifier) to contain '\(expectedSubstring)'")
    }

    private func waitForDiagnosticNotContaining(
        _ identifier: String,
        forbiddenSubstring: String,
        timeout: TimeInterval
    ) {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if !label(for: identifier).contains(forbiddenSubstring) {
                return
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }

        XCTFail("Timed out waiting for \(identifier) to stop containing '\(forbiddenSubstring)'")
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

    private func diagnosticIntegerValue(for identifier: String, prefix: String) -> Int? {
        let text = label(for: identifier)
        let suffix = text.replacingOccurrences(of: prefix, with: "")
        return Int(suffix)
    }

    private func pause(seconds: TimeInterval) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
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
        case "runtime.control.stop":
            return "Stop"
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
        case "debug.nodeCount":
            return "Nodes:"
        case "debug.linkCount":
            return "Links:"
        case "debug.simulationPhase":
            return "Simulation phase:"
        case "debug.simulationTick":
            return "Simulation tick:"
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
        case "debug.runtimeConsoleCount":
            return "Opened runtime console entries:"
        case "debug.lastPersistenceSaveAt":
            return "Last persistence save:"
        case "debug.lastPersistenceLoadAt":
            return "Last persistence load:"
        case "debug.lastPersistenceError":
            return "Last persistence error:"
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

    private func makeAutosaveURL() -> URL {
        let filename = "TopologyIntegratedAcceptanceUITests-\(UUID().uuidString).json"
        return FileManager.default.temporaryDirectory.appendingPathComponent(filename)
    }
}
