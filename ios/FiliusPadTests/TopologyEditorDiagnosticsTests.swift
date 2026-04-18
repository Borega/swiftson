import CoreGraphics
import XCTest
@testable import FiliusPad

final class TopologyEditorDiagnosticsTests: XCTestCase {
    func testRejectedConnectAttemptExposesInspectableValidationCode() {
        var state = TopologyEditorState()

        let firstPCNodeID = addNode(kind: .pc, at: CGPoint(x: 40, y: 40), to: &state)
        let secondPCNodeID = addNode(kind: .pc, at: CGPoint(x: 160, y: 40), to: &state)

        TopologyEditorReducer.reduce(
            state: &state,
            action: .startConnection(nodeID: firstPCNodeID, portID: nil)
        )
        TopologyEditorReducer.reduce(
            state: &state,
            action: .completeConnection(nodeID: secondPCNodeID, portID: nil)
        )

        XCTAssertEqual(state.lastValidationError, .incompatibleEndpoint)
        XCTAssertEqual(state.lastValidationError?.rawValue, "incompatibleEndpoint")
        XCTAssertEqual(state.lastAction, "completeConnection")
        XCTAssertNotNil(state.lastActionAt)
    }

    func testDuplicateConnectAttemptKeepsGraphUnchangedAndTracksActionMetadata() {
        var state = TopologyEditorState()

        let sourceNodeID = addNode(kind: .pc, at: CGPoint(x: 10, y: 10), to: &state)
        let targetNodeID = addNode(kind: .networkSwitch, at: CGPoint(x: 220, y: 10), to: &state)

        connect(sourceNodeID, targetNodeID, state: &state)
        let snapshot = state.graph

        TopologyEditorReducer.reduce(
            state: &state,
            action: .startConnection(nodeID: targetNodeID, portID: nil)
        )
        TopologyEditorReducer.reduce(
            state: &state,
            action: .completeConnection(nodeID: sourceNodeID, portID: nil)
        )

        XCTAssertEqual(state.graph, snapshot)
        XCTAssertEqual(state.lastValidationError, .duplicateLink)
        XCTAssertEqual(state.lastValidationError?.rawValue, "duplicateLink")
        XCTAssertEqual(state.lastAction, "completeConnection")
        XCTAssertNotNil(state.lastActionAt)
    }

    func testSuccessfulConnectClearsPreviousValidationErrorAndKeepsInspectableCode() {
        var state = TopologyEditorState()

        let firstPCNodeID = addNode(kind: .pc, at: CGPoint(x: 40, y: 40), to: &state)
        let secondPCNodeID = addNode(kind: .pc, at: CGPoint(x: 160, y: 40), to: &state)
        let switchNodeID = addNode(kind: .networkSwitch, at: CGPoint(x: 100, y: 140), to: &state)

        TopologyEditorReducer.reduce(
            state: &state,
            action: .startConnection(nodeID: firstPCNodeID, portID: nil)
        )
        TopologyEditorReducer.reduce(
            state: &state,
            action: .completeConnection(nodeID: secondPCNodeID, portID: nil)
        )

        XCTAssertEqual(state.lastValidationError, .incompatibleEndpoint)
        XCTAssertEqual(state.lastValidationError?.rawValue, "incompatibleEndpoint")

        TopologyEditorReducer.reduce(
            state: &state,
            action: .completeConnection(nodeID: switchNodeID, portID: nil)
        )

        XCTAssertNil(state.lastValidationError)
        XCTAssertEqual(state.graph.links.count, 1)
        XCTAssertEqual(state.lastAction, "completeConnection")
        XCTAssertNotNil(state.lastActionAt)
    }

    func testSuccessfulActionClearsPreviousValidationError() {
        var state = TopologyEditorState()

        TopologyEditorReducer.reduce(state: &state, action: .selectNodes(in: nil))
        XCTAssertEqual(state.lastValidationError, .malformedActionPayload)

        let nodeID = addNode(kind: .pc, at: CGPoint(x: 10, y: 10), to: &state)
        TopologyEditorReducer.reduce(state: &state, action: .selectSingleNode(nodeID: nodeID))

        XCTAssertNil(state.lastValidationError)
        XCTAssertEqual(state.lastAction, "selectSingleNode")
        XCTAssertNotNil(state.lastActionAt)
    }

    func testRuntimeFaultIsInspectableAndPreservesPhaseAndTick() {
        var state = TopologyEditorState()

        TopologyEditorReducer.reduce(state: &state, action: .startSimulation)
        TopologyEditorReducer.reduce(state: &state, action: .simulationTick(step: 2))

        let phaseSnapshot = state.simulationPhase
        let tickSnapshot = state.simulationTick

        TopologyEditorReducer.reduce(
            state: &state,
            action: .simulationFault(code: "runtimeDependencyDown", message: "scheduler queue unavailable")
        )

        XCTAssertEqual(state.simulationPhase, phaseSnapshot)
        XCTAssertEqual(state.simulationTick, tickSnapshot)
        XCTAssertEqual(state.lastRuntimeFault?.category, .runtimeFault)
        XCTAssertEqual(state.lastRuntimeFault?.code, "runtimeDependencyDown")
        XCTAssertEqual(state.lastRuntimeFault?.message, "scheduler queue unavailable")
        XCTAssertEqual(state.lastRuntimeEvent?.code, .simulationFaultReported)
        XCTAssertEqual(state.lastRuntimeEvent?.detail, "runtimeDependencyDown")
        XCTAssertEqual(state.lastAction, "simulationFault")
    }

    func testMalformedRuntimeFaultPayloadDoesNotAdvanceTickAndUsesDeterministicFaultCode() {
        var state = TopologyEditorState()

        TopologyEditorReducer.reduce(state: &state, action: .startSimulation)
        TopologyEditorReducer.reduce(state: &state, action: .simulationTick(step: 3))
        let phaseSnapshot = state.simulationPhase
        let tickSnapshot = state.simulationTick

        TopologyEditorReducer.reduce(
            state: &state,
            action: .simulationFault(code: nil, message: "ignored")
        )

        XCTAssertEqual(state.simulationPhase, phaseSnapshot)
        XCTAssertEqual(state.simulationTick, tickSnapshot)
        XCTAssertEqual(state.lastRuntimeFault?.category, .malformedRuntimePayload)
        XCTAssertEqual(state.lastRuntimeFault?.code, "malformedRuntimePayload")
        XCTAssertEqual(state.lastRuntimeEvent?.code, .simulationFaultRejectedMalformedPayload)
        XCTAssertEqual(state.lastAction, "simulationFault")
    }

    func testRuntimeFaultThenRecoverClearsFaultOnNextStart() {
        var state = TopologyEditorState()

        TopologyEditorReducer.reduce(state: &state, action: .startSimulation)
        TopologyEditorReducer.reduce(
            state: &state,
            action: .simulationFault(code: "runtimeDependencyDown", message: "temporary")
        )
        XCTAssertEqual(state.lastRuntimeFault?.category, .runtimeFault)

        TopologyEditorReducer.reduce(state: &state, action: .stopSimulation)
        TopologyEditorReducer.reduce(state: &state, action: .startSimulation)

        XCTAssertEqual(state.simulationPhase, .running)
        XCTAssertNil(state.lastRuntimeFault)
        XCTAssertEqual(state.lastRuntimeEvent?.code, .simulationStarted)
        XCTAssertEqual(state.lastAction, "startSimulation")
    }

    func testPingMalformedCommandExposesInspectableFaultAndActionMetadata() {
        var state = TopologyEditorState()

        let sourceNodeID = addNode(kind: .pc, at: CGPoint(x: 20, y: 20), to: &state)
        saveRuntimeIP(nodeID: sourceNodeID, ipAddress: "192.168.0.10", subnetMask: "255.255.255.0", state: &state)

        TopologyEditorReducer.reduce(state: &state, action: .startSimulation)
        TopologyEditorReducer.reduce(state: &state, action: .executePing(nodeID: sourceNodeID, command: "ping"))

        XCTAssertEqual(state.lastPingEvent?.code, .pingRejectedMalformedCommand)
        XCTAssertEqual(state.lastPingEvent?.detail, "malformedPingCommand")
        XCTAssertEqual(state.lastPingFault?.category, .commandValidation)
        XCTAssertEqual(state.lastPingFault?.code, "malformedPingCommand")
        XCTAssertEqual(state.lastRuntimeEvent?.code, .pingRejectedMalformedCommand)
        XCTAssertEqual(state.lastAction, "executePing")
        XCTAssertTrue(state.runtimeConsoleEntriesByNodeID[sourceNodeID]?.last?.contains("malformedPingCommand") ?? false)
    }

    func testPingTopologyUnreachableExposesRoutingFailureWithoutMutatingIPAddressConfig() {
        var state = TopologyEditorState()

        let sourceNodeID = addNode(kind: .pc, at: CGPoint(x: 20, y: 20), to: &state)
        let targetNodeID = addNode(kind: .pc, at: CGPoint(x: 300, y: 20), to: &state)
        saveRuntimeIP(nodeID: sourceNodeID, ipAddress: "192.168.0.10", subnetMask: "255.255.255.0", state: &state)
        saveRuntimeIP(nodeID: targetNodeID, ipAddress: "192.168.0.20", subnetMask: "255.255.255.0", state: &state)
        let sourceSnapshot = state.runtimeDeviceConfigurations[sourceNodeID]

        TopologyEditorReducer.reduce(state: &state, action: .startSimulation)
        TopologyEditorReducer.reduce(state: &state, action: .executePing(nodeID: sourceNodeID, command: "ping 192.168.0.20"))

        XCTAssertEqual(state.lastPingEvent?.code, .pingRejectedTopologyUnreachable)
        XCTAssertEqual(state.lastPingEvent?.detail, "pingTargetUnreachable")
        XCTAssertEqual(state.lastPingFault?.category, .networkRouting)
        XCTAssertEqual(state.lastPingFault?.code, "pingTargetUnreachable")
        XCTAssertEqual(state.runtimeDeviceConfigurations[sourceNodeID], sourceSnapshot)
    }

    func testPingSuccessClearsPreviousPingFaultAndReportsAttributedDetail() {
        var state = TopologyEditorState()

        let sourceNodeID = addNode(kind: .pc, at: CGPoint(x: 20, y: 20), to: &state)
        let targetNodeID = addNode(kind: .pc, at: CGPoint(x: 300, y: 20), to: &state)
        let switchNodeID = addNode(kind: .networkSwitch, at: CGPoint(x: 160, y: 100), to: &state)

        connect(sourceNodeID, switchNodeID, state: &state)
        connect(targetNodeID, switchNodeID, state: &state)

        saveRuntimeIP(nodeID: sourceNodeID, ipAddress: "192.168.0.10", subnetMask: "255.255.255.0", state: &state)
        saveRuntimeIP(nodeID: targetNodeID, ipAddress: "192.168.0.20", subnetMask: "255.255.255.0", state: &state)

        TopologyEditorReducer.reduce(state: &state, action: .startSimulation)
        TopologyEditorReducer.reduce(state: &state, action: .executePing(nodeID: sourceNodeID, command: "ping"))
        XCTAssertEqual(state.lastPingEvent?.code, .pingRejectedMalformedCommand)

        TopologyEditorReducer.reduce(state: &state, action: .executePing(nodeID: sourceNodeID, command: "ping 192.168.0.20"))

        XCTAssertEqual(state.lastPingEvent?.code, .pingSucceeded)
        XCTAssertTrue(state.lastPingEvent?.detail?.contains("targetIP=192.168.0.20") ?? false)
        XCTAssertNil(state.lastPingFault)
        XCTAssertNil(state.lastRuntimeFault)
        XCTAssertEqual(state.lastRuntimeEvent?.code, .pingSucceeded)
    }

    // MARK: - Helpers

    @discardableResult
    private func addNode(kind: TopologyNodeKind, at position: CGPoint, to state: inout TopologyEditorState) -> UUID {
        let nodeID = UUID()
        TopologyEditorReducer.reduce(state: &state, action: .placeNode(kind: kind, at: position, nodeID: nodeID))
        return nodeID
    }

    private func connect(_ sourceNodeID: UUID, _ targetNodeID: UUID, state: inout TopologyEditorState) {
        TopologyEditorReducer.reduce(state: &state, action: .startConnection(nodeID: sourceNodeID, portID: nil))
        TopologyEditorReducer.reduce(state: &state, action: .completeConnection(nodeID: targetNodeID, portID: nil))
        XCTAssertNil(state.lastValidationError)
    }

    private func saveRuntimeIP(
        nodeID: UUID,
        ipAddress: String,
        subnetMask: String,
        state: inout TopologyEditorState
    ) {
        TopologyEditorReducer.reduce(
            state: &state,
            action: .saveRuntimeDeviceIP(nodeID: nodeID, ipAddress: ipAddress, subnetMask: subnetMask)
        )
        XCTAssertNil(state.lastRuntimeFault)
        XCTAssertEqual(state.lastRuntimeEvent?.code, .runtimeDeviceIPSaved)
    }
}
