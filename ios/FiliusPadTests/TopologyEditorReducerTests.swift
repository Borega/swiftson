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
