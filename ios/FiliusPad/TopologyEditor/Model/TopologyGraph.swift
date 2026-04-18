import Foundation

struct TopologyGraph: Equatable {
    var nodes: [TopologyNode] = []
    var links: [TopologyLink] = []

    func node(withID id: UUID) -> TopologyNode? {
        nodes.first(where: { $0.id == id })
    }

    func containsNode(id: UUID) -> Bool {
        node(withID: id) != nil
    }

    mutating func appendNode(_ node: TopologyNode) {
        nodes.append(node)
    }

    mutating func setNodeSelection(id: UUID?) -> Set<UUID> {
        guard let id else { return [] }
        return containsNode(id: id) ? [id] : []
    }
}
