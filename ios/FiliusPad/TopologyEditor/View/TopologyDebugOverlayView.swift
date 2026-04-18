import Foundation
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

            Text("Last runtime route: \(debugRuntimeRoute(state.lastRuntimeEvent))")
                .accessibilityIdentifier("debug.lastRuntimeRoute")

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

            Text("Persistence revision: \(state.persistenceRevision)")
                .accessibilityIdentifier("debug.persistenceRevision")

            Text("Last persistence save: \(debugDate(state.lastPersistenceSaveAt))")
                .accessibilityIdentifier("debug.lastPersistenceSaveAt")

            Text("Last persistence load: \(debugDate(state.lastPersistenceLoadAt))")
                .accessibilityIdentifier("debug.lastPersistenceLoadAt")

            Text("Recovery state: \(debugRecoveryState())")
                .accessibilityIdentifier("debug.lastRecoveryState")

            Text("Last recovery at: \(debugDate(state.lastRecoveryAt))")
                .accessibilityIdentifier("debug.lastRecoveryAt")

            Text("Last persistence error: \(debugPersistenceError(state.lastPersistenceError))")
                .accessibilityIdentifier("debug.lastPersistenceError")

            Text("Last error: \(state.lastValidationError?.rawValue ?? "none")")
                .accessibilityIdentifier("debug.lastValidationError")

            Text("Last action: \(state.lastAction ?? "none")")
                .accessibilityIdentifier("debug.lastAction")

            Text("Last interaction mode: \(state.lastInteractionMode ?? "none")")
                .accessibilityIdentifier("debug.lastInteractionMode")

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

    private func debugRuntimeRoute(_ event: TopologyRuntimeEvent?) -> String {
        guard let event,
              let detail = event.detail,
              detail.contains("path=") || detail.contains("hops=") || detail.contains("latencyMs=")
        else {
            return "none"
        }

        return detail
    }

    private func debugRuntimeFault(_ fault: TopologyRuntimeFault?) -> String {
        guard let fault else {
            return "none"
        }

        return "\(fault.category.rawValue):\(fault.code) [\(fault.message)]"
    }

    private func debugPersistenceError(_ failure: TopologyPersistenceFailure?) -> String {
        guard let failure else {
            return "none"
        }

        let timestamp = ISO8601DateFormatter().string(from: failure.occurredAt)
        return "\(failure.operation.rawValue):\(failure.code.rawValue) [\(failure.detail)] @\(timestamp)"
    }

    private func debugRecoveryState() -> String {
        guard let message = state.lastRecoveryMessage else {
            return "none"
        }

        let prefix: String
        if let lastRecoverySucceeded = state.lastRecoverySucceeded {
            prefix = lastRecoverySucceeded ? "success" : "failure"
        } else {
            prefix = "unknown"
        }

        return "\(prefix): \(message)"
    }

    private func debugDate(_ date: Date?) -> String {
        guard let date else {
            return "none"
        }

        return ISO8601DateFormatter().string(from: date)
    }
}
