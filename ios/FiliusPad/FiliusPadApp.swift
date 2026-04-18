import SwiftUI

@main
struct FiliusPadApp: App {
    @State private var editorState = TopologyEditorState()

    var body: some Scene {
        WindowGroup {
            VStack(alignment: .leading, spacing: 12) {
                Text("FiliusPad")
                    .font(.largeTitle.bold())

                Text("Topology editor bootstrap ready.")

                Text("Nodes: \(editorState.graph.nodes.count)")
                    .accessibilityIdentifier("debug.nodeCount")

                Text("Selected: \(editorState.selectedNodeIDs.count)")
                    .accessibilityIdentifier("debug.selectedNodeCount")

                if let code = editorState.lastValidationError?.rawValue {
                    Text("Last error: \(code)")
                        .accessibilityIdentifier("debug.lastValidationError")
                }

                if let action = editorState.lastAction {
                    Text("Last action: \(action)")
                        .accessibilityIdentifier("debug.lastAction")
                }

                if let lastActionAt = editorState.lastActionAt {
                    Text("Last action at: \(lastActionAt.timeIntervalSince1970)")
                        .accessibilityIdentifier("debug.lastActionAt")
                }
            }
            .padding(20)
        }
    }
}
