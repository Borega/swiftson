import CoreGraphics
import Foundation

enum TopologyEditorReducer {
    private static let maxRuntimeConsoleEntriesPerDevice = 60

    private enum RuntimeCommand {
        case ping(String)
        case trace(String)
    }

    private enum RuntimeCommandParseResult {
        case success(RuntimeCommand)
        case malformed(command: String?, reason: String)
        case unsupported(command: String)
    }

    private enum PortResolutionResult {
        case success(UUID)
        case failure(TopologyValidationErrorCode)
    }

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
            advancePersistenceRevision(state: &state)

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
                advancePersistenceRevision(state: &state)

            case let .failure(validationError):
                state.lastValidationError = validationError
            }

        case .startSimulation:
            guard state.simulationPhase != .running else {
                recordRuntimeEvent(
                    state: &state,
                    code: .simulationStartIgnoredAlreadyRunning
                )
                return
            }

            state.simulationPhase = .running
            state.lastRuntimeFault = nil
            recordRuntimeEvent(state: &state, code: .simulationStarted)

        case .stopSimulation:
            guard state.simulationPhase != .stopped else {
                recordRuntimeEvent(
                    state: &state,
                    code: .simulationStopIgnoredAlreadyStopped
                )
                return
            }

            state.simulationPhase = .stopped
            recordRuntimeEvent(state: &state, code: .simulationStopped)

        case let .simulationTick(step):
            guard let step, step > 0 else {
                setMalformedRuntimePayload(
                    state: &state,
                    reason: "simulationTick requires a positive step"
                )
                return
            }

            guard state.simulationPhase == .running else {
                recordRuntimeEvent(
                    state: &state,
                    code: .simulationTickIgnoredWhileStopped,
                    detail: "phase=\(state.simulationPhase.rawValue),step=\(step)"
                )
                return
            }

            let (nextTick, overflowed) = state.simulationTick.addingReportingOverflow(step)
            guard !overflowed else {
                state.lastRuntimeFault = TopologyRuntimeFault(
                    category: .runtimeFault,
                    code: "tickOverflow",
                    message: "Simulation tick overflowed UInt64 capacity"
                )
                recordRuntimeEvent(
                    state: &state,
                    code: .simulationFaultReported,
                    detail: "tickOverflow"
                )
                return
            }

            state.simulationTick = nextTick
            state.lastRuntimeFault = nil
            recordRuntimeEvent(
                state: &state,
                code: .simulationTickAdvanced,
                detail: "step=\(step)"
            )

        case let .simulationFault(code, message):
            guard let normalizedCode = normalizedRuntimeValue(code) else {
                setMalformedRuntimePayload(
                    state: &state,
                    reason: "simulationFault requires a non-empty code"
                )
                return
            }

            state.lastRuntimeFault = TopologyRuntimeFault(
                category: .runtimeFault,
                code: normalizedCode,
                message: normalizedRuntimeValue(message) ?? "unspecified"
            )
            recordRuntimeEvent(
                state: &state,
                code: .simulationFaultReported,
                detail: normalizedCode
            )

        case let .openRuntimeDevice(nodeID):
            guard let nodeID else {
                setMalformedRuntimePayload(
                    state: &state,
                    reason: "openRuntimeDevice requires nodeID"
                )
                return
            }

            guard state.graph.containsNode(id: nodeID) else {
                state.lastValidationError = .nodeNotFound
                state.lastRuntimeFault = TopologyRuntimeFault(
                    category: .networkRouting,
                    code: "runtimeDeviceNotFound",
                    message: "Cannot open runtime panel for unknown node \(nodeID.uuidString)"
                )
                recordRuntimeEvent(state: &state, code: .simulationFaultReported, detail: "runtimeDeviceNotFound")
                return
            }

            state.openedRuntimeDeviceID = nodeID
            state.lastRuntimeFault = nil
            recordRuntimeEvent(state: &state, code: .runtimeDeviceOpened, detail: nodeID.uuidString)

        case .closeRuntimeDevice:
            guard let previousNodeID = state.openedRuntimeDeviceID else {
                recordRuntimeEvent(state: &state, code: .runtimeDeviceCloseIgnoredAlreadyClosed)
                return
            }

            state.openedRuntimeDeviceID = nil
            recordRuntimeEvent(state: &state, code: .runtimeDeviceClosed, detail: previousNodeID.uuidString)

        case let .saveRuntimeDeviceIP(nodeID, ipAddress, subnetMask):
            guard let nodeID else {
                setMalformedRuntimePayload(
                    state: &state,
                    reason: "saveRuntimeDeviceIP requires nodeID"
                )
                return
            }

            guard state.graph.containsNode(id: nodeID) else {
                state.lastValidationError = .nodeNotFound
                state.lastRuntimeFault = TopologyRuntimeFault(
                    category: .networkConfiguration,
                    code: "runtimeDeviceNotFound",
                    message: "Cannot save IP for unknown node \(nodeID.uuidString)"
                )
                recordRuntimeEvent(state: &state, code: .runtimeDeviceIPRejectedInvalidConfiguration, detail: "runtimeDeviceNotFound")
                return
            }

            guard let normalizedIPAddress = normalizedIPv4Address(ipAddress) else {
                state.lastRuntimeFault = TopologyRuntimeFault(
                    category: .networkConfiguration,
                    code: "invalidIPv4Address",
                    message: "IP address must use four octets between 0 and 255"
                )
                recordRuntimeEvent(state: &state, code: .runtimeDeviceIPRejectedInvalidConfiguration, detail: "invalidIPv4Address")
                return
            }

            guard let normalizedSubnetMask = normalizedSubnetMask(subnetMask) else {
                state.lastRuntimeFault = TopologyRuntimeFault(
                    category: .networkConfiguration,
                    code: "invalidSubnetMask",
                    message: "Subnet mask must be a contiguous IPv4 mask"
                )
                recordRuntimeEvent(state: &state, code: .runtimeDeviceIPRejectedInvalidConfiguration, detail: "invalidSubnetMask")
                return
            }

            state.runtimeDeviceConfigurations[nodeID] = TopologyRuntimeDeviceConfiguration(
                ipAddress: normalizedIPAddress,
                subnetMask: normalizedSubnetMask
            )
            state.lastRuntimeFault = nil
            advancePersistenceRevision(state: &state)
            recordRuntimeEvent(
                state: &state,
                code: .runtimeDeviceIPSaved,
                detail: "node=\(nodeID.uuidString),ip=\(normalizedIPAddress),subnet=\(normalizedSubnetMask)"
            )

        case let .executePing(nodeID, command):
            guard let sourceNodeID = nodeID else {
                setMalformedPingPayload(
                    state: &state,
                    detail: "missing source node identifier"
                )
                return
            }

            guard state.graph.containsNode(id: sourceNodeID) else {
                setPingFailure(
                    state: &state,
                    sourceNodeID: sourceNodeID,
                    eventCode: .pingRejectedInvalidSourceConfiguration,
                    faultCategory: .networkConfiguration,
                    faultCode: "sourceNodeNotFound",
                    message: "Ping source node does not exist in graph",
                    detail: "sourceNodeNotFound"
                )
                return
            }

            let normalizedCommand = normalizedRuntimeValue(command) ?? ""
            appendConsoleLine(
                state: &state,
                nodeID: sourceNodeID,
                line: "> \(normalizedCommand.isEmpty ? "(empty)" : normalizedCommand)"
            )

            switch parseRuntimeCommand(normalizedCommand) {
            case let .unsupported(command):
                setRuntimeCommandFailure(
                    state: &state,
                    sourceNodeID: sourceNodeID,
                    eventCode: .runtimeCommandRejectedUnsupported,
                    faultCode: "unsupportedRuntimeCommand",
                    message: "Unsupported runtime command '\(command)'. Supported commands are: ping, trace",
                    detail: "unsupportedRuntimeCommand"
                )
                return

            case let .malformed(command, reason):
                if command == "trace" {
                    setTraceFailure(
                        state: &state,
                        sourceNodeID: sourceNodeID,
                        eventCode: .traceRejectedMalformedCommand,
                        faultCategory: .commandValidation,
                        faultCode: "malformedTraceCommand",
                        message: reason,
                        detail: "malformedTraceCommand"
                    )
                    return
                }

                setPingFailure(
                    state: &state,
                    sourceNodeID: sourceNodeID,
                    eventCode: .pingRejectedMalformedCommand,
                    faultCategory: .commandValidation,
                    faultCode: "malformedPingCommand",
                    message: reason,
                    detail: "malformedPingCommand"
                )
                return

            case let .success(runtimeCommand):
                switch runtimeCommand {
                case let .ping(targetIPAddress):
                    guard state.simulationPhase == .running else {
                        setPingFailure(
                            state: &state,
                            sourceNodeID: sourceNodeID,
                            eventCode: .pingRejectedSimulationStopped,
                            faultCategory: .runtimeFault,
                            faultCode: "pingWhileSimulationStopped",
                            message: "Ping commands require a running simulation",
                            detail: "phase=\(state.simulationPhase.rawValue)"
                        )
                        return
                    }

                    executePingCommand(
                        state: &state,
                        sourceNodeID: sourceNodeID,
                        targetIPAddress: targetIPAddress
                    )

                case let .trace(targetIPAddress):
                    guard state.simulationPhase == .running else {
                        setTraceFailure(
                            state: &state,
                            sourceNodeID: sourceNodeID,
                            eventCode: .traceRejectedSimulationStopped,
                            faultCategory: .runtimeFault,
                            faultCode: "traceWhileSimulationStopped",
                            message: "Trace commands require a running simulation",
                            detail: "phase=\(state.simulationPhase.rawValue)"
                        )
                        return
                    }

                    executeTraceCommand(
                        state: &state,
                        sourceNodeID: sourceNodeID,
                        targetIPAddress: targetIPAddress
                    )
                }
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
            advancePersistenceRevision(state: &state)

        case let .panCanvas(delta):
            guard let delta, isFiniteSize(delta) else {
                state.lastValidationError = .malformedActionPayload
                return
            }

            state.viewport = state.viewport.panned(by: delta)
            advancePersistenceRevision(state: &state)

        case let .zoomCanvas(scaleDelta, anchor):
            guard let scaleDelta, isFiniteScalar(scaleDelta), scaleDelta > 0 else {
                state.lastValidationError = .malformedActionPayload
                return
            }

            if let anchor, !isFinitePoint(anchor) {
                state.lastValidationError = .malformedActionPayload
                return
            }

            state.viewport = state.viewport.zoomed(by: scaleDelta, anchor: anchor)
            advancePersistenceRevision(state: &state)

        case let .setInteractionMode(mode):
            state.lastInteractionMode = normalizedRuntimeValue(mode) ?? "none"

        case .dismissRecoveryNotice:
            state.dismissRecoveryNotice()

        case .dismissPersistenceError:
            state.dismissPersistenceError()
        }
    }

    private static func advancePersistenceRevision(state: inout TopologyEditorState) {
        let (nextRevision, overflowed) = state.persistenceRevision.addingReportingOverflow(1)
        state.persistenceRevision = overflowed ? UInt64.max : nextRevision
    }

    private static func recordRuntimeEvent(
        state: inout TopologyEditorState,
        code: TopologyRuntimeEventCode,
        detail: String? = nil
    ) {
        state.lastRuntimeEvent = TopologyRuntimeEvent(code: code, detail: detail)
    }

    private static func setMalformedRuntimePayload(state: inout TopologyEditorState, reason: String) {
        state.lastRuntimeFault = TopologyRuntimeFault(
            category: .malformedRuntimePayload,
            code: "malformedRuntimePayload",
            message: reason
        )
        recordRuntimeEvent(
            state: &state,
            code: .simulationFaultRejectedMalformedPayload,
            detail: reason
        )
    }

    private static func setMalformedPingPayload(state: inout TopologyEditorState, detail: String) {
        let fault = TopologyRuntimeFault(
            category: .commandValidation,
            code: "malformedPingCommand",
            message: detail
        )
        state.lastPingFault = fault
        state.lastRuntimeFault = fault
        state.lastPingEvent = TopologyRuntimeEvent(code: .pingRejectedMalformedCommand, detail: detail)
        recordRuntimeEvent(state: &state, code: .pingRejectedMalformedCommand, detail: detail)
    }

    private static func setPingFailure(
        state: inout TopologyEditorState,
        sourceNodeID: UUID,
        eventCode: TopologyRuntimeEventCode,
        faultCategory: TopologyRuntimeFaultCategory,
        faultCode: String,
        message: String,
        detail: String
    ) {
        let fault = TopologyRuntimeFault(
            category: faultCategory,
            code: faultCode,
            message: message
        )
        state.lastPingFault = fault
        state.lastRuntimeFault = fault
        state.lastPingEvent = TopologyRuntimeEvent(code: eventCode, detail: detail)
        recordRuntimeEvent(state: &state, code: eventCode, detail: detail)
        appendConsoleLine(state: &state, nodeID: sourceNodeID, line: "Ping failed: \(faultCode) — \(message)")
    }

    private static func setTraceFailure(
        state: inout TopologyEditorState,
        sourceNodeID: UUID,
        eventCode: TopologyRuntimeEventCode,
        faultCategory: TopologyRuntimeFaultCategory,
        faultCode: String,
        message: String,
        detail: String
    ) {
        let fault = TopologyRuntimeFault(
            category: faultCategory,
            code: faultCode,
            message: message
        )
        state.lastRuntimeFault = fault
        recordRuntimeEvent(state: &state, code: eventCode, detail: detail)
        appendConsoleLine(state: &state, nodeID: sourceNodeID, line: "Trace failed: \(faultCode) — \(message)")
    }

    private static func setRuntimeCommandFailure(
        state: inout TopologyEditorState,
        sourceNodeID: UUID,
        eventCode: TopologyRuntimeEventCode,
        faultCode: String,
        message: String,
        detail: String
    ) {
        let fault = TopologyRuntimeFault(
            category: .commandValidation,
            code: faultCode,
            message: message
        )
        state.lastRuntimeFault = fault
        recordRuntimeEvent(state: &state, code: eventCode, detail: detail)
        appendConsoleLine(state: &state, nodeID: sourceNodeID, line: "Command failed: \(faultCode) — \(message)")
    }

    private static func executePingCommand(
        state: inout TopologyEditorState,
        sourceNodeID: UUID,
        targetIPAddress: String
    ) {
        guard let sourceConfiguration = state.runtimeDeviceConfigurations[sourceNodeID] else {
            setPingFailure(
                state: &state,
                sourceNodeID: sourceNodeID,
                eventCode: .pingRejectedInvalidSourceConfiguration,
                faultCategory: .networkConfiguration,
                faultCode: "sourceConfigurationMissing",
                message: "Configure source IP and subnet before pinging",
                detail: "sourceConfigurationMissing"
            )
            return
        }

        let targetNodeIDs = state.runtimeDeviceConfigurations
            .filter { $0.value.ipAddress == targetIPAddress }
            .map(\.key)
            .sorted { $0.uuidString < $1.uuidString }

        guard targetNodeIDs.count == 1, let targetNodeID = targetNodeIDs.first else {
            setPingFailure(
                state: &state,
                sourceNodeID: sourceNodeID,
                eventCode: .pingRejectedUnknownTarget,
                faultCategory: .networkRouting,
                faultCode: "pingTargetUnknown",
                message: "No unique node is configured with target \(targetIPAddress)",
                detail: "pingTargetUnknown"
            )
            return
        }

        guard state.graph.containsNode(id: targetNodeID),
              let targetConfiguration = state.runtimeDeviceConfigurations[targetNodeID] else {
            setPingFailure(
                state: &state,
                sourceNodeID: sourceNodeID,
                eventCode: .pingRejectedUnknownTarget,
                faultCategory: .networkRouting,
                faultCode: "pingTargetUnknown",
                message: "Target node is unavailable in topology",
                detail: "pingTargetUnknown"
            )
            return
        }

        guard areInSameSubnet(source: sourceConfiguration, target: targetConfiguration) else {
            setPingFailure(
                state: &state,
                sourceNodeID: sourceNodeID,
                eventCode: .pingRejectedSubnetMismatch,
                faultCategory: .networkRouting,
                faultCode: "pingSubnetMismatch",
                message: "Source and target are not in the same subnet",
                detail: "pingSubnetMismatch"
            )
            return
        }

        guard let pathNodeIDs = state.graph.shortestPathNodeIDs(from: sourceNodeID, to: targetNodeID) else {
            setPingFailure(
                state: &state,
                sourceNodeID: sourceNodeID,
                eventCode: .pingRejectedTopologyUnreachable,
                faultCategory: .networkRouting,
                faultCode: "pingTargetUnreachable",
                message: "No topology path exists between source and target",
                detail: "pingTargetUnreachable"
            )
            return
        }

        let hopCount = max(0, pathNodeIDs.count - 1)
        let latencyMilliseconds = deterministicLatencyMilliseconds(forHopCount: hopCount)

        state.lastPingFault = nil
        state.lastRuntimeFault = nil

        let successDetail = routeDetail(
            command: "ping",
            sourceNodeID: sourceNodeID,
            targetNodeID: targetNodeID,
            targetIPAddress: targetIPAddress,
            hopCount: hopCount,
            latencyMilliseconds: latencyMilliseconds,
            pathNodeIDs: pathNodeIDs
        )
        state.lastPingEvent = TopologyRuntimeEvent(code: .pingSucceeded, detail: successDetail)
        recordRuntimeEvent(state: &state, code: .pingSucceeded, detail: successDetail)
        appendConsoleLine(
            state: &state,
            nodeID: sourceNodeID,
            line: "Ping to \(targetIPAddress) succeeded"
        )
    }

    private static func executeTraceCommand(
        state: inout TopologyEditorState,
        sourceNodeID: UUID,
        targetIPAddress: String
    ) {
        guard let sourceConfiguration = state.runtimeDeviceConfigurations[sourceNodeID] else {
            setTraceFailure(
                state: &state,
                sourceNodeID: sourceNodeID,
                eventCode: .traceRejectedInvalidSourceConfiguration,
                faultCategory: .networkConfiguration,
                faultCode: "sourceConfigurationMissing",
                message: "Configure source IP and subnet before tracing",
                detail: "sourceConfigurationMissing"
            )
            return
        }

        let targetNodeIDs = state.runtimeDeviceConfigurations
            .filter { $0.value.ipAddress == targetIPAddress }
            .map(\.key)
            .sorted { $0.uuidString < $1.uuidString }

        guard targetNodeIDs.count == 1, let targetNodeID = targetNodeIDs.first else {
            setTraceFailure(
                state: &state,
                sourceNodeID: sourceNodeID,
                eventCode: .traceRejectedUnknownTarget,
                faultCategory: .networkRouting,
                faultCode: "traceTargetUnknown",
                message: "No unique node is configured with target \(targetIPAddress)",
                detail: "traceTargetUnknown"
            )
            return
        }

        guard state.graph.containsNode(id: targetNodeID),
              let targetConfiguration = state.runtimeDeviceConfigurations[targetNodeID] else {
            setTraceFailure(
                state: &state,
                sourceNodeID: sourceNodeID,
                eventCode: .traceRejectedUnknownTarget,
                faultCategory: .networkRouting,
                faultCode: "traceTargetUnknown",
                message: "Target node is unavailable in topology",
                detail: "traceTargetUnknown"
            )
            return
        }

        guard areInSameSubnet(source: sourceConfiguration, target: targetConfiguration) else {
            setTraceFailure(
                state: &state,
                sourceNodeID: sourceNodeID,
                eventCode: .traceRejectedSubnetMismatch,
                faultCategory: .networkRouting,
                faultCode: "traceSubnetMismatch",
                message: "Source and target are not in the same subnet",
                detail: "traceSubnetMismatch"
            )
            return
        }

        guard let pathNodeIDs = state.graph.shortestPathNodeIDs(from: sourceNodeID, to: targetNodeID) else {
            setTraceFailure(
                state: &state,
                sourceNodeID: sourceNodeID,
                eventCode: .traceRejectedTopologyUnreachable,
                faultCategory: .networkRouting,
                faultCode: "traceTargetUnreachable",
                message: "No topology path exists between source and target",
                detail: "traceTargetUnreachable"
            )
            return
        }

        let hopCount = max(0, pathNodeIDs.count - 1)
        let latencyMilliseconds = deterministicLatencyMilliseconds(forHopCount: hopCount)

        state.lastRuntimeFault = nil

        let detail = routeDetail(
            command: "trace",
            sourceNodeID: sourceNodeID,
            targetNodeID: targetNodeID,
            targetIPAddress: targetIPAddress,
            hopCount: hopCount,
            latencyMilliseconds: latencyMilliseconds,
            pathNodeIDs: pathNodeIDs
        )
        recordRuntimeEvent(state: &state, code: .traceSucceeded, detail: detail)
        appendConsoleLine(
            state: &state,
            nodeID: sourceNodeID,
            line: "Trace to \(targetIPAddress) succeeded (hops=\(hopCount), latencyMs=\(latencyMilliseconds))"
        )
        appendConsoleLine(
            state: &state,
            nodeID: sourceNodeID,
            line: "Path: \(pathNodeIDs.map(\.uuidString).joined(separator: " -> "))"
        )
    }

    private static func routeDetail(
        command: String,
        sourceNodeID: UUID,
        targetNodeID: UUID,
        targetIPAddress: String,
        hopCount: Int,
        latencyMilliseconds: Int,
        pathNodeIDs: [UUID]
    ) -> String {
        "command=\(command),source=\(sourceNodeID.uuidString),target=\(targetNodeID.uuidString),targetIP=\(targetIPAddress),hops=\(hopCount),latencyMs=\(latencyMilliseconds),path=\(pathNodeIDs.map(\.uuidString).joined(separator: "->"))"
    }

    private static func deterministicLatencyMilliseconds(forHopCount hopCount: Int) -> Int {
        max(1, 2 + (hopCount * 4))
    }

    private static func appendConsoleLine(state: inout TopologyEditorState, nodeID: UUID, line: String) {
        var entries = state.runtimeConsoleEntriesByNodeID[nodeID] ?? []
        entries.append(line)

        if entries.count > maxRuntimeConsoleEntriesPerDevice {
            entries.removeFirst(entries.count - maxRuntimeConsoleEntriesPerDevice)
        }

        state.runtimeConsoleEntriesByNodeID[nodeID] = entries
    }

    private static func normalizedRuntimeValue(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private static func parseRuntimeCommand(_ command: String) -> RuntimeCommandParseResult {
        let parts = command.split(whereSeparator: { $0.isWhitespace }).map(String.init)

        guard let firstToken = parts.first else {
            return .malformed(
                command: nil,
                reason: "Command must follow deterministic format: ping <target-ipv4>"
            )
        }

        let commandToken = firstToken.lowercased()
        switch commandToken {
        case "ping":
            guard parts.count == 2 else {
                return .malformed(
                    command: "ping",
                    reason: "Command must follow deterministic format: ping <target-ipv4>"
                )
            }

            guard let normalizedTargetAddress = normalizedIPv4Address(parts[1]) else {
                return .malformed(
                    command: "ping",
                    reason: "Ping target must be a valid IPv4 address"
                )
            }

            return .success(.ping(normalizedTargetAddress))

        case "trace", "path", "traceroute":
            guard parts.count == 2 else {
                return .malformed(
                    command: "trace",
                    reason: "Command must follow deterministic format: trace <target-ipv4>"
                )
            }

            guard let normalizedTargetAddress = normalizedIPv4Address(parts[1]) else {
                return .malformed(
                    command: "trace",
                    reason: "Trace target must be a valid IPv4 address"
                )
            }

            return .success(.trace(normalizedTargetAddress))

        default:
            return .unsupported(command: commandToken)
        }
    }

    private static func normalizedIPv4Address(_ value: String?) -> String? {
        guard let octets = parseIPv4Octets(value) else {
            return nil
        }

        return octets.map(String.init).joined(separator: ".")
    }

    private static func normalizedSubnetMask(_ value: String?) -> String? {
        guard let octets = parseIPv4Octets(value), isContiguousSubnetMask(octets) else {
            return nil
        }

        return octets.map(String.init).joined(separator: ".")
    }

    private static func parseIPv4Octets(_ value: String?) -> [UInt8]? {
        guard let normalized = normalizedRuntimeValue(value) else {
            return nil
        }

        let segments = normalized.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count == 4 else {
            return nil
        }

        var octets: [UInt8] = []
        octets.reserveCapacity(4)

        for segment in segments {
            let text = String(segment)
            guard !text.isEmpty, text.allSatisfy({ $0.isNumber }), let octet = UInt8(text) else {
                return nil
            }
            octets.append(octet)
        }

        return octets
    }

    private static func isContiguousSubnetMask(_ octets: [UInt8]) -> Bool {
        guard octets.count == 4 else {
            return false
        }

        let mask = octets.reduce(UInt32(0)) { partial, octet in
            (partial << 8) | UInt32(octet)
        }

        let inverted = ~mask
        return (inverted & (inverted &+ 1)) == 0
    }

    private static func networkPrefix(ipAddress: String, subnetMask: String) -> UInt32? {
        guard
            let ipOctets = parseIPv4Octets(ipAddress),
            let subnetOctets = parseIPv4Octets(subnetMask)
        else {
            return nil
        }

        let ip = ipOctets.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        let mask = subnetOctets.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        return ip & mask
    }

    private static func areInSameSubnet(
        source: TopologyRuntimeDeviceConfiguration,
        target: TopologyRuntimeDeviceConfiguration
    ) -> Bool {
        guard source.subnetMask == target.subnetMask else {
            return false
        }

        guard
            let sourceNetwork = networkPrefix(ipAddress: source.ipAddress, subnetMask: source.subnetMask),
            let targetNetwork = networkPrefix(ipAddress: target.ipAddress, subnetMask: target.subnetMask)
        else {
            return false
        }

        return sourceNetwork == targetNetwork
    }

    private static func areCompatibleEndpoints(_ sourceNode: TopologyNode, _ targetNode: TopologyNode) -> Bool {
        sourceNode.kind == .networkSwitch || targetNode.kind == .networkSwitch
    }

    private static func resolvePortID(
        on node: TopologyNode,
        requestedPortID: UUID?,
        graph: TopologyGraph
    ) -> PortResolutionResult {
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

    private static func isFiniteSize(_ value: CGSize) -> Bool {
        isFiniteScalar(value.width) && isFiniteScalar(value.height)
    }

    private static func isFinitePoint(_ value: CGPoint) -> Bool {
        isFiniteScalar(value.x) && isFiniteScalar(value.y)
    }

    private static func isFiniteScalar(_ value: CGFloat) -> Bool {
        value.isFinite && !value.isNaN
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
        case .startSimulation:
            return "startSimulation"
        case .stopSimulation:
            return "stopSimulation"
        case .simulationTick:
            return "simulationTick"
        case .simulationFault:
            return "simulationFault"
        case .openRuntimeDevice:
            return "openRuntimeDevice"
        case .closeRuntimeDevice:
            return "closeRuntimeDevice"
        case .saveRuntimeDeviceIP:
            return "saveRuntimeDeviceIP"
        case .executePing:
            return "executePing"
        case .moveSelectedNodes:
            return "moveSelectedNodes"
        case .panCanvas:
            return "panCanvas"
        case .zoomCanvas:
            return "zoomCanvas"
        case .setInteractionMode:
            return "setInteractionMode"
        case .dismissRecoveryNotice:
            return "dismissRecoveryNotice"
        case .dismissPersistenceError:
            return "dismissPersistenceError"
        }
    }
}
