import SwiftUI

struct TopologyDebugOverlayView: View {
    let state: TopologyEditorState

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Tool: \(debugToolName(state.activeTool))")
                .accessibilityIdentifier("debug.activeTool")

            Text("Nodes: \(state.graph.nodes.count)")
                .accessibilityIdentifier("debug.nodeCount")

            Text("Links: \(state.graph.links.count)")
                .accessibilityIdentifier("debug.linkCount")

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

            Text("Transitions: \(state.transitionCount)")
                .accessibilityIdentifier("debug.transitionCount")
        }
        .font(.footnote.monospaced())
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
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
