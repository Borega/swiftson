import CoreGraphics
import XCTest
@testable import FiliusPad

final class TopologyEditorReducerTests: XCTestCase {
    func testPlaceNodeAtCanvasEdgeAddsNodeAndSelectsIt() {
        var state = TopologyEditorState()
        let id = uuid("11111111-1111-1111-1111-111111111111")

        TopologyEditorReducer.reduce(
            state: &state,
            action: .placeNode(kind: .pc, at: CGPoint(x: 0, y: 0), nodeID: id)
        )

        XCTAssertEqual(state.graph.nodes.count, 1)
        XCTAssertEqual(state.graph.nodes.first?.id, id)
        XCTAssertEqual(state.graph.nodes.first?.position, CGPoint(x: 0, y: 0))
        XCTAssertEqual(state.selectedNodeIDs, [id])
        XCTAssertNil(state.lastValidationError)
    }

    func testSelectNodesInRectangleSelectsOnlyMembers() {
        var state = TopologyEditorState()

        let insideA = addNode(kind: .pc, at: CGPoint(x: 10, y: 10), to: &state)
        let insideB = addNode(kind: .networkSwitch, at: CGPoint(x: 90, y: 80), to: &state)
        _ = addNode(kind: .pc, at: CGPoint(x: 160, y: 160), to: &state)

        TopologyEditorReducer.reduce(
            state: &state,
            action: .selectNodes(in: CGRect(x: 0, y: 0, width: 120, height: 120))
        )

        XCTAssertEqual(state.selectedNodeIDs, [insideA, insideB])
        XCTAssertNil(state.lastValidationError)
    }

    func testSelectNodesWithZeroAreaRectangleReturnsEmptySelection() {
        var state = TopologyEditorState()
        _ = addNode(kind: .pc, at: CGPoint(x: 40, y: 60), to: &state)

        TopologyEditorReducer.reduce(
            state: &state,
            action: .selectNodes(in: CGRect(x: 0, y: 0, width: 0, height: 0))
        )

        XCTAssertTrue(state.selectedNodeIDs.isEmpty)
        XCTAssertNil(state.lastValidationError)
    }

    func testStartAndCompleteConnectionAddsLinkAndClearsDraft() {
        var state = TopologyEditorState()

        let sourceNodeID = addNode(kind: .pc, at: CGPoint(x: 20, y: 20), to: &state)
        let targetNodeID = addNode(kind: .networkSwitch, at: CGPoint(x: 150, y: 20), to: &state)

        TopologyEditorReducer.reduce(
            state: &state,
            action: .startConnection(nodeID: sourceNodeID, portID: nil)
        )
        TopologyEditorReducer.reduce(
            state: &state,
            action: .completeConnection(nodeID: targetNodeID, portID: nil)
        )

        XCTAssertEqual(state.graph.links.count, 1)
        XCTAssertNil(state.pendingConnection)
        XCTAssertEqual(state.selectedNodeIDs, [sourceNodeID, targetNodeID])
        XCTAssertNil(state.lastValidationError)
    }

    func testDuplicateLinkRejectedWithoutMutatingGraph() {
        var state = TopologyEditorState()

        let sourceNodeID = addNode(kind: .pc, at: CGPoint(x: 30, y: 30), to: &state)
        let targetNodeID = addNode(kind: .networkSwitch, at: CGPoint(x: 180, y: 30), to: &state)

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
    }

    func testNoFreePortRejectedWithoutMutatingGraph() {
        var state = TopologyEditorState()

        let saturatedPCNodeID = addNode(kind: .pc, at: CGPoint(x: 30, y: 30), to: &state)
        let switchAID = addNode(kind: .networkSwitch, at: CGPoint(x: 180, y: 30), to: &state)
        let switchBID = addNode(kind: .networkSwitch, at: CGPoint(x: 340, y: 30), to: &state)

        connect(saturatedPCNodeID, switchAID, state: &state)
        let snapshot = state.graph

        TopologyEditorReducer.reduce(
            state: &state,
            action: .startConnection(nodeID: saturatedPCNodeID, portID: nil)
        )

        XCTAssertEqual(state.graph, snapshot)
        XCTAssertEqual(state.lastValidationError, .noFreePort)

        TopologyEditorReducer.reduce(
            state: &state,
            action: .startConnection(nodeID: switchBID, portID: nil)
        )
        TopologyEditorReducer.reduce(
            state: &state,
            action: .completeConnection(nodeID: saturatedPCNodeID, portID: nil)
        )

        XCTAssertEqual(state.graph, snapshot)
        XCTAssertEqual(state.lastValidationError, .noFreePort)
    }

    func testIncompatibleEndpointsRejectedWithoutMutatingGraph() {
        var state = TopologyEditorState()

        let firstPCNodeID = addNode(kind: .pc, at: CGPoint(x: 50, y: 50), to: &state)
        let secondPCNodeID = addNode(kind: .pc, at: CGPoint(x: 200, y: 50), to: &state)
        let snapshot = state.graph

        TopologyEditorReducer.reduce(
            state: &state,
            action: .startConnection(nodeID: firstPCNodeID, portID: nil)
        )
        TopologyEditorReducer.reduce(
            state: &state,
            action: .completeConnection(nodeID: secondPCNodeID, portID: nil)
        )

        XCTAssertEqual(state.graph, snapshot)
        XCTAssertEqual(state.lastValidationError, .incompatibleEndpoint)
    }

    func testInvalidPortIdentifierRejected() {
        var state = TopologyEditorState()

        let switchNodeID = addNode(kind: .networkSwitch, at: CGPoint(x: 20, y: 20), to: &state)

        TopologyEditorReducer.reduce(
            state: &state,
            action: .startConnection(nodeID: switchNodeID, portID: UUID())
        )

        XCTAssertEqual(state.lastValidationError, .invalidPortIdentifier)
        XCTAssertNil(state.pendingConnection)
    }

    func testConnectionToSelfRejected() {
        var state = TopologyEditorState()

        let switchNodeID = addNode(kind: .networkSwitch, at: CGPoint(x: 20, y: 20), to: &state)

        TopologyEditorReducer.reduce(
            state: &state,
            action: .startConnection(nodeID: switchNodeID, portID: nil)
        )
        TopologyEditorReducer.reduce(
            state: &state,
            action: .completeConnection(nodeID: switchNodeID, portID: nil)
        )

        XCTAssertEqual(state.lastValidationError, .selfConnectionNotAllowed)
        XCTAssertTrue(state.graph.links.isEmpty)
    }

    func testConnectWithNonexistentNodeIdentifierRejected() {
        var state = TopologyEditorState()
        let switchNodeID = addNode(kind: .networkSwitch, at: CGPoint(x: 20, y: 20), to: &state)

        TopologyEditorReducer.reduce(
            state: &state,
            action: .startConnection(nodeID: switchNodeID, portID: nil)
        )
        TopologyEditorReducer.reduce(
            state: &state,
            action: .completeConnection(nodeID: uuid("99999999-9999-9999-9999-999999999999"), portID: nil)
        )

        XCTAssertEqual(state.lastValidationError, .nodeNotFound)
        XCTAssertTrue(state.graph.links.isEmpty)
    }

    func testMalformedSelectionAndMovePayloadsAreRejected() {
        var state = TopologyEditorState()

        TopologyEditorReducer.reduce(state: &state, action: .selectNodes(in: nil))
        XCTAssertEqual(state.lastValidationError, .malformedActionPayload)

        TopologyEditorReducer.reduce(state: &state, action: .moveSelectedNodes(delta: nil))
        XCTAssertEqual(state.lastValidationError, .malformedActionPayload)
    }

    func testMoveSelectedNodesWithZeroDeltaDoesNotMutateGraph() {
        var state = TopologyEditorState()
        let nodeID = addNode(kind: .pc, at: CGPoint(x: 30, y: 40), to: &state)

        TopologyEditorReducer.reduce(state: &state, action: .selectSingleNode(nodeID: nodeID))
        let snapshot = state.graph

        TopologyEditorReducer.reduce(state: &state, action: .moveSelectedNodes(delta: .zero))

        XCTAssertEqual(state.graph, snapshot)
        XCTAssertNil(state.lastValidationError)
    }

    func testMoveSelectedNodeUpdatesLinkProjection() {
        var state = TopologyEditorState()

        let movingNodeID = addNode(kind: .pc, at: CGPoint(x: 20, y: 20), to: &state)
        let anchorNodeID = addNode(kind: .networkSwitch, at: CGPoint(x: 200, y: 20), to: &state)
        connect(movingNodeID, anchorNodeID, state: &state)

        let linkID = tryUnwrap(state.graph.links.first?.id)
        let beforeProjection = tryUnwrap(state.graph.linkProjection(for: linkID))

        TopologyEditorReducer.reduce(state: &state, action: .selectSingleNode(nodeID: movingNodeID))
        TopologyEditorReducer.reduce(
            state: &state,
            action: .moveSelectedNodes(delta: CGSize(width: 40, height: 15))
        )

        let afterProjection = tryUnwrap(state.graph.linkProjection(for: linkID))
        XCTAssertEqual(afterProjection.source, CGPoint(x: 60, y: 35))
        XCTAssertEqual(afterProjection.target, beforeProjection.target)
        XCTAssertNotEqual(afterProjection, beforeProjection)
    }

    func testPanAndZoomUpdateViewportWithoutMutatingGraph() {
        var state = TopologyEditorState()
        let nodeID = addNode(kind: .pc, at: CGPoint(x: 50, y: 50), to: &state)
        let graphSnapshot = state.graph

        TopologyEditorReducer.reduce(state: &state, action: .setActiveTool(mode: .connect))
        TopologyEditorReducer.reduce(state: &state, action: .panCanvas(delta: CGSize(width: 24, height: -12)))
        TopologyEditorReducer.reduce(
            state: &state,
            action: .zoomCanvas(scaleDelta: 1.5, anchor: CGPoint(x: 100, y: 100))
        )

        XCTAssertEqual(state.graph, graphSnapshot)
        XCTAssertNotEqual(state.viewport.offset, .zero)
        XCTAssertGreaterThan(state.viewport.scale, 1)
        XCTAssertEqual(state.activeTool, .connect)
        XCTAssertEqual(state.selectedNodeIDs, [nodeID])
        XCTAssertNil(state.lastValidationError)
    }

    func testMalformedViewportPayloadsAreRejectedAndDoNotChangeViewport() {
        var state = TopologyEditorState()
        let initialViewport = state.viewport

        TopologyEditorReducer.reduce(
            state: &state,
            action: .panCanvas(delta: CGSize(width: .infinity, height: 10))
        )
        XCTAssertEqual(state.lastValidationError, .malformedActionPayload)
        XCTAssertEqual(state.viewport, initialViewport)

        TopologyEditorReducer.reduce(state: &state, action: .zoomCanvas(scaleDelta: 0, anchor: nil))
        XCTAssertEqual(state.lastValidationError, .malformedActionPayload)
        XCTAssertEqual(state.viewport, initialViewport)
    }

    func testStartSimulationIsIdempotentAndDeterministic() {
        var state = TopologyEditorState()

        TopologyEditorReducer.reduce(state: &state, action: .startSimulation)
        XCTAssertEqual(state.simulationPhase, .running)
        XCTAssertEqual(state.simulationTick, 0)
        XCTAssertEqual(state.lastRuntimeEvent?.code, .simulationStarted)
        XCTAssertNil(state.lastRuntimeFault)

        TopologyEditorReducer.reduce(state: &state, action: .startSimulation)
        XCTAssertEqual(state.simulationPhase, .running)
        XCTAssertEqual(state.simulationTick, 0)
        XCTAssertEqual(state.lastRuntimeEvent?.code, .simulationStartIgnoredAlreadyRunning)
        XCTAssertEqual(state.lastAction, "startSimulation")
    }

    func testSimulationTickMutatesOnlyRuntimeStateWhileRunning() {
        var state = TopologyEditorState()
        _ = addNode(kind: .pc, at: CGPoint(x: 50, y: 50), to: &state)

        let graphSnapshot = state.graph
        let selectedSnapshot = state.selectedNodeIDs
        let activeToolSnapshot = state.activeTool
        let pendingConnectionSnapshot = state.pendingConnection
        let viewportSnapshot = state.viewport

        TopologyEditorReducer.reduce(state: &state, action: .startSimulation)
        TopologyEditorReducer.reduce(state: &state, action: .simulationTick(step: 3))

        XCTAssertEqual(state.simulationPhase, .running)
        XCTAssertEqual(state.simulationTick, 3)
        XCTAssertEqual(state.lastRuntimeEvent?.code, .simulationTickAdvanced)
        XCTAssertEqual(state.graph, graphSnapshot)
        XCTAssertEqual(state.selectedNodeIDs, selectedSnapshot)
        XCTAssertEqual(state.activeTool, activeToolSnapshot)
        XCTAssertEqual(state.pendingConnection, pendingConnectionSnapshot)
        XCTAssertEqual(state.viewport, viewportSnapshot)
    }

    func testSimulationTickWhileStoppedIsIgnored() {
        var state = TopologyEditorState()

        TopologyEditorReducer.reduce(state: &state, action: .simulationTick(step: 1))

        XCTAssertEqual(state.simulationPhase, .stopped)
        XCTAssertEqual(state.simulationTick, 0)
        XCTAssertEqual(state.lastRuntimeEvent?.code, .simulationTickIgnoredWhileStopped)
        XCTAssertNil(state.lastRuntimeFault)
    }

    func testSimulationTickWithMalformedPayloadDoesNotAdvanceTickAndSetsFault() {
        var state = TopologyEditorState()

        TopologyEditorReducer.reduce(state: &state, action: .startSimulation)
        TopologyEditorReducer.reduce(state: &state, action: .simulationTick(step: 2))
        let snapshotTick = state.simulationTick

        TopologyEditorReducer.reduce(state: &state, action: .simulationTick(step: nil))

        XCTAssertEqual(state.simulationTick, snapshotTick)
        XCTAssertEqual(state.lastRuntimeEvent?.code, .simulationFaultRejectedMalformedPayload)
        XCTAssertEqual(state.lastRuntimeFault?.category, .malformedRuntimePayload)
        XCTAssertEqual(state.lastRuntimeFault?.code, "malformedRuntimePayload")
    }

    func testStopSimulationIsIdempotentAfterStartAndTick() {
        var state = TopologyEditorState()

        TopologyEditorReducer.reduce(state: &state, action: .startSimulation)
        TopologyEditorReducer.reduce(state: &state, action: .simulationTick(step: 1))
        TopologyEditorReducer.reduce(state: &state, action: .stopSimulation)

        XCTAssertEqual(state.simulationPhase, .stopped)
        XCTAssertEqual(state.simulationTick, 1)
        XCTAssertEqual(state.lastRuntimeEvent?.code, .simulationStopped)

        TopologyEditorReducer.reduce(state: &state, action: .stopSimulation)

        XCTAssertEqual(state.simulationPhase, .stopped)
        XCTAssertEqual(state.simulationTick, 1)
        XCTAssertEqual(state.lastRuntimeEvent?.code, .simulationStopIgnoredAlreadyStopped)
    }

    func testOpenAndCloseRuntimeDeviceAreIdempotent() {
        var state = TopologyEditorState()
        let nodeID = addNode(kind: .pc, at: CGPoint(x: 30, y: 30), to: &state)

        TopologyEditorReducer.reduce(state: &state, action: .openRuntimeDevice(nodeID: nodeID))
        XCTAssertEqual(state.openedRuntimeDeviceID, nodeID)
        XCTAssertEqual(state.lastRuntimeEvent?.code, .runtimeDeviceOpened)

        TopologyEditorReducer.reduce(state: &state, action: .openRuntimeDevice(nodeID: nodeID))
        XCTAssertEqual(state.openedRuntimeDeviceID, nodeID)
        XCTAssertEqual(state.lastRuntimeEvent?.code, .runtimeDeviceOpened)

        TopologyEditorReducer.reduce(state: &state, action: .closeRuntimeDevice)
        XCTAssertNil(state.openedRuntimeDeviceID)
        XCTAssertEqual(state.lastRuntimeEvent?.code, .runtimeDeviceClosed)

        TopologyEditorReducer.reduce(state: &state, action: .closeRuntimeDevice)
        XCTAssertNil(state.openedRuntimeDeviceID)
        XCTAssertEqual(state.lastRuntimeEvent?.code, .runtimeDeviceCloseIgnoredAlreadyClosed)
    }

    func testSaveRuntimeDeviceIPStoresNormalizedConfiguration() {
        var state = TopologyEditorState()
        let nodeID = addNode(kind: .pc, at: CGPoint(x: 10, y: 10), to: &state)

        TopologyEditorReducer.reduce(
            state: &state,
            action: .saveRuntimeDeviceIP(nodeID: nodeID, ipAddress: " 192.168.001.010 ", subnetMask: "255.255.255.000")
        )

        XCTAssertEqual(
            state.runtimeDeviceConfigurations[nodeID],
            TopologyRuntimeDeviceConfiguration(ipAddress: "192.168.1.10", subnetMask: "255.255.255.0")
        )
        XCTAssertEqual(state.lastRuntimeEvent?.code, .runtimeDeviceIPSaved)
        XCTAssertNil(state.lastRuntimeFault)
    }

    func testSaveRuntimeDeviceIPRejectsInvalidSubnetMaskWithoutMutatingPriorConfig() {
        var state = TopologyEditorState()
        let nodeID = addNode(kind: .pc, at: CGPoint(x: 10, y: 10), to: &state)

        saveRuntimeIP(nodeID: nodeID, ipAddress: "192.168.0.10", subnetMask: "255.255.255.0", state: &state)
        let snapshot = state.runtimeDeviceConfigurations[nodeID]

        TopologyEditorReducer.reduce(
            state: &state,
            action: .saveRuntimeDeviceIP(nodeID: nodeID, ipAddress: "192.168.0.10", subnetMask: "255.0.255.0")
        )

        XCTAssertEqual(state.runtimeDeviceConfigurations[nodeID], snapshot)
        XCTAssertEqual(state.lastRuntimeEvent?.code, .runtimeDeviceIPRejectedInvalidConfiguration)
        XCTAssertEqual(state.lastRuntimeFault?.category, .networkConfiguration)
        XCTAssertEqual(state.lastRuntimeFault?.code, "invalidSubnetMask")
    }

    func testExecutePingSuccessAppendsConsoleEntryAndClearsPingFault() {
        var state = TopologyEditorState()

        let sourceNodeID = addNode(kind: .pc, at: CGPoint(x: 30, y: 30), to: &state)
        let targetNodeID = addNode(kind: .pc, at: CGPoint(x: 280, y: 30), to: &state)
        let switchNodeID = addNode(kind: .networkSwitch, at: CGPoint(x: 150, y: 100), to: &state)
        connect(sourceNodeID, switchNodeID, state: &state)
        connect(targetNodeID, switchNodeID, state: &state)

        saveRuntimeIP(nodeID: sourceNodeID, ipAddress: "192.168.0.10", subnetMask: "255.255.255.0", state: &state)
        saveRuntimeIP(nodeID: targetNodeID, ipAddress: "192.168.0.20", subnetMask: "255.255.255.0", state: &state)

        TopologyEditorReducer.reduce(state: &state, action: .startSimulation)
        TopologyEditorReducer.reduce(state: &state, action: .executePing(nodeID: sourceNodeID, command: "ping 192.168.0.20"))

        XCTAssertEqual(state.lastPingEvent?.code, .pingSucceeded)
        XCTAssertTrue(state.lastPingEvent?.detail?.contains("targetIP=192.168.0.20") ?? false)
        XCTAssertTrue(state.lastPingEvent?.detail?.contains("hops=") ?? false)
        XCTAssertTrue(state.lastPingEvent?.detail?.contains("path=") ?? false)
        XCTAssertTrue(state.lastPingEvent?.detail?.contains("latencyMs=") ?? false)
        XCTAssertNil(state.lastPingFault)
        XCTAssertEqual(state.lastRuntimeEvent?.code, .pingSucceeded)
        XCTAssertEqual(state.runtimeConsoleEntriesByNodeID[sourceNodeID]?.last, "Ping to 192.168.0.20 succeeded")
    }

    func testExecutePingRejectsMalformedCommand() {
        var state = TopologyEditorState()

        let sourceNodeID = addNode(kind: .pc, at: CGPoint(x: 30, y: 30), to: &state)
        saveRuntimeIP(nodeID: sourceNodeID, ipAddress: "192.168.0.10", subnetMask: "255.255.255.0", state: &state)

        TopologyEditorReducer.reduce(state: &state, action: .startSimulation)
        TopologyEditorReducer.reduce(state: &state, action: .executePing(nodeID: sourceNodeID, command: "ping"))

        XCTAssertEqual(state.lastPingEvent?.code, .pingRejectedMalformedCommand)
        XCTAssertEqual(state.lastPingFault?.category, .commandValidation)
        XCTAssertEqual(state.lastPingFault?.code, "malformedPingCommand")
    }

    func testExecutePingRejectsUnknownTarget() {
        var state = TopologyEditorState()

        let sourceNodeID = addNode(kind: .pc, at: CGPoint(x: 30, y: 30), to: &state)
        saveRuntimeIP(nodeID: sourceNodeID, ipAddress: "192.168.0.10", subnetMask: "255.255.255.0", state: &state)

        TopologyEditorReducer.reduce(state: &state, action: .startSimulation)
        TopologyEditorReducer.reduce(state: &state, action: .executePing(nodeID: sourceNodeID, command: "ping 192.168.0.200"))

        XCTAssertEqual(state.lastPingEvent?.code, .pingRejectedUnknownTarget)
        XCTAssertEqual(state.lastPingFault?.category, .networkRouting)
        XCTAssertEqual(state.lastPingFault?.code, "pingTargetUnknown")
    }

    func testExecutePingRejectsInvalidSourceConfiguration() {
        var state = TopologyEditorState()

        let sourceNodeID = addNode(kind: .pc, at: CGPoint(x: 30, y: 30), to: &state)

        TopologyEditorReducer.reduce(state: &state, action: .startSimulation)
        TopologyEditorReducer.reduce(state: &state, action: .executePing(nodeID: sourceNodeID, command: "ping 192.168.0.20"))

        XCTAssertEqual(state.lastPingEvent?.code, .pingRejectedInvalidSourceConfiguration)
        XCTAssertEqual(state.lastPingFault?.category, .networkConfiguration)
        XCTAssertEqual(state.lastPingFault?.code, "sourceConfigurationMissing")
    }

    func testExecutePingRejectsSubnetMismatch() {
        var state = TopologyEditorState()

        let sourceNodeID = addNode(kind: .pc, at: CGPoint(x: 30, y: 30), to: &state)
        let targetNodeID = addNode(kind: .pc, at: CGPoint(x: 280, y: 30), to: &state)
        let switchNodeID = addNode(kind: .networkSwitch, at: CGPoint(x: 150, y: 100), to: &state)
        connect(sourceNodeID, switchNodeID, state: &state)
        connect(targetNodeID, switchNodeID, state: &state)

        saveRuntimeIP(nodeID: sourceNodeID, ipAddress: "192.168.0.10", subnetMask: "255.255.255.0", state: &state)
        saveRuntimeIP(nodeID: targetNodeID, ipAddress: "10.0.0.20", subnetMask: "255.0.0.0", state: &state)

        TopologyEditorReducer.reduce(state: &state, action: .startSimulation)
        TopologyEditorReducer.reduce(state: &state, action: .executePing(nodeID: sourceNodeID, command: "ping 10.0.0.20"))

        XCTAssertEqual(state.lastPingEvent?.code, .pingRejectedSubnetMismatch)
        XCTAssertEqual(state.lastPingFault?.category, .networkRouting)
        XCTAssertEqual(state.lastPingFault?.code, "pingSubnetMismatch")
    }

    func testExecutePingRejectsDisconnectedTopology() {
        var state = TopologyEditorState()

        let sourceNodeID = addNode(kind: .pc, at: CGPoint(x: 30, y: 30), to: &state)
        let targetNodeID = addNode(kind: .pc, at: CGPoint(x: 280, y: 30), to: &state)

        saveRuntimeIP(nodeID: sourceNodeID, ipAddress: "192.168.0.10", subnetMask: "255.255.255.0", state: &state)
        saveRuntimeIP(nodeID: targetNodeID, ipAddress: "192.168.0.20", subnetMask: "255.255.255.0", state: &state)

        TopologyEditorReducer.reduce(state: &state, action: .startSimulation)
        TopologyEditorReducer.reduce(state: &state, action: .executePing(nodeID: sourceNodeID, command: "ping 192.168.0.20"))

        XCTAssertEqual(state.lastPingEvent?.code, .pingRejectedTopologyUnreachable)
        XCTAssertEqual(state.lastPingFault?.category, .networkRouting)
        XCTAssertEqual(state.lastPingFault?.code, "pingTargetUnreachable")
    }

    func testExecutePingWhileStoppedReturnsDeterministicFailure() {
        var state = TopologyEditorState()

        let sourceNodeID = addNode(kind: .pc, at: CGPoint(x: 30, y: 30), to: &state)
        let targetNodeID = addNode(kind: .pc, at: CGPoint(x: 280, y: 30), to: &state)

        saveRuntimeIP(nodeID: sourceNodeID, ipAddress: "192.168.0.10", subnetMask: "255.255.255.0", state: &state)
        saveRuntimeIP(nodeID: targetNodeID, ipAddress: "192.168.0.20", subnetMask: "255.255.255.0", state: &state)

        TopologyEditorReducer.reduce(state: &state, action: .executePing(nodeID: sourceNodeID, command: "ping 192.168.0.20"))

        XCTAssertEqual(state.lastPingEvent?.code, .pingRejectedSimulationStopped)
        XCTAssertEqual(state.lastPingFault?.category, .runtimeFault)
        XCTAssertEqual(state.lastPingFault?.code, "pingWhileSimulationStopped")
    }

    func testExecutePingAgainstSelfSucceedsWhenConfigured() {
        var state = TopologyEditorState()

        let sourceNodeID = addNode(kind: .pc, at: CGPoint(x: 30, y: 30), to: &state)
        saveRuntimeIP(nodeID: sourceNodeID, ipAddress: "192.168.0.10", subnetMask: "255.255.255.0", state: &state)

        TopologyEditorReducer.reduce(state: &state, action: .startSimulation)
        TopologyEditorReducer.reduce(state: &state, action: .executePing(nodeID: sourceNodeID, command: "ping 192.168.0.10"))

        XCTAssertEqual(state.lastPingEvent?.code, .pingSucceeded)
        XCTAssertNil(state.lastPingFault)
    }

    func testExecuteTraceSuccessReportsDeterministicPathAndHopMetadata() {
        var state = TopologyEditorState()

        let sourceNodeID = addNode(kind: .pc, at: CGPoint(x: 20, y: 20), nodeID: uuid("10000000-0000-0000-0000-000000000001"), to: &state)
        let switchAID = addNode(kind: .networkSwitch, at: CGPoint(x: 140, y: 20), nodeID: uuid("20000000-0000-0000-0000-000000000002"), to: &state)
        let switchBID = addNode(kind: .networkSwitch, at: CGPoint(x: 260, y: 20), nodeID: uuid("30000000-0000-0000-0000-000000000003"), to: &state)
        let targetNodeID = addNode(kind: .pc, at: CGPoint(x: 380, y: 20), nodeID: uuid("40000000-0000-0000-0000-000000000004"), to: &state)

        connect(sourceNodeID, switchAID, state: &state)
        connect(switchAID, switchBID, state: &state)
        connect(switchBID, targetNodeID, state: &state)

        saveRuntimeIP(nodeID: sourceNodeID, ipAddress: "192.168.0.10", subnetMask: "255.255.255.0", state: &state)
        saveRuntimeIP(nodeID: targetNodeID, ipAddress: "192.168.0.20", subnetMask: "255.255.255.0", state: &state)

        TopologyEditorReducer.reduce(state: &state, action: .startSimulation)
        TopologyEditorReducer.reduce(state: &state, action: .executePing(nodeID: sourceNodeID, command: "trace 192.168.0.20"))

        XCTAssertEqual(state.lastRuntimeEvent?.code, .traceSucceeded)
        XCTAssertTrue(state.lastRuntimeEvent?.detail?.contains("command=trace") ?? false)
        XCTAssertTrue(state.lastRuntimeEvent?.detail?.contains("hops=3") ?? false)
        XCTAssertTrue(state.lastRuntimeEvent?.detail?.contains("latencyMs=14") ?? false)
        XCTAssertTrue(
            state.lastRuntimeEvent?.detail?.contains(
                "path=10000000-0000-0000-0000-000000000001->20000000-0000-0000-0000-000000000002->30000000-0000-0000-0000-000000000003->40000000-0000-0000-0000-000000000004"
            ) ?? false
        )
        XCTAssertNil(state.lastRuntimeFault)
        XCTAssertEqual(
            Array(state.runtimeConsoleEntriesByNodeID[sourceNodeID]?.suffix(2) ?? []),
            [
                "Trace to 192.168.0.20 succeeded (hops=3, latencyMs=14)",
                "Path: 10000000-0000-0000-0000-000000000001 -> 20000000-0000-0000-0000-000000000002 -> 30000000-0000-0000-0000-000000000003 -> 40000000-0000-0000-0000-000000000004"
            ]
        )
    }

    func testExecuteTraceRejectsUnsupportedCommandVerbExplicitly() {
        var state = TopologyEditorState()

        let sourceNodeID = addNode(kind: .pc, at: CGPoint(x: 30, y: 30), to: &state)
        TopologyEditorReducer.reduce(state: &state, action: .startSimulation)
        TopologyEditorReducer.reduce(state: &state, action: .executePing(nodeID: sourceNodeID, command: "arp 192.168.0.20"))

        XCTAssertEqual(state.lastRuntimeEvent?.code, .runtimeCommandRejectedUnsupported)
        XCTAssertEqual(state.lastRuntimeFault?.category, .commandValidation)
        XCTAssertEqual(state.lastRuntimeFault?.code, "unsupportedRuntimeCommand")
        XCTAssertTrue(state.runtimeConsoleEntriesByNodeID[sourceNodeID]?.last?.contains("unsupportedRuntimeCommand") ?? false)
    }

    func testExecuteTraceMalformedCommandIsAttributedWithoutMutatingPingContracts() {
        var state = TopologyEditorState()

        let sourceNodeID = addNode(kind: .pc, at: CGPoint(x: 30, y: 30), to: &state)
        saveRuntimeIP(nodeID: sourceNodeID, ipAddress: "192.168.0.10", subnetMask: "255.255.255.0", state: &state)
        TopologyEditorReducer.reduce(state: &state, action: .startSimulation)

        TopologyEditorReducer.reduce(state: &state, action: .executePing(nodeID: sourceNodeID, command: "trace"))

        XCTAssertEqual(state.lastRuntimeEvent?.code, .traceRejectedMalformedCommand)
        XCTAssertEqual(state.lastRuntimeFault?.category, .commandValidation)
        XCTAssertEqual(state.lastRuntimeFault?.code, "malformedTraceCommand")
        XCTAssertNil(state.lastPingEvent)
    }

    func testExecuteTraceTwentyNodeRuntimeDepthContractIsDeterministic() {
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

        saveRuntimeIP(nodeID: sourceNodeID, ipAddress: "10.20.0.10", subnetMask: "255.255.255.0", state: &state)
        saveRuntimeIP(nodeID: targetNodeID, ipAddress: "10.20.0.20", subnetMask: "255.255.255.0", state: &state)

        TopologyEditorReducer.reduce(state: &state, action: .startSimulation)
        let tickSnapshot = state.simulationTick

        TopologyEditorReducer.reduce(state: &state, action: .executePing(nodeID: sourceNodeID, command: "trace 10.20.0.20"))

        XCTAssertEqual(state.lastRuntimeEvent?.code, .traceSucceeded, "\(phaseTag) expected trace success over 20-node chain")

        let detail = tryUnwrap(state.lastRuntimeEvent?.detail)
        let expectedPath = pathNodeIDs.map(\.uuidString).joined(separator: "->")

        XCTAssertTrue(detail.contains("command=trace"), "\(phaseTag) runtime detail should record trace command")
        XCTAssertTrue(detail.contains("targetIP=10.20.0.20"), "\(phaseTag) runtime detail should retain target attribution")
        XCTAssertTrue(detail.contains("hops=19"), "\(phaseTag) deterministic chain should produce 19 hops")
        XCTAssertTrue(detail.contains("latencyMs=78"), "\(phaseTag) deterministic latency should scale with hop count")
        XCTAssertTrue(detail.contains("path=\(expectedPath)"), "\(phaseTag) runtime detail should expose full path metadata")

        XCTAssertEqual(state.simulationTick, tickSnapshot, "\(phaseTag) trace execution should not mutate simulation tick directly")
        XCTAssertNil(state.lastRuntimeFault)
        XCTAssertNil(state.lastPingEvent)

        XCTAssertEqual(
            Array(state.runtimeConsoleEntriesByNodeID[sourceNodeID]?.suffix(2) ?? []),
            [
                "Trace to 10.20.0.20 succeeded (hops=19, latencyMs=78)",
                "Path: \(pathNodeIDs.map(\.uuidString).joined(separator: " -> "))"
            ]
        )
    }

    func testShortestPathHopCountReturnsExpectedHopsForLinearTopology() {
        var state = TopologyEditorState()

        let sourceNodeID = addNode(kind: .pc, at: CGPoint(x: 20, y: 20), to: &state)
        let switchAID = addNode(kind: .networkSwitch, at: CGPoint(x: 140, y: 20), to: &state)
        let switchBID = addNode(kind: .networkSwitch, at: CGPoint(x: 260, y: 20), to: &state)
        let targetNodeID = addNode(kind: .pc, at: CGPoint(x: 380, y: 20), to: &state)

        connect(sourceNodeID, switchAID, state: &state)
        connect(switchAID, switchBID, state: &state)
        connect(switchBID, targetNodeID, state: &state)

        XCTAssertEqual(state.graph.shortestPathHopCount(from: sourceNodeID, to: targetNodeID), 3)
        XCTAssertEqual(state.graph.shortestPathNodeIDs(from: sourceNodeID, to: targetNodeID), [sourceNodeID, switchAID, switchBID, targetNodeID])
    }

    func testShortestPathHelpersHandleIdentityAndMissingNodesDeterministically() {
        var state = TopologyEditorState()

        let existingNodeID = addNode(kind: .pc, at: CGPoint(x: 20, y: 20), to: &state)
        let missingNodeID = uuid("99999999-9999-9999-9999-999999999999")

        XCTAssertEqual(state.graph.shortestPathHopCount(from: existingNodeID, to: existingNodeID), 0)
        XCTAssertEqual(state.graph.shortestPathNodeIDs(from: existingNodeID, to: existingNodeID), [existingNodeID])
        XCTAssertNil(state.graph.shortestPathHopCount(from: existingNodeID, to: missingNodeID))
        XCTAssertNil(state.graph.shortestPathNodeIDs(from: existingNodeID, to: missingNodeID))
    }

    func testShortestPathNodeIDsPrefersLexicographicallyStableRouteWhenHopsTie() {
        var state = TopologyEditorState()

        let sourceNodeID = addNode(
            kind: .networkSwitch,
            at: CGPoint(x: 40, y: 40),
            nodeID: uuid("10000000-0000-0000-0000-000000000001"),
            to: &state
        )
        let preferredMidNodeID = addNode(
            kind: .networkSwitch,
            at: CGPoint(x: 180, y: 10),
            nodeID: uuid("20000000-0000-0000-0000-000000000002"),
            to: &state
        )
        let alternateMidNodeID = addNode(
            kind: .networkSwitch,
            at: CGPoint(x: 180, y: 100),
            nodeID: uuid("30000000-0000-0000-0000-000000000003"),
            to: &state
        )
        let targetNodeID = addNode(
            kind: .networkSwitch,
            at: CGPoint(x: 340, y: 40),
            nodeID: uuid("40000000-0000-0000-0000-000000000004"),
            to: &state
        )

        // Insert links in non-lexicographic order to prove deterministic route selection is data-order independent.
        connect(sourceNodeID, alternateMidNodeID, state: &state)
        connect(sourceNodeID, preferredMidNodeID, state: &state)
        connect(alternateMidNodeID, targetNodeID, state: &state)
        connect(preferredMidNodeID, targetNodeID, state: &state)

        XCTAssertEqual(state.graph.shortestPathHopCount(from: sourceNodeID, to: targetNodeID), 2)
        XCTAssertEqual(state.graph.shortestPathNodeIDs(from: sourceNodeID, to: targetNodeID), [sourceNodeID, preferredMidNodeID, targetNodeID])
    }

    func testAdjacencyAndReachabilityHelpersPreserveExistingSemantics() {
        var state = TopologyEditorState()

        let sourceNodeID = addNode(kind: .networkSwitch, at: CGPoint(x: 30, y: 30), to: &state)
        let firstNeighborID = addNode(kind: .networkSwitch, at: CGPoint(x: 180, y: 30), to: &state)
        let secondNeighborID = addNode(kind: .networkSwitch, at: CGPoint(x: 180, y: 150), to: &state)
        let disconnectedNodeID = addNode(kind: .networkSwitch, at: CGPoint(x: 340, y: 30), to: &state)

        connect(sourceNodeID, firstNeighborID, state: &state)
        connect(sourceNodeID, secondNeighborID, state: &state)

        XCTAssertEqual(state.graph.adjacentNodeIDs(for: sourceNodeID), [firstNeighborID, secondNeighborID])
        XCTAssertTrue(state.graph.isReachable(from: sourceNodeID, to: secondNeighborID))
        XCTAssertFalse(state.graph.isReachable(from: sourceNodeID, to: disconnectedNodeID))
        XCTAssertNil(state.graph.shortestPathHopCount(from: sourceNodeID, to: disconnectedNodeID))
    }

    func testPersistenceRevisionAdvancesOnlyForDurableMutations() {
        var state = TopologyEditorState()
        let nodeID = addNode(kind: .pc, at: CGPoint(x: 20, y: 20), to: &state)

        XCTAssertEqual(state.persistenceRevision, 1)

        TopologyEditorReducer.reduce(state: &state, action: .setActiveTool(mode: .connect))
        XCTAssertEqual(state.persistenceRevision, 1)

        TopologyEditorReducer.reduce(state: &state, action: .selectSingleNode(nodeID: nodeID))
        XCTAssertEqual(state.persistenceRevision, 1)

        TopologyEditorReducer.reduce(state: &state, action: .panCanvas(delta: CGSize(width: 30, height: -10)))
        XCTAssertEqual(state.persistenceRevision, 2)

        TopologyEditorReducer.reduce(state: &state, action: .zoomCanvas(scaleDelta: 1.2, anchor: CGPoint(x: 0, y: 0)))
        XCTAssertEqual(state.persistenceRevision, 3)

        TopologyEditorReducer.reduce(
            state: &state,
            action: .moveSelectedNodes(delta: CGSize(width: 5, height: 5))
        )
        XCTAssertEqual(state.persistenceRevision, 4)
    }

    func testMalformedOrNoOpDurableActionsDoNotAdvancePersistenceRevision() {
        var state = TopologyEditorState()
        _ = addNode(kind: .pc, at: CGPoint(x: 10, y: 10), to: &state)
        let startingRevision = state.persistenceRevision

        TopologyEditorReducer.reduce(state: &state, action: .moveSelectedNodes(delta: .zero))
        XCTAssertEqual(state.persistenceRevision, startingRevision)

        TopologyEditorReducer.reduce(state: &state, action: .moveSelectedNodes(delta: nil))
        XCTAssertEqual(state.persistenceRevision, startingRevision)

        TopologyEditorReducer.reduce(
            state: &state,
            action: .panCanvas(delta: CGSize(width: .infinity, height: 1))
        )
        XCTAssertEqual(state.persistenceRevision, startingRevision)

        TopologyEditorReducer.reduce(state: &state, action: .zoomCanvas(scaleDelta: 0, anchor: nil))
        XCTAssertEqual(state.persistenceRevision, startingRevision)
    }

    func testDismissPersistenceErrorClearsFailureWithoutAdvancingRevision() {
        var state = TopologyEditorState()
        state.persistenceRevision = 9
        state.recordPersistenceFailure(
            operation: .save,
            code: .fileWriteFailed,
            detail: "sandbox write denied"
        )

        TopologyEditorReducer.reduce(state: &state, action: .dismissPersistenceError)

        XCTAssertNil(state.lastPersistenceError)
        XCTAssertEqual(state.persistenceRevision, 9)
        XCTAssertEqual(state.lastAction, "dismissPersistenceError")
    }

    // MARK: - Helpers

    @discardableResult
    private func addNode(kind: TopologyNodeKind, at position: CGPoint, to state: inout TopologyEditorState) -> UUID {
        addNode(kind: kind, at: position, nodeID: UUID(), to: &state)
    }

    @discardableResult
    private func addNode(
        kind: TopologyNodeKind,
        at position: CGPoint,
        nodeID: UUID,
        to state: inout TopologyEditorState
    ) -> UUID {
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

    private func uuid(_ rawValue: String) -> UUID {
        UUID(uuidString: rawValue) ?? UUID()
    }

    private func tryUnwrap<T>(_ value: T?) -> T {
        guard let value else {
            XCTFail("Expected non-nil value")
            fatalError("Expected non-nil value")
        }
        return value
    }
}
