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

            TopologyPaletteView(
                activeTool: state.activeTool,
                simulationPhase: state.simulationPhase,
                onSelectTool: setToolMode,
                onStartSimulation: handleStartSimulation,
                onStopSimulation: handleStopSimulation
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

            TopologyDebugOverlayView(state: state)
                .accessibilityIdentifier("debug.overlay")
        }
        .padding(16)
        .background(Color(uiColor: .systemGroupedBackground))
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

    private func setToolMode(_ mode: TopologyEditorToolMode) {
        send(.setActiveTool(mode: mode))
    }

    private func handleStartSimulation() {
        send(.startSimulation)
    }

    private func handleStopSimulation() {
        send(.stopSimulation)
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

        switch state.activeTool {
        case let .place(kind):
            let worldPoint = state.viewport.screenToWorld(screenPoint)
            guard canvasWorldBounds.contains(worldPoint) else {
                return
            }
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
        guard state.activeTool == .select else {
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
        guard !nodeDragInFlight else {
            return
        }

        send(.panCanvas(delta: delta))
    }

    private func handleCanvasMagnify(_ scaleDelta: CGFloat, anchor: CGPoint) {
        send(.zoomCanvas(scaleDelta: scaleDelta, anchor: anchor))
    }

    private func send(_ action: TopologyEditorAction) {
        var snapshot = state
        TopologyEditorReducer.reduce(state: &snapshot, action: action)
        state = snapshot
    }
}
