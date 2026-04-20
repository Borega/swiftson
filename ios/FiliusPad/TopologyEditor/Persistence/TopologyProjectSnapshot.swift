import CoreGraphics
import Foundation

enum TopologyProjectSnapshotValidationError: Error, Equatable {
    case duplicateRuntimeDeviceConfiguration(nodeID: UUID)
    case duplicateRuntimeDNSRecord(hostname: String)
}

struct TopologyProjectSnapshot: Codable, Equatable {
    let graph: TopologyGraphSnapshot
    let viewport: ViewportTransformSnapshot
    let runtimeDeviceConfigurations: [TopologyRuntimeDeviceConfigurationSnapshot]
    let runtimeDNSRecords: [TopologyRuntimeDNSRecordSnapshot]
    let persistenceRevision: UInt64

    init(
        graph: TopologyGraphSnapshot,
        viewport: ViewportTransformSnapshot,
        runtimeDeviceConfigurations: [TopologyRuntimeDeviceConfigurationSnapshot],
        runtimeDNSRecords: [TopologyRuntimeDNSRecordSnapshot],
        persistenceRevision: UInt64
    ) {
        self.graph = graph
        self.viewport = viewport
        self.runtimeDeviceConfigurations = runtimeDeviceConfigurations
        self.runtimeDNSRecords = runtimeDNSRecords
        self.persistenceRevision = persistenceRevision
    }

    init(state: TopologyEditorState) {
        graph = TopologyGraphSnapshot(graph: state.graph)
        viewport = ViewportTransformSnapshot(state.viewport)
        runtimeDeviceConfigurations = state.runtimeDeviceConfigurations
            .map { nodeID, configuration in
                TopologyRuntimeDeviceConfigurationSnapshot(
                    nodeID: nodeID,
                    ipAddress: configuration.ipAddress,
                    subnetMask: configuration.subnetMask
                )
            }
            .sorted { $0.nodeID.uuidString < $1.nodeID.uuidString }
        runtimeDNSRecords = state.runtimeDNSRecordsByHostname
            .values
            .map { record in
                TopologyRuntimeDNSRecordSnapshot(
                    hostname: record.hostname,
                    targetIPAddress: record.targetIPAddress
                )
            }
            .sorted { $0.hostname < $1.hostname }
        persistenceRevision = state.persistenceRevision
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case graph
        case viewport
        case runtimeDeviceConfigurations
        case runtimeDNSRecords
        case persistenceRevision
    }

    init(from decoder: Decoder) throws {
        try assertNoUnknownKeys(
            decoder: decoder,
            allowedKeys: CodingKeys.self,
            context: "TopologyProjectSnapshot"
        )

        let container = try decoder.container(keyedBy: CodingKeys.self)
        graph = try container.decode(TopologyGraphSnapshot.self, forKey: .graph)
        viewport = try container.decode(ViewportTransformSnapshot.self, forKey: .viewport)
        runtimeDeviceConfigurations = try container.decode(
            [TopologyRuntimeDeviceConfigurationSnapshot].self,
            forKey: .runtimeDeviceConfigurations
        )
        runtimeDNSRecords = try container.decodeIfPresent(
            [TopologyRuntimeDNSRecordSnapshot].self,
            forKey: .runtimeDNSRecords
        ) ?? []
        persistenceRevision = try container.decodeIfPresent(UInt64.self, forKey: .persistenceRevision) ?? 0
    }

    func toEditorState() throws -> TopologyEditorState {
        if let duplicateNodeID = duplicateRuntimeConfigurationNodeID() {
            throw TopologyProjectSnapshotValidationError.duplicateRuntimeDeviceConfiguration(nodeID: duplicateNodeID)
        }

        if let duplicateHostname = duplicateRuntimeDNSHostname() {
            throw TopologyProjectSnapshotValidationError.duplicateRuntimeDNSRecord(hostname: duplicateHostname)
        }

        var state = TopologyEditorState()
        state.graph = graph.toTopologyGraph()
        state.viewport = viewport.toViewportTransform()
        state.runtimeDeviceConfigurations = Dictionary(
            uniqueKeysWithValues: runtimeDeviceConfigurations.map { snapshot in
                (
                    snapshot.nodeID,
                    TopologyRuntimeDeviceConfiguration(
                        ipAddress: snapshot.ipAddress,
                        subnetMask: snapshot.subnetMask
                    )
                )
            }
        )
        state.runtimeDNSRecordsByHostname = Dictionary(
            uniqueKeysWithValues: runtimeDNSRecords.map { snapshot in
                (
                    snapshot.hostname,
                    TopologyRuntimeDNSRecord(
                        hostname: snapshot.hostname,
                        targetIPAddress: snapshot.targetIPAddress
                    )
                )
            }
        )
        state.persistenceRevision = persistenceRevision
        state.lastPersistedRevision = persistenceRevision

        return state
    }

    private func duplicateRuntimeConfigurationNodeID() -> UUID? {
        var seenNodeIDs: Set<UUID> = []

        for entry in runtimeDeviceConfigurations {
            if !seenNodeIDs.insert(entry.nodeID).inserted {
                return entry.nodeID
            }
        }

        return nil
    }

    private func duplicateRuntimeDNSHostname() -> String? {
        var seenHostnames: Set<String> = []

        for record in runtimeDNSRecords {
            if !seenHostnames.insert(record.hostname).inserted {
                return record.hostname
            }
        }

        return nil
    }
}

struct TopologyGraphSnapshot: Codable, Equatable {
    let nodes: [TopologyNodeSnapshot]
    let links: [TopologyLinkSnapshot]

    init(nodes: [TopologyNodeSnapshot], links: [TopologyLinkSnapshot]) {
        self.nodes = nodes
        self.links = links
    }

    init(graph: TopologyGraph) {
        nodes = graph.nodes.map(TopologyNodeSnapshot.init)
        links = graph.links.map(TopologyLinkSnapshot.init)
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case nodes
        case links
    }

    init(from decoder: Decoder) throws {
        try assertNoUnknownKeys(
            decoder: decoder,
            allowedKeys: CodingKeys.self,
            context: "TopologyGraphSnapshot"
        )

        let container = try decoder.container(keyedBy: CodingKeys.self)
        nodes = try container.decode([TopologyNodeSnapshot].self, forKey: .nodes)
        links = try container.decode([TopologyLinkSnapshot].self, forKey: .links)
    }

    func toTopologyGraph() -> TopologyGraph {
        TopologyGraph(
            nodes: nodes.map(\.toTopologyNode),
            links: links.map(\.toTopologyLink)
        )
    }
}

struct TopologyNodeSnapshot: Codable, Equatable {
    let id: UUID
    let kind: TopologyNodeKind
    let position: TopologyPointSnapshot
    let ports: [TopologyPortSnapshot]

    init(
        id: UUID,
        kind: TopologyNodeKind,
        position: TopologyPointSnapshot,
        ports: [TopologyPortSnapshot]
    ) {
        self.id = id
        self.kind = kind
        self.position = position
        self.ports = ports
    }

    init(_ node: TopologyNode) {
        id = node.id
        kind = node.kind
        position = TopologyPointSnapshot(node.position)
        ports = node.ports.map(TopologyPortSnapshot.init)
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case id
        case kind
        case position
        case ports
    }

    init(from decoder: Decoder) throws {
        try assertNoUnknownKeys(
            decoder: decoder,
            allowedKeys: CodingKeys.self,
            context: "TopologyNodeSnapshot"
        )

        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        kind = try container.decode(TopologyNodeKind.self, forKey: .kind)
        position = try container.decode(TopologyPointSnapshot.self, forKey: .position)
        ports = try container.decode([TopologyPortSnapshot].self, forKey: .ports)
    }

    var toTopologyNode: TopologyNode {
        TopologyNode(
            id: id,
            kind: kind,
            position: position.toCGPoint,
            ports: ports.map(\.toPortMetadata)
        )
    }
}

struct TopologyPortSnapshot: Codable, Equatable {
    let id: UUID
    let label: String
    let isOccupied: Bool

    init(id: UUID, label: String, isOccupied: Bool) {
        self.id = id
        self.label = label
        self.isOccupied = isOccupied
    }

    init(_ port: TopologyPortMetadata) {
        id = port.id
        label = port.label
        isOccupied = port.isOccupied
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case id
        case label
        case isOccupied
    }

    init(from decoder: Decoder) throws {
        try assertNoUnknownKeys(
            decoder: decoder,
            allowedKeys: CodingKeys.self,
            context: "TopologyPortSnapshot"
        )

        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        label = try container.decode(String.self, forKey: .label)
        isOccupied = try container.decode(Bool.self, forKey: .isOccupied)
    }

    var toPortMetadata: TopologyPortMetadata {
        TopologyPortMetadata(id: id, label: label, isOccupied: isOccupied)
    }
}

struct TopologyLinkSnapshot: Codable, Equatable {
    let id: UUID
    let sourceNodeID: UUID
    let sourcePortID: UUID
    let targetNodeID: UUID
    let targetPortID: UUID

    init(
        id: UUID,
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

    init(_ link: TopologyLink) {
        id = link.id
        sourceNodeID = link.sourceNodeID
        sourcePortID = link.sourcePortID
        targetNodeID = link.targetNodeID
        targetPortID = link.targetPortID
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case id
        case sourceNodeID
        case sourcePortID
        case targetNodeID
        case targetPortID
    }

    init(from decoder: Decoder) throws {
        try assertNoUnknownKeys(
            decoder: decoder,
            allowedKeys: CodingKeys.self,
            context: "TopologyLinkSnapshot"
        )

        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        sourceNodeID = try container.decode(UUID.self, forKey: .sourceNodeID)
        sourcePortID = try container.decode(UUID.self, forKey: .sourcePortID)
        targetNodeID = try container.decode(UUID.self, forKey: .targetNodeID)
        targetPortID = try container.decode(UUID.self, forKey: .targetPortID)
    }

    var toTopologyLink: TopologyLink {
        TopologyLink(
            id: id,
            sourceNodeID: sourceNodeID,
            sourcePortID: sourcePortID,
            targetNodeID: targetNodeID,
            targetPortID: targetPortID
        )
    }
}

struct TopologyRuntimeDeviceConfigurationSnapshot: Codable, Equatable {
    let nodeID: UUID
    let ipAddress: String
    let subnetMask: String

    enum CodingKeys: String, CodingKey, CaseIterable {
        case nodeID
        case ipAddress
        case subnetMask
    }

    init(nodeID: UUID, ipAddress: String, subnetMask: String) {
        self.nodeID = nodeID
        self.ipAddress = ipAddress
        self.subnetMask = subnetMask
    }

    init(from decoder: Decoder) throws {
        try assertNoUnknownKeys(
            decoder: decoder,
            allowedKeys: CodingKeys.self,
            context: "TopologyRuntimeDeviceConfigurationSnapshot"
        )

        let container = try decoder.container(keyedBy: CodingKeys.self)
        nodeID = try container.decode(UUID.self, forKey: .nodeID)
        ipAddress = try container.decode(String.self, forKey: .ipAddress)
        subnetMask = try container.decode(String.self, forKey: .subnetMask)
    }
}

struct TopologyRuntimeDNSRecordSnapshot: Codable, Equatable {
    let hostname: String
    let targetIPAddress: String

    enum CodingKeys: String, CodingKey, CaseIterable {
        case hostname
        case targetIPAddress
    }

    init(hostname: String, targetIPAddress: String) {
        self.hostname = hostname
        self.targetIPAddress = targetIPAddress
    }

    init(from decoder: Decoder) throws {
        try assertNoUnknownKeys(
            decoder: decoder,
            allowedKeys: CodingKeys.self,
            context: "TopologyRuntimeDNSRecordSnapshot"
        )

        let container = try decoder.container(keyedBy: CodingKeys.self)
        hostname = try container.decode(String.self, forKey: .hostname)
        targetIPAddress = try container.decode(String.self, forKey: .targetIPAddress)
    }
}

struct ViewportTransformSnapshot: Codable, Equatable {
    let offset: TopologySizeSnapshot
    let scale: Double

    init(offset: TopologySizeSnapshot, scale: Double) {
        self.offset = offset
        self.scale = scale
    }

    init(_ viewportTransform: ViewportTransform) {
        offset = TopologySizeSnapshot(viewportTransform.offset)
        scale = Double(viewportTransform.scale)
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case offset
        case scale
    }

    init(from decoder: Decoder) throws {
        try assertNoUnknownKeys(
            decoder: decoder,
            allowedKeys: CodingKeys.self,
            context: "ViewportTransformSnapshot"
        )

        let container = try decoder.container(keyedBy: CodingKeys.self)
        offset = try container.decode(TopologySizeSnapshot.self, forKey: .offset)
        scale = try container.decode(Double.self, forKey: .scale)
    }

    func toViewportTransform() -> ViewportTransform {
        ViewportTransform(offset: offset.toCGSize, scale: CGFloat(scale))
    }
}

struct TopologyPointSnapshot: Codable, Equatable {
    let x: Double
    let y: Double

    init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    init(_ point: CGPoint) {
        x = Double(point.x)
        y = Double(point.y)
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case x
        case y
    }

    init(from decoder: Decoder) throws {
        try assertNoUnknownKeys(
            decoder: decoder,
            allowedKeys: CodingKeys.self,
            context: "TopologyPointSnapshot"
        )

        let container = try decoder.container(keyedBy: CodingKeys.self)
        x = try container.decode(Double.self, forKey: .x)
        y = try container.decode(Double.self, forKey: .y)
    }

    var toCGPoint: CGPoint {
        CGPoint(x: x, y: y)
    }
}

struct TopologySizeSnapshot: Codable, Equatable {
    let width: Double
    let height: Double

    init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }

    init(_ size: CGSize) {
        width = Double(size.width)
        height = Double(size.height)
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case width
        case height
    }

    init(from decoder: Decoder) throws {
        try assertNoUnknownKeys(
            decoder: decoder,
            allowedKeys: CodingKeys.self,
            context: "TopologySizeSnapshot"
        )

        let container = try decoder.container(keyedBy: CodingKeys.self)
        width = try container.decode(Double.self, forKey: .width)
        height = try container.decode(Double.self, forKey: .height)
    }

    var toCGSize: CGSize {
        CGSize(width: width, height: height)
    }
}

extension TopologyNodeKind: Codable {}
