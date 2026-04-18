import CoreGraphics
import XCTest
@testable import FiliusPad

final class TopologyEditorReducerTests: XCTestCase {
    func testEmptyGraphStartsWithoutSelection() {
        let state = TopologyEditorState()

        XCTAssertTrue(state.graph.nodes.isEmpty)
        XCTAssertTrue(state.graph.links.isEmpty)
        XCTAssertTrue(state.selectedNodeIDs.isEmpty)
        XCTAssertNil(state.lastValidationError)
    }

    func testPlaceNodeAtCanvasEdgeAddsNodeAndSelectsIt() {
        var state = TopologyEditorState()
        let id = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!

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

    func testSelectSingleNodeReplacesPreviousSelection() {
        var state = TopologyEditorState()
        let firstID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let secondID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!

        TopologyEditorReducer.reduce(
            state: &state,
            action: .placeNode(kind: .pc, at: CGPoint(x: 100, y: 100), nodeID: firstID)
        )
        TopologyEditorReducer.reduce(
            state: &state,
            action: .placeNode(kind: .networkSwitch, at: CGPoint(x: 300, y: 200), nodeID: secondID)
        )

        XCTAssertEqual(state.selectedNodeIDs, [secondID])

        TopologyEditorReducer.reduce(
            state: &state,
            action: .selectSingleNode(nodeID: firstID)
        )

        XCTAssertEqual(state.selectedNodeIDs, [firstID])
        XCTAssertNil(state.lastValidationError)
    }

    func testSelectMissingNodeClearsSelectionAndSetsError() {
        var state = TopologyEditorState()
        let placedID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!

        TopologyEditorReducer.reduce(
            state: &state,
            action: .placeNode(kind: .pc, at: CGPoint(x: 10, y: 20), nodeID: placedID)
        )

        TopologyEditorReducer.reduce(
            state: &state,
            action: .selectSingleNode(nodeID: UUID(uuidString: "55555555-5555-5555-5555-555555555555")!)
        )

        XCTAssertTrue(state.selectedNodeIDs.isEmpty)
        XCTAssertEqual(state.lastValidationError, .nodeNotFound)
    }

    func testPlaceNodeWithoutIdentifierSetsValidationErrorAndDoesNotMutateGraph() {
        var state = TopologyEditorState()

        TopologyEditorReducer.reduce(
            state: &state,
            action: .placeNode(kind: .pc, at: CGPoint(x: 50, y: 60), nodeID: nil)
        )

        XCTAssertTrue(state.graph.nodes.isEmpty)
        XCTAssertEqual(state.lastValidationError, .missingNodeIdentifier)
    }

    func testUnsupportedNodeKindSetsValidationErrorAndDoesNotMutateGraph() {
        var state = TopologyEditorState()
        let id = UUID(uuidString: "66666666-6666-6666-6666-666666666666")!

        TopologyEditorReducer.reduce(
            state: &state,
            action: .placeNode(kind: .unsupported, at: CGPoint(x: 50, y: 60), nodeID: id)
        )

        XCTAssertTrue(state.graph.nodes.isEmpty)
        XCTAssertEqual(state.lastValidationError, .unknownNodeKind)
    }
}
