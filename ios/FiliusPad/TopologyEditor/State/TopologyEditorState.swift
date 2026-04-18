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

enum TopologySimulationPhase: String, Equatable {
    case stopped
    case running
}

enum TopologyRuntimeEventCode: String, Equatable {
    case simulationStarted
    case simulationStartIgnoredAlreadyRunning
    case simulationStopped
    case simulationStopIgnoredAlreadyStopped
    case simulationTickAdvanced
    case simulationTickIgnoredWhileStopped
    case simulationFaultReported
    case simulationFaultRejectedMalformedPayload
    case runtimeDeviceOpened
    case runtimeDeviceCloseIgnoredAlreadyClosed
    case runtimeDeviceClosed
    case runtimeDeviceIPSaved
    case runtimeDeviceIPRejectedInvalidConfiguration
    case pingSucceeded
    case pingRejectedSimulationStopped
    case pingRejectedMalformedCommand
    case pingRejectedUnknownTarget
    case pingRejectedInvalidSourceConfiguration
    case pingRejectedTopologyUnreachable
    case pingRejectedSubnetMismatch
}

struct TopologyRuntimeEvent: Equatable {
    let code: TopologyRuntimeEventCode
    let detail: String?
}

enum TopologyRuntimeFaultCategory: String, Equatable {
    case runtimeFault
    case malformedRuntimePayload
    case commandValidation
    case networkConfiguration
    case networkRouting
}

struct TopologyRuntimeFault: Equatable {
    let category: TopologyRuntimeFaultCategory
    let code: String
    let message: String
}

struct TopologyRuntimeDeviceConfiguration: Equatable {
    let ipAddress: String
    let subnetMask: String
}

struct TopologyEditorState: Equatable {
    var graph = TopologyGraph()
    var selectedNodeIDs: Set<UUID> = []
    var activeTool: TopologyEditorToolMode = .select
    var pendingConnection: TopologyConnectionDraft?
    var simulationPhase: TopologySimulationPhase = .stopped
    var simulationTick: UInt64 = 0
    var lastRuntimeEvent: TopologyRuntimeEvent?
    var lastRuntimeFault: TopologyRuntimeFault?
    var openedRuntimeDeviceID: UUID?
    var runtimeDeviceConfigurations: [UUID: TopologyRuntimeDeviceConfiguration] = [:]
    var runtimeConsoleEntriesByNodeID: [UUID: [String]] = [:]
    var lastPingEvent: TopologyRuntimeEvent?
    var lastPingFault: TopologyRuntimeFault?
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
    case startSimulation
    case stopSimulation
    case simulationTick(step: UInt64?)
    case simulationFault(code: String?, message: String?)
    case openRuntimeDevice(nodeID: UUID?)
    case closeRuntimeDevice
    case saveRuntimeDeviceIP(nodeID: UUID?, ipAddress: String?, subnetMask: String?)
    case executePing(nodeID: UUID?, command: String?)
    case moveSelectedNodes(delta: CGSize?)
    case panCanvas(delta: CGSize?)
    case zoomCanvas(scaleDelta: CGFloat?, anchor: CGPoint?)
}
