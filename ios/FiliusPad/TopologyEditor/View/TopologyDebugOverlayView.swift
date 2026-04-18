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

            Text("Simulation phase: \(state.simulationPhase.rawValue)")
                .accessibilityIdentifier("debug.simulationPhase")

            Text("Simulation tick: \(state.simulationTick)")
                .accessibilityIdentifier("debug.simulationTick")

            Text("Opened runtime device: \(state.openedRuntimeDeviceID?.uuidString ?? "none")")
                .accessibilityIdentifier("debug.openedRuntimeDevice")

            Text("Last runtime event: \(debugRuntimeEvent(state.lastRuntimeEvent))")
                .accessibilityIdentifier("debug.lastRuntimeEvent")

            Text("Last runtime fault: \(debugRuntimeFault(state.lastRuntimeFault))")
                .accessibilityIdentifier("debug.lastRuntimeFault")

            Text("Last ping event: \(debugRuntimeEvent(state.lastPingEvent))")
                .accessibilityIdentifier("debug.lastPingEvent")

            Text("Last ping fault: \(debugRuntimeFault(state.lastPingFault))")
                .accessibilityIdentifier("debug.lastPingFault")

            Text("Opened runtime console entries: \(openedRuntimeConsoleCount)")
                .accessibilityIdentifier("debug.runtimeConsoleCount")

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

    private var openedRuntimeConsoleCount: Int {
        guard let openedRuntimeDeviceID = state.openedRuntimeDeviceID else {
            return 0
        }

        return state.runtimeConsoleEntriesByNodeID[openedRuntimeDeviceID]?.count ?? 0
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

    private func debugRuntimeEvent(_ event: TopologyRuntimeEvent?) -> String {
        guard let event else {
            return "none"
        }

        if let detail = event.detail, !detail.isEmpty {
            return "\(event.code.rawValue) [\(detail)]"
        }

        return event.code.rawValue
    }

    private func debugRuntimeFault(_ fault: TopologyRuntimeFault?) -> String {
        guard let fault else {
            return "none"
        }

        return "\(fault.category.rawValue):\(fault.code) [\(fault.message)]"
    }
}
