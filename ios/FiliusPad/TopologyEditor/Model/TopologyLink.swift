import Foundation

struct TopologyLink: Identifiable, Equatable {
    let id: UUID
    let sourceNodeID: UUID
    let sourcePortID: UUID
    let targetNodeID: UUID
    let targetPortID: UUID

    init(
        id: UUID = UUID(),
        sourceNodeID: UUID,
        sourcePortID: UUID,
        targetNodeID: UUID,
        targetPortID: UUID
    ) {
        self.id = id
        self.sourceNodeID = sourceNodeID
        self.sourcePortID = sourcePortID
        self.targetNodeID = targetNodeID
        self.targetPortID = targetPortID
    }
}
