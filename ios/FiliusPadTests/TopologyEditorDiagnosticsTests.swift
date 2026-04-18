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
}
