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
    case runtimeProgramInstalled
    case runtimeDeviceIPRejectedInvalidConfiguration
    case pingSucceeded
    case pingRejectedSimulationStopped
    case pingRejectedMalformedCommand
    case pingRejectedUnknownTarget
    case pingRejectedInvalidSourceConfiguration
    case pingRejectedTopologyUnreachable
    case pingRejectedSubnetMismatch
    case traceSucceeded
    case traceRejectedSimulationStopped
    case traceRejectedMalformedCommand
    case traceRejectedUnknownTarget
    case traceRejectedInvalidSourceConfiguration
    case traceRejectedTopologyUnreachable
    case traceRejectedSubnetMismatch
    case dhcpLeaseAssigned
    case dhcpLeaseReleased
    case dhcpLeaseRejectedSimulationStopped
    case dhcpLeaseRejectedMalformedCommand
    case dhcpLeaseRejectedInvalidConfiguration
    case dhcpLeaseRejectedMissingLease
    case dnsRecordRegistered
    case dnsRecordRemoved
    case dnsRecordRejectedMalformedCommand
    case dnsRecordRejectedSimulationStopped
    case dnsRecordRejectedUnknownHost
    case dnsResolveSucceeded
    case dnsResolveRejectedUnknownHost
    case dnsResolveRejectedSimulationStopped
    case runtimeCommandRejectedUnsupported
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
    case networkService
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

struct TopologyRuntimeDNSRecord: Equatable {
    let hostname: String
    let targetIPAddress: String
}

enum TopologyRuntimeInstallableProgram: String, CaseIterable, Codable, Equatable, Hashable {
    case commandPrompt
    case webServer
    case echoServer
    case dnsServer
    case dhcpServer
}

struct TopologyPersistenceFailure: Equatable {
    let operation: TopologyProjectPersistenceOperation
    let code: TopologyProjectPersistenceErrorCode
    let detail: String
    let occurredAt: Date
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
    var runtimeDHCPLeaseByNodeID: [UUID: TopologyRuntimeDeviceConfiguration] = [:]
    var runtimeDNSRecordsByHostname: [String: TopologyRuntimeDNSRecord] = [:]
    var runtimeInstalledProgramsByNodeID: [UUID: Set<TopologyRuntimeInstallableProgram>] = [:]
    var runtimeConsoleEntriesByNodeID: [UUID: [String]] = [:]
    var lastPingEvent: TopologyRuntimeEvent?
    var lastPingFault: TopologyRuntimeFault?
    var viewport = ViewportTransform.identity
    var persistenceRevision: UInt64 = 0
    var lastPersistedRevision: UInt64 = 0
    var lastPersistenceSaveAt: Date?
    var lastPersistenceLoadAt: Date?
    var lastPersistenceError: TopologyPersistenceFailure?
    var lastRecoveryMessage: String?
    var lastRecoveryAt: Date?
    var lastRecoverySucceeded: Bool?
    var isRecoveryNoticeVisible = false
    var lastValidationError: TopologyValidationErrorCode?
    var lastAction: String?
    var lastActionAt: Date?
    var lastInteractionMode: String?
    var transitionCount = 0

    mutating func recordPersistenceLoad(at date: Date = Date()) {
        lastPersistenceLoadAt = date
        lastPersistedRevision = persistenceRevision
        lastPersistenceError = nil
    }

    mutating func recordPersistenceSave(revision: UInt64, at date: Date = Date()) {
        lastPersistedRevision = max(lastPersistedRevision, revision)
        lastPersistenceSaveAt = date
        lastPersistenceError = nil
    }

    mutating func recordPersistenceFailure(
        operation: TopologyProjectPersistenceOperation,
        code: TopologyProjectPersistenceErrorCode,
        detail: String,
        occurredAt: Date = Date()
    ) {
        lastPersistenceError = TopologyPersistenceFailure(
            operation: operation,
            code: code,
            detail: detail,
            occurredAt: occurredAt
        )
    }

    mutating func dismissPersistenceError() {
        lastPersistenceError = nil
    }

    mutating func recordRecoverySuccess(message: String, at date: Date = Date()) {
        lastRecoveryMessage = message
        lastRecoveryAt = date
        lastRecoverySucceeded = true
        isRecoveryNoticeVisible = true
    }

    mutating func recordRecoveryFailure(message: String, at date: Date = Date()) {
        lastRecoveryMessage = message
        lastRecoveryAt = date
        lastRecoverySucceeded = false
        isRecoveryNoticeVisible = true
    }

    mutating func dismissRecoveryNotice() {
        isRecoveryNoticeVisible = false
    }
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
    case installRuntimeProgram(nodeID: UUID?, program: TopologyRuntimeInstallableProgram?)
    case executePing(nodeID: UUID?, command: String?)
    case moveSelectedNodes(delta: CGSize?)
    case panCanvas(delta: CGSize?)
    case zoomCanvas(scaleDelta: CGFloat?, anchor: CGPoint?)
    case setInteractionMode(mode: String?)
    case dismissRecoveryNotice
    case dismissPersistenceError
}
