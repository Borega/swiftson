import SwiftUI

struct TopologyEditorView: View {
    @Binding var state: TopologyEditorState

    @State private var activeNodeDragTranslations: [UUID: CGSize] = [:]
    @State private var nodeDragInFlight = false

    private let canvasWorldBounds = CGRect(x: -10_000, y: -10_000, width: 20_000, height: 20_000)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("FiliusPad")
                .font(.title.bold())

            TopologyPaletteView(
                activeTool: state.activeTool,
                onSelectTool: setToolMode
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

            diagnosticsBar
        }
        .padding(16)
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private var diagnosticsBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Tool: \(debugToolName(state.activeTool))")
                .accessibilityIdentifier("debug.activeTool")

            Text("Nodes: \(state.graph.nodes.count)")
                .accessibilityIdentifier("debug.nodeCount")

            Text("Selected: \(state.selectedNodeIDs.count)")
                .accessibilityIdentifier("debug.selectedNodeCount")

            Text(
                String(
                    format: "Camera: x=%.1f y=%.1f",
                    state.viewport.offset.width,
                    state.viewport.offset.height
                )
            )
            .accessibilityIdentifier("debug.cameraOffset")

            Text(String(format: "Zoom: %.2f", state.viewport.scale))
                .accessibilityIdentifier("debug.zoomScale")

            Text("Last error: \(state.lastValidationError?.rawValue ?? "none")")
                .accessibilityIdentifier("debug.lastValidationError")

            Text("Last action: \(state.lastAction ?? "none")")
                .accessibilityIdentifier("debug.lastAction")
        }
        .font(.footnote.monospaced())
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func setToolMode(_ mode: TopologyEditorToolMode) {
        send(.setActiveTool(mode: mode))
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

    private func debugToolName(_ mode: TopologyEditorToolMode) -> String {
        switch mode {
        case .select:
            return "select"
        case .connect:
            return "connect"
        case let .place(kind):
            return "place(\(kind.rawValue))"
        }
    }
}
