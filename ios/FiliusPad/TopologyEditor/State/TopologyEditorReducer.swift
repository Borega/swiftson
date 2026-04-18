import CoreGraphics
import Foundation

enum TopologyEditorReducer {
    static func reduce(state: inout TopologyEditorState, action: TopologyEditorAction) {
        state.transitionCount += 1
        state.lastAction = action.debugName
        state.lastActionAt = Date()
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
            state.pendingConnection = nil

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
            state.activeTool = .select

        case let .selectNodes(selectionRect):
            guard let selectionRect else {
                state.lastValidationError = .malformedActionPayload
                return
            }

            let normalizedRect = selectionRect.standardized
            let selectedNodeIDs = state.graph.nodes
                .filter { normalizedRect.contains($0.position) }
                .map(\.id)

            state.selectedNodeIDs = Set(selectedNodeIDs)
            state.activeTool = .select

        case .clearSelection:
            state.selectedNodeIDs.removeAll()
            state.activeTool = .select

        case let .setActiveTool(mode):
            state.activeTool = mode
            if mode != .connect {
                state.pendingConnection = nil
            }

        case let .startConnection(nodeID, portID):
            guard let nodeID else {
                state.lastValidationError = .missingNodeIdentifier
                return
            }

            guard let sourceNode = state.graph.node(withID: nodeID) else {
                state.lastValidationError = .nodeNotFound
                return
            }

            switch resolvePortID(on: sourceNode, requestedPortID: portID, graph: state.graph) {
            case let .success(sourcePortID):
                state.pendingConnection = TopologyConnectionDraft(sourceNodeID: nodeID, sourcePortID: sourcePortID)
                state.activeTool = .connect
                state.selectedNodeIDs = [nodeID]

            case let .failure(validationError):
                state.lastValidationError = validationError
            }

        case let .completeConnection(nodeID, portID):
            guard let nodeID else {
                state.lastValidationError = .missingNodeIdentifier
                return
            }

            guard let pendingConnection = state.pendingConnection else {
                state.lastValidationError = .connectionSourceNotSelected
                return
            }

            guard let sourceNode = state.graph.node(withID: pendingConnection.sourceNodeID) else {
                state.pendingConnection = nil
                state.lastValidationError = .nodeNotFound
                return
            }

            guard let targetNode = state.graph.node(withID: nodeID) else {
                state.lastValidationError = .nodeNotFound
                return
            }

            guard sourceNode.id != targetNode.id else {
                state.lastValidationError = .selfConnectionNotAllowed
                return
            }

            guard areCompatibleEndpoints(sourceNode, targetNode) else {
                state.lastValidationError = .incompatibleEndpoint
                return
            }

            guard !state.graph.hasConnection(between: sourceNode.id, and: targetNode.id) else {
                state.lastValidationError = .duplicateLink
                return
            }

            guard isPortAvailable(
                sourcePortID: pendingConnection.sourcePortID,
                on: sourceNode,
                in: state.graph
            ) else {
                state.lastValidationError = .noFreePort
                return
            }

            switch resolvePortID(on: targetNode, requestedPortID: portID, graph: state.graph) {
            case let .success(targetPortID):
                let link = TopologyLink(
                    sourceNodeID: sourceNode.id,
                    sourcePortID: pendingConnection.sourcePortID,
                    targetNodeID: targetNode.id,
                    targetPortID: targetPortID
                )
                state.graph.appendLink(link)
                state.selectedNodeIDs = [sourceNode.id, targetNode.id]
                state.pendingConnection = nil
                state.activeTool = .select

            case let .failure(validationError):
                state.lastValidationError = validationError
            }

        case let .moveSelectedNodes(delta):
            guard let delta else {
                state.lastValidationError = .malformedActionPayload
                return
            }

            guard delta != .zero else {
                return
            }

            for nodeID in state.selectedNodeIDs {
                state.graph.moveNode(withID: nodeID, delta: delta)
            }

        case let .panCanvas(delta):
            guard let delta, delta.isFinite else {
                state.lastValidationError = .malformedActionPayload
                return
            }

            state.viewport = state.viewport.panned(by: delta)

        case let .zoomCanvas(scaleDelta, anchor):
            guard let scaleDelta, scaleDelta.isFiniteNumber, scaleDelta > 0 else {
                state.lastValidationError = .malformedActionPayload
                return
            }

            if let anchor, !anchor.isFinite {
                state.lastValidationError = .malformedActionPayload
                return
            }

            state.viewport = state.viewport.zoomed(by: scaleDelta, anchor: anchor)
        }
    }

    private static func areCompatibleEndpoints(_ sourceNode: TopologyNode, _ targetNode: TopologyNode) -> Bool {
        sourceNode.kind == .networkSwitch || targetNode.kind == .networkSwitch
    }

    private static func resolvePortID(
        on node: TopologyNode,
        requestedPortID: UUID?,
        graph: TopologyGraph
    ) -> Result<UUID, TopologyValidationErrorCode> {
        guard !node.ports.isEmpty else {
            return .failure(.noFreePort)
        }

        if let requestedPortID {
            guard node.ports.contains(where: { $0.id == requestedPortID }) else {
                return .failure(.invalidPortIdentifier)
            }

            guard isPortAvailable(sourcePortID: requestedPortID, on: node, in: graph) else {
                return .failure(.noFreePort)
            }

            return .success(requestedPortID)
        }

        guard let availablePortID = node.ports.first(where: {
            isPortAvailable(sourcePortID: $0.id, on: node, in: graph)
        })?.id else {
            return .failure(.noFreePort)
        }

        return .success(availablePortID)
    }

    private static func isPortAvailable(sourcePortID: UUID, on node: TopologyNode, in graph: TopologyGraph) -> Bool {
        guard let port = node.ports.first(where: { $0.id == sourcePortID }) else {
            return false
        }

        return !port.isOccupied && !graph.isPortConnected(nodeID: node.id, portID: sourcePortID)
    }
}

private extension CGSize {
    var isFinite: Bool {
        width.isFiniteNumber && height.isFiniteNumber
    }
}

private extension CGPoint {
    var isFinite: Bool {
        x.isFiniteNumber && y.isFiniteNumber
    }
}

private extension CGFloat {
    var isFiniteNumber: Bool {
        isFinite && !isNaN
    }
}

private extension TopologyEditorAction {
    var debugName: String {
        switch self {
        case .placeNode:
            return "placeNode"
        case .selectSingleNode:
            return "selectSingleNode"
        case .selectNodes:
            return "selectNodes"
        case .clearSelection:
            return "clearSelection"
        case .setActiveTool:
            return "setActiveTool"
        case .startConnection:
            return "startConnection"
        case .completeConnection:
            return "completeConnection"
        case .moveSelectedNodes:
            return "moveSelectedNodes"
        case .panCanvas:
            return "panCanvas"
        case .zoomCanvas:
            return "zoomCanvas"
        }
    }
}
