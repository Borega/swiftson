import CoreGraphics
import Foundation

enum TopologyNodeKind: String, CaseIterable {
    case pc
    case networkSwitch
    case unsupported
}

struct TopologyPortMetadata: Identifiable, Equatable {
    let id: UUID
    var label: String
    var isOccupied: Bool

    init(id: UUID = UUID(), label: String, isOccupied: Bool = false) {
        self.id = id
        self.label = label
        self.isOccupied = isOccupied
    }
}

struct TopologyNode: Identifiable, Equatable {
    let id: UUID
    var kind: TopologyNodeKind
    var position: CGPoint
    var ports: [TopologyPortMetadata]

    init(
        id: UUID,
        kind: TopologyNodeKind,
        position: CGPoint,
        ports: [TopologyPortMetadata]? = nil
    ) {
        self.id = id
        self.kind = kind
        self.position = position
        self.ports = ports ?? TopologyNode.defaultPorts(for: kind)
    }

    static func defaultPorts(for kind: TopologyNodeKind) -> [TopologyPortMetadata] {
        switch kind {
        case .pc:
            return [TopologyPortMetadata(label: "eth0")]
        case .networkSwitch:
            return (1...8).map { index in
                TopologyPortMetadata(label: "sw\(index)")
            }
        case .unsupported:
            return []
        }
    }
}
