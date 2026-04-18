import CoreGraphics
import Foundation

enum TopologyEditorToolMode: Equatable {
    case select
    case place(TopologyNodeKind)
    case connect
}

struct TopologyConnectionDraft: Equatable {
    let sourceNodeID: UUID
    let sourcePortID: UUID
}

struct TopologyEditorState: Equatable {
    var graph = TopologyGraph()
    var selectedNodeIDs: Set<UUID> = []
    var activeTool: TopologyEditorToolMode = .select
    var pendingConnection: TopologyConnectionDraft?
    var viewport = ViewportTransform.identity
    var lastValidationError: TopologyValidationErrorCode?
    var lastAction: String?
    var lastActionAt: Date?
    var transitionCount = 0
}

enum TopologyEditorAction: Equatable {
    case placeNode(kind: TopologyNodeKind, at: CGPoint, nodeID: UUID?)
    case selectSingleNode(nodeID: UUID?)
    case selectNodes(in: CGRect?)
    case clearSelection
    case setActiveTool(mode: TopologyEditorToolMode)
    case startConnection(nodeID: UUID?, portID: UUID?)
    case completeConnection(nodeID: UUID?, portID: UUID?)
    case moveSelectedNodes(delta: CGSize?)
    case panCanvas(delta: CGSize?)
    case zoomCanvas(scaleDelta: CGFloat?, anchor: CGPoint?)
}
