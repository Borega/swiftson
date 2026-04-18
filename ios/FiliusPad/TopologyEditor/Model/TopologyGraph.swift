import CoreGraphics
import Foundation

struct TopologyLinkProjection: Equatable {
    let source: CGPoint
    let target: CGPoint
}

struct TopologyGraph: Equatable {
    var nodes: [TopologyNode] = []
    var links: [TopologyLink] = []

    func nodeIndex(withID id: UUID) -> Int? {
        nodes.firstIndex(where: { $0.id == id })
    }

    func node(withID id: UUID) -> TopologyNode? {
        guard let index = nodeIndex(withID: id) else {
            return nil
        }

        return nodes[index]
    }

    func containsNode(id: UUID) -> Bool {
        nodeIndex(withID: id) != nil
    }

    func containsLink(id: UUID) -> Bool {
        links.contains(where: { $0.id == id })
    }

    func hasConnection(between firstNodeID: UUID, and secondNodeID: UUID) -> Bool {
        links.contains {
            ($0.sourceNodeID == firstNodeID && $0.targetNodeID == secondNodeID)
                || ($0.sourceNodeID == secondNodeID && $0.targetNodeID == firstNodeID)
        }
    }

    func usedPortIDs(for nodeID: UUID) -> Set<UUID> {
        Set(
            links.compactMap { link in
                if link.sourceNodeID == nodeID {
                    return link.sourcePortID
                }

                if link.targetNodeID == nodeID {
                    return link.targetPortID
                }

                return nil
            }
        )
    }

    func isPortConnected(nodeID: UUID, portID: UUID) -> Bool {
        links.contains {
            ($0.sourceNodeID == nodeID && $0.sourcePortID == portID)
                || ($0.targetNodeID == nodeID && $0.targetPortID == portID)
        }
    }

    func availablePortIDs(for nodeID: UUID) -> [UUID] {
        guard let node = node(withID: nodeID) else {
            return []
        }

        let usedPortIDs = usedPortIDs(for: nodeID)

        return node.ports
            .filter { !$0.isOccupied && !usedPortIDs.contains($0.id) }
            .map(\.id)
    }

    func linkProjection(for linkID: UUID) -> TopologyLinkProjection? {
        guard let link = links.first(where: { $0.id == linkID }) else {
            return nil
        }

        return linkProjection(for: link)
    }

    func linkProjection(for link: TopologyLink) -> TopologyLinkProjection? {
        guard
            let sourceNode = node(withID: link.sourceNodeID),
            let targetNode = node(withID: link.targetNodeID)
        else {
            return nil
        }

        return TopologyLinkProjection(source: sourceNode.position, target: targetNode.position)
    }

    mutating func appendNode(_ node: TopologyNode) {
        nodes.append(node)
    }

    mutating func appendLink(_ link: TopologyLink) {
        links.append(link)
    }

    mutating func moveNode(withID id: UUID, delta: CGSize) {
        guard let index = nodeIndex(withID: id) else {
            return
        }

        let current = nodes[index].position
        nodes[index].position = CGPoint(x: current.x + delta.width, y: current.y + delta.height)
    }
}
