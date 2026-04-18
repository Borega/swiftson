import CoreGraphics
import Foundation

enum TopologyValidationErrorCode: String, Equatable {
    case missingNodeIdentifier
    case unknownNodeKind
    case nodeNotFound
}

enum TopologyEditorToolMode: Equatable {
    case select
    case place(TopologyNodeKind)
    case connect
}

struct TopologyEditorState: Equatable {
    var graph = TopologyGraph()
    var selectedNodeIDs: Set<UUID> = []
    var activeTool: TopologyEditorToolMode = .select
    var pendingConnectionSourceNodeID: UUID?
    var lastValidationError: TopologyValidationErrorCode?
    var transitionCount = 0
}

enum TopologyEditorAction: Equatable {
    case placeNode(kind: TopologyNodeKind, at: CGPoint, nodeID: UUID?)
    case selectSingleNode(nodeID: UUID?)
    case clearSelection
}

enum TopologyEditorReducer {
    static func reduce(state: inout TopologyEditorState, action: TopologyEditorAction) {
        state.transitionCount += 1
        state.lastValidationError = nil

        switch action {
        case let .placeNode(kind, point, nodeID):
            guard let nodeID else {
                state.lastValidationError = .missingNodeIdentifier
                return
            }

            guard kind != .unsupported else {
                state.lastValidationError = .unknownNodeKind
                return
            }

            let node = TopologyNode(id: nodeID, kind: kind, position: point)
            state.graph.appendNode(node)
            state.selectedNodeIDs = [nodeID]
            state.activeTool = .select

        case let .selectSingleNode(nodeID):
            guard let nodeID else {
                state.selectedNodeIDs = []
                state.lastValidationError = .missingNodeIdentifier
                return
            }

            guard state.graph.containsNode(id: nodeID) else {
                state.selectedNodeIDs = []
                state.lastValidationError = .nodeNotFound
                return
            }

            state.selectedNodeIDs = [nodeID]

        case .clearSelection:
            state.selectedNodeIDs.removeAll()
        }
    }
}
