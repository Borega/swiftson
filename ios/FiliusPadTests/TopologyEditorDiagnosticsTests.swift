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
        XCTAssertTrue(state.lastPingEvent?.detail?.contains("hops=") ?? false)
        XCTAssertTrue(state.lastPingEvent?.detail?.contains("latencyMs=") ?? false)
        XCTAssertTrue(state.lastPingEvent?.detail?.contains("path=") ?? false)
        XCTAssertNil(state.lastPingFault)
        XCTAssertNil(state.lastRuntimeFault)
        XCTAssertEqual(state.lastRuntimeEvent?.code, .pingSucceeded)
    }

    func testTraceSuccessPublishesPathAwareRuntimeDiagnostics() {
        var state = TopologyEditorState()

        let sourceNodeID = addNode(kind: .pc, at: CGPoint(x: 20, y: 20), to: &state)
        let switchNodeID = addNode(kind: .networkSwitch, at: CGPoint(x: 160, y: 100), to: &state)
        let targetNodeID = addNode(kind: .pc, at: CGPoint(x: 300, y: 20), to: &state)

        connect(sourceNodeID, switchNodeID, state: &state)
        connect(targetNodeID, switchNodeID, state: &state)

        saveRuntimeIP(nodeID: sourceNodeID, ipAddress: "192.168.0.10", subnetMask: "255.255.255.0", state: &state)
        saveRuntimeIP(nodeID: targetNodeID, ipAddress: "192.168.0.20", subnetMask: "255.255.255.0", state: &state)

        TopologyEditorReducer.reduce(state: &state, action: .startSimulation)
        TopologyEditorReducer.reduce(state: &state, action: .executePing(nodeID: sourceNodeID, command: "trace 192.168.0.20"))

        XCTAssertEqual(state.lastRuntimeEvent?.code, .traceSucceeded)
        XCTAssertTrue(state.lastRuntimeEvent?.detail?.contains("command=trace") ?? false)
        XCTAssertTrue(state.lastRuntimeEvent?.detail?.contains("hops=2") ?? false)
        XCTAssertTrue(state.lastRuntimeEvent?.detail?.contains("path=") ?? false)
        XCTAssertTrue(state.lastRuntimeEvent?.detail?.contains("latencyMs=10") ?? false)
        XCTAssertNil(state.lastRuntimeFault)
    }

    func testUnsupportedRuntimeCommandUsesExplicitAttributableFault() {
        var state = TopologyEditorState()

        let sourceNodeID = addNode(kind: .pc, at: CGPoint(x: 20, y: 20), to: &state)
        TopologyEditorReducer.reduce(state: &state, action: .startSimulation)

        TopologyEditorReducer.reduce(state: &state, action: .executePing(nodeID: sourceNodeID, command: "nmap 192.168.0.20"))

        XCTAssertEqual(state.lastRuntimeEvent?.code, .runtimeCommandRejectedUnsupported)
        XCTAssertEqual(state.lastRuntimeFault?.category, .commandValidation)
        XCTAssertEqual(state.lastRuntimeFault?.code, "unsupportedRuntimeCommand")
        XCTAssertTrue(state.lastRuntimeFault?.message.contains("nmap") ?? false)
    }

    func testDHCPAndDNSServiceCommandsPublishInspectableDiagnostics() {
        var state = TopologyEditorState()
        let sourceNodeID = addNode(kind: .pc, at: CGPoint(x: 20, y: 20), to: &state)

        TopologyEditorReducer.reduce(state: &state, action: .startSimulation)
        TopologyEditorReducer.reduce(
            state: &state,
            action: .executePing(nodeID: sourceNodeID, command: "dhcp lease 10.40.0.10 255.255.255.0")
        )

        XCTAssertEqual(state.lastRuntimeEvent?.code, .dhcpLeaseAssigned)
        XCTAssertEqual(state.runtimeDHCPLeaseByNodeID[sourceNodeID]?.ipAddress, "10.40.0.10")

        TopologyEditorReducer.reduce(
            state: &state,
            action: .executePing(nodeID: sourceNodeID, command: "dns add lab.local 10.40.0.44")
        )
        XCTAssertEqual(state.lastRuntimeEvent?.code, .dnsRecordRegistered)

        TopologyEditorReducer.reduce(
            state: &state,
            action: .executePing(nodeID: sourceNodeID, command: "dns resolve lab.local")
        )

        XCTAssertEqual(state.lastRuntimeEvent?.code, .dnsResolveSucceeded)
        XCTAssertTrue(state.lastRuntimeEvent?.detail?.contains("host=lab.local") ?? false)
        XCTAssertNil(state.lastRuntimeFault)
        XCTAssertEqual(state.runtimeDNSRecordsByHostname["lab.local"]?.targetIPAddress, "10.40.0.44")
    }

    func testDNSResolveUnknownHostPublishesServiceFaultCategory() {
        var state = TopologyEditorState()
        let sourceNodeID = addNode(kind: .pc, at: CGPoint(x: 20, y: 20), to: &state)

        TopologyEditorReducer.reduce(state: &state, action: .startSimulation)
        TopologyEditorReducer.reduce(
            state: &state,
            action: .executePing(nodeID: sourceNodeID, command: "dns resolve unknown.local")
        )

        XCTAssertEqual(state.lastRuntimeEvent?.code, .dnsResolveRejectedUnknownHost)
        XCTAssertEqual(state.lastRuntimeFault?.category, .networkService)
        XCTAssertEqual(state.lastRuntimeFault?.code, "dnsUnknownHost")
    }

    func testTraceTwentyNodeDiagnosticsContractPublishesDeterministicRouteWithoutTickMutation() {
        let phaseTag = "[M002/S03/T03 tests]"
        var state = TopologyEditorState()

        var pathNodeIDs: [UUID] = []
        let sourceNodeID = addNode(kind: .pc, at: CGPoint(x: 20, y: 20), to: &state)
        pathNodeIDs.append(sourceNodeID)

        for index in 1...18 {
            let switchNodeID = addNode(
                kind: .networkSwitch,
                at: CGPoint(x: CGFloat(20 + (index * 20)), y: index.isMultiple(of: 2) ? 20 : 120),
                to: &state
            )
            pathNodeIDs.append(switchNodeID)
        }

        let targetNodeID = addNode(kind: .pc, at: CGPoint(x: 420, y: 20), to: &state)
        pathNodeIDs.append(targetNodeID)

        for (source, destination) in zip(pathNodeIDs, pathNodeIDs.dropFirst()) {
            connect(source, destination, state: &state)
        }

        saveRuntimeIP(nodeID: sourceNodeID, ipAddress: "10.30.0.10", subnetMask: "255.255.255.0", state: &state)
        saveRuntimeIP(nodeID: targetNodeID, ipAddress: "10.30.0.20", subnetMask: "255.255.255.0", state: &state)

        TopologyEditorReducer.reduce(state: &state, action: .startSimulation)
        TopologyEditorReducer.reduce(state: &state, action: .simulationTick(step: 9))
        let tickSnapshot = state.simulationTick

        TopologyEditorReducer.reduce(state: &state, action: .executePing(nodeID: sourceNodeID, command: "trace 10.30.0.20"))

        XCTAssertEqual(state.lastRuntimeEvent?.code, .traceSucceeded, "\(phaseTag) expected trace success over 20-node diagnostics fixture")
        let detail = state.lastRuntimeEvent?.detail ?? ""
        let expectedPath = pathNodeIDs.map(\.uuidString).joined(separator: "->")

        XCTAssertTrue(detail.contains("command=trace"), "\(phaseTag) expected runtime event to include command attribution")
        XCTAssertTrue(detail.contains("targetIP=10.30.0.20"), "\(phaseTag) expected runtime event to include target attribution")
        XCTAssertTrue(detail.contains("hops=19"), "\(phaseTag) expected runtime event to include 19-hop depth metadata")
        XCTAssertTrue(detail.contains("latencyMs=78"), "\(phaseTag) expected runtime event to include deterministic latency metadata")
        XCTAssertTrue(detail.contains("path=\(expectedPath)"), "\(phaseTag) expected runtime event to include full path metadata")

        XCTAssertEqual(state.simulationTick, tickSnapshot, "\(phaseTag) trace command should not mutate simulation tick")
        XCTAssertNil(state.lastRuntimeFault)
        XCTAssertNil(state.lastPingEvent)
        XCTAssertNil(state.lastPingFault)
    }

    func testPersistenceFailureMetadataIsInspectableAndDismissible() {
        var state = TopologyEditorState()
        state.recordPersistenceFailure(
            operation: .load,
            code: .malformedPayload,
            detail: "Decoded snapshot failed validation"
        )

        XCTAssertEqual(state.lastPersistenceError?.operation, .load)
        XCTAssertEqual(state.lastPersistenceError?.code, .malformedPayload)
        XCTAssertEqual(state.lastPersistenceError?.detail, "Decoded snapshot failed validation")
        XCTAssertNotNil(state.lastPersistenceError?.occurredAt)

        TopologyEditorReducer.reduce(state: &state, action: .dismissPersistenceError)
        XCTAssertNil(state.lastPersistenceError)
    }

    func testPersistenceSaveAndLoadMetadataRemainInspectable() {
        var state = TopologyEditorState()
        state.persistenceRevision = 7

        state.recordPersistenceSave(revision: 7)
        XCTAssertEqual(state.lastPersistedRevision, 7)
        XCTAssertNotNil(state.lastPersistenceSaveAt)
        XCTAssertNil(state.lastPersistenceError)

        state.recordPersistenceLoad()
        XCTAssertNotNil(state.lastPersistenceLoadAt)
        XCTAssertEqual(state.lastPersistedRevision, 7)
        XCTAssertNil(state.lastPersistenceError)
    }

    func testRecoverySuccessMetadataIsInspectableAndDismissible() {
        var state = TopologyEditorState()

        state.recordRecoverySuccess(message: "Recovered autosave (revision: 9)")

        XCTAssertEqual(state.lastRecoveryMessage, "Recovered autosave (revision: 9)")
        XCTAssertEqual(state.lastRecoverySucceeded, true)
        XCTAssertTrue(state.isRecoveryNoticeVisible)
        XCTAssertNotNil(state.lastRecoveryAt)

        TopologyEditorReducer.reduce(state: &state, action: .dismissRecoveryNotice)
        XCTAssertFalse(state.isRecoveryNoticeVisible)
        XCTAssertEqual(state.lastAction, "dismissRecoveryNotice")
    }

    func testRecoveryFailureMetadataIsInspectableAndDismissible() {
        var state = TopologyEditorState()

        state.recordRecoveryFailure(message: "Recovery failed: malformedPayload")

        XCTAssertEqual(state.lastRecoveryMessage, "Recovery failed: malformedPayload")
        XCTAssertEqual(state.lastRecoverySucceeded, false)
        XCTAssertTrue(state.isRecoveryNoticeVisible)
        XCTAssertNotNil(state.lastRecoveryAt)

        TopologyEditorReducer.reduce(state: &state, action: .dismissRecoveryNotice)
        XCTAssertFalse(state.isRecoveryNoticeVisible)
        XCTAssertEqual(state.lastAction, "dismissRecoveryNotice")
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
