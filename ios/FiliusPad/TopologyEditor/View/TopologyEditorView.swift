import SwiftUI

struct TopologyEditorView: View {
    @Binding var state: TopologyEditorState

    @State private var activeNodeDragTranslations: [UUID: CGSize] = [:]
    @State private var nodeDragInFlight = false
    @State private var simulationTickTask: Task<Void, Never>?

    private let canvasWorldBounds = CGRect(x: -10_000, y: -10_000, width: 20_000, height: 20_000)
    private let simulationTickIntervalNanoseconds: UInt64 = 200_000_000

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("FiliusPad")
                .font(.title.bold())

            if state.isRecoveryNoticeVisible {
                recoveryNoticeBanner
            }

            TopologyPaletteView(
                activeTool: state.activeTool,
                simulationPhase: state.simulationPhase,
                onSelectTool: setToolMode,
                onStartSimulation: handleStartSimulation,
                onStopSimulation: handleStopSimulation,
                onPaletteDragPrepared: handlePaletteDragPrepared
            )

            TopologyCanvasView(
                state: state,
                onTap: handleCanvasTap,
                onNodeDragChanged: handleNodeDragChanged,
                onNodeDragEnded: handleNodeDragEnded,
                onCanvasPan: handleCanvasPan,
                onCanvasPanEnded: { nodeDragInFlight = false },
                onMagnify: handleCanvasMagnify,
                onMagnifyEnded: { }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .dropDestination(for: String.self) { items, location in
                handlePaletteDrop(items: items, location: location)
            }

            TopologyDebugOverlayView(state: state)
                .accessibilityIdentifier("debug.overlay")
        }
        .padding(16)
        .background(Color(uiColor: .systemGroupedBackground))
        .sheet(item: runtimeDeviceSheetBinding) { item in
            runtimeDeviceSheet(for: item.id)
        }
        .alert(
            "Persistence error",
            isPresented: persistenceAlertPresented,
            presenting: state.lastPersistenceError
        ) { _ in
            Button("Dismiss") {
                send(.dismissPersistenceError)
            }
        } message: { failure in
            Text(persistenceAlertMessage(for: failure))
                .accessibilityIdentifier("persistence.error.alert")
        }
        .onAppear {
            handleSimulationPhaseChange(state.simulationPhase)
        }
        .onChange(of: state.simulationPhase) { newPhase in
            handleSimulationPhaseChange(newPhase)
        }
        .onDisappear {
            stopSimulationTickLoop()
            if state.simulationPhase == .running {
                send(.stopSimulation)
            }
        }
    }

    private var runtimeDeviceSheetBinding: Binding<RuntimeDeviceSheetItem?> {
        Binding(
            get: {
                guard let nodeID = state.openedRuntimeDeviceID,
                      state.graph.containsNode(id: nodeID)
                else {
                    return nil
                }

                return RuntimeDeviceSheetItem(id: nodeID)
            },
            set: { newValue in
                guard let newValue else {
                    send(.closeRuntimeDevice)
                    return
                }

                send(.openRuntimeDevice(nodeID: newValue.id))
            }
        )
    }

    private var persistenceAlertPresented: Binding<Bool> {
        Binding(
            get: {
                state.lastPersistenceError != nil
            },
            set: { isPresented in
                if !isPresented {
                    send(.dismissPersistenceError)
                }
            }
        )
    }

    private var recoveryNoticeBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: state.lastRecoverySucceeded == false ? "exclamationmark.triangle.fill" : "arrow.clockwise.circle.fill")
                .foregroundStyle(state.lastRecoverySucceeded == false ? Color.orange : Color.green)

            Text(state.lastRecoveryMessage ?? "Recovered autosave state")
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button("Dismiss") {
                send(.dismissRecoveryNotice)
            }
            .buttonStyle(.borderless)
            .accessibilityIdentifier("recovery.notice.dismiss")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(state.lastRecoverySucceeded == false ? Color.orange.opacity(0.5) : Color.green.opacity(0.45), lineWidth: 1)
        }
        .accessibilityIdentifier("recovery.notice.banner")
    }

    @ViewBuilder
    private func runtimeDeviceSheet(for nodeID: UUID) -> some View {
        let node = state.graph.node(withID: nodeID)

        TopologyRuntimeDeviceSheet(
            nodeID: nodeID,
            nodeKind: node?.kind ?? .unsupported,
            configuration: state.runtimeDeviceConfigurations[nodeID],
            installedPrograms: state.runtimeInstalledProgramsByNodeID[nodeID] ?? [],
            consoleEntries: state.runtimeConsoleEntriesByNodeID[nodeID] ?? [],
            onSaveConfiguration: { ipAddress, subnetMask in
                send(.saveRuntimeDeviceIP(nodeID: nodeID, ipAddress: ipAddress, subnetMask: subnetMask))
            },
            onInstallProgram: { program in
                send(.installRuntimeProgram(nodeID: nodeID, program: program))
            },
            onExecuteCommand: { command in
                send(.executePing(nodeID: nodeID, command: command))
            },
            onClose: {
                send(.closeRuntimeDevice)
            }
        )
        .presentationDetents([.medium, .large])
    }

    private func setToolMode(_ mode: TopologyEditorToolMode) {
        send(.setActiveTool(mode: mode))

        switch mode {
        case .select:
            send(.setInteractionMode(mode: "paletteTap:select"))
        case .connect:
            send(.setInteractionMode(mode: "paletteTap:connect"))
        case let .place(kind):
            send(.setInteractionMode(mode: "paletteTap:place:\(kind.rawValue)"))
        }
    }

    private func handleStartSimulation() {
        send(.startSimulation)
    }

    private func handleStopSimulation() {
        send(.stopSimulation)
    }

    private func handlePaletteDragPrepared(_ kind: TopologyNodeKind) {
        guard state.simulationPhase == .stopped else {
            return
        }

        send(.setInteractionMode(mode: "paletteDrag:start:\(kind.rawValue)"))
    }

    private func handlePaletteDrop(items: [String], location: CGPoint) -> Bool {
        guard state.simulationPhase == .stopped else {
            return false
        }

        guard let first = items.first,
              let kind = TopologyNodeKind(rawValue: first),
              kind != .unsupported
        else {
            send(.setInteractionMode(mode: "paletteDrag:invalidPayload"))
            return false
        }

        send(.setActiveTool(mode: .place(kind)))
        send(.setInteractionMode(mode: "paletteDrag:drop:\(kind.rawValue)"))
        handleCanvasTap(location)
        return true
    }

    private func handleSimulationPhaseChange(_ phase: TopologySimulationPhase) {
        switch phase {
        case .running:
            startSimulationTickLoopIfNeeded()
        case .stopped:
            stopSimulationTickLoop()
        }
    }

    private func startSimulationTickLoopIfNeeded() {
        guard simulationTickTask == nil else {
            return
        }

        simulationTickTask = Task {
            await simulationTickLoop()
        }
    }

    private func stopSimulationTickLoop() {
        simulationTickTask?.cancel()
        simulationTickTask = nil
    }

    private func simulationTickLoop() async {
        while !Task.isCancelled {
            do {
                try await Task.sleep(nanoseconds: simulationTickIntervalNanoseconds)
            } catch {
                break
            }

            if Task.isCancelled {
                break
            }

            await MainActor.run {
                guard state.simulationPhase == .running else {
                    return
                }
                send(.simulationTick(step: 1))
            }
        }
    }

    private func handleCanvasTap(_ screenPoint: CGPoint) {
        let hitNodeID = state.viewport.hitTestNode(atScreenPoint: screenPoint, nodes: state.graph.nodes)

        if state.simulationPhase == .running {
            guard let hitNodeID else {
                return
            }

            send(.openRuntimeDevice(nodeID: hitNodeID))
            return
        }

        switch state.activeTool {
        case let .place(kind):
            let worldPoint = state.viewport.screenToWorld(screenPoint)
            guard canvasWorldBounds.contains(worldPoint) else {
                return
            }
            send(.setInteractionMode(mode: "canvasTap:place:\(kind.rawValue)"))
            send(.placeNode(kind: kind, at: worldPoint, nodeID: UUID()))

        case .select:
            guard let hitNodeID else {
                send(.clearSelection)
                return
            }
            send(.selectSingleNode(nodeID: hitNodeID))

        case .connect:
            guard let hitNodeID else {
                return
            }

            if state.pendingConnection == nil {
                send(.startConnection(nodeID: hitNodeID, portID: nil))
            } else {
                send(.completeConnection(nodeID: hitNodeID, portID: nil))
            }
        }
    }

    private func handleNodeDragChanged(nodeID: UUID, translation: CGSize) {
        guard state.simulationPhase == .stopped,
              state.activeTool == .select
        else {
            return
        }

        nodeDragInFlight = true

        if !state.selectedNodeIDs.contains(nodeID) {
            send(.selectSingleNode(nodeID: nodeID))
        }

        let previous = activeNodeDragTranslations[nodeID] ?? .zero
        let incrementalScreenDelta = CGSize(
            width: translation.width - previous.width,
            height: translation.height - previous.height
        )

        activeNodeDragTranslations[nodeID] = translation

        guard incrementalScreenDelta != .zero else {
            return
        }

        let worldDelta = CGSize(
            width: incrementalScreenDelta.width / max(state.viewport.scale, 0.001),
            height: incrementalScreenDelta.height / max(state.viewport.scale, 0.001)
        )

        send(.moveSelectedNodes(delta: worldDelta))
    }

    private func handleNodeDragEnded(nodeID: UUID) {
        activeNodeDragTranslations.removeValue(forKey: nodeID)
        nodeDragInFlight = false
    }

    private func handleCanvasPan(_ delta: CGSize) {
        guard state.simulationPhase == .stopped,
              !nodeDragInFlight
        else {
            return
        }

        send(.panCanvas(delta: delta))
    }

    private func handleCanvasMagnify(_ scaleDelta: CGFloat, anchor: CGPoint) {
        send(.zoomCanvas(scaleDelta: scaleDelta, anchor: anchor))
    }

    private func persistenceAlertMessage(for failure: TopologyPersistenceFailure) -> String {
        "Operation: \(failure.operation.rawValue)\nCode: \(failure.code.rawValue)\nDetail: \(failure.detail)"
    }

    private func send(_ action: TopologyEditorAction) {
        var snapshot = state
        TopologyEditorReducer.reduce(state: &snapshot, action: action)
        state = snapshot
    }
}

private struct RuntimeDeviceSheetItem: Identifiable, Equatable {
    let id: UUID
}
