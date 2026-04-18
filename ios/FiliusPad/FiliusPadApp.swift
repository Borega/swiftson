import SwiftUI

@main
struct FiliusPadApp: App {
    @State private var editorState = TopologyEditorState()

    var body: some Scene {
        WindowGroup {
            TopologyEditorView(state: $editorState)
        }
    }
}
