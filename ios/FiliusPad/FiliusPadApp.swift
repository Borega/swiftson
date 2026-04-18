import Foundation
import SwiftUI

@main
struct FiliusPadApp: App {
    @State private var editorState = TopologyEditorState()
    @State private var autosaveTask: Task<Void, Never>?
    @State private var hasAttemptedLaunchRestore = false

    private let projectStore: TopologyProjectStore
    private let autosaveDebounceNanoseconds: UInt64 = 500_000_000

    init(projectStore: TopologyProjectStore = TopologyProjectStore(fileURL: Self.defaultAutosaveFileURL)) {
        self.projectStore = projectStore
    }

    var body: some Scene {
        WindowGroup {
            TopologyEditorView(state: $editorState)
                .onAppear {
                    guard !hasAttemptedLaunchRestore else {
                        return
                    }

                    hasAttemptedLaunchRestore = true
                    Task {
                        await restoreAutosaveSnapshotOnLaunch()
                    }
                }
                .onChange(of: editorState.persistenceRevision) { _ in
                    scheduleDebouncedAutosaveIfNeeded()
                }
                .onDisappear {
                    autosaveTask?.cancel()
                }
        }
    }

    @MainActor
    private func restoreAutosaveSnapshotOnLaunch() async {
        do {
            var restoredState = try await loadStateFromStore()
            restoredState.recordPersistenceLoad()
            editorState = restoredState
        } catch let persistenceError as TopologyProjectPersistenceError {
            if persistenceError.code == .fileNotFound {
                return
            }

            editorState.recordPersistenceFailure(
                operation: persistenceError.operation,
                code: persistenceError.code,
                detail: sanitizePersistenceDetail(persistenceError.detail)
            )
        } catch {
            editorState.recordPersistenceFailure(
                operation: .load,
                code: .malformedPayload,
                detail: "Unexpected persistence load failure"
            )
        }
    }

    @MainActor
    private func scheduleDebouncedAutosaveIfNeeded() {
        autosaveTask?.cancel()

        let targetRevision = editorState.persistenceRevision
        guard targetRevision > editorState.lastPersistedRevision else {
            return
        }

        autosaveTask = Task {
            do {
                try await Task.sleep(nanoseconds: autosaveDebounceNanoseconds)
            } catch {
                return
            }

            guard !Task.isCancelled else {
                return
            }

            var snapshotToSave: TopologyEditorState?

            await MainActor.run {
                guard editorState.persistenceRevision == targetRevision,
                      editorState.persistenceRevision > editorState.lastPersistedRevision
                else {
                    return
                }

                snapshotToSave = editorState
            }

            guard let snapshotToSave else {
                return
            }

            do {
                try await saveStateToStore(snapshotToSave)
                await MainActor.run {
                    editorState.recordPersistenceSave(revision: targetRevision)
                }
            } catch let persistenceError as TopologyProjectPersistenceError {
                await MainActor.run {
                    editorState.recordPersistenceFailure(
                        operation: persistenceError.operation,
                        code: persistenceError.code,
                        detail: sanitizePersistenceDetail(persistenceError.detail)
                    )
                }
            } catch {
                await MainActor.run {
                    editorState.recordPersistenceFailure(
                        operation: .save,
                        code: .fileWriteFailed,
                        detail: "Unexpected persistence save failure"
                    )
                }
            }
        }
    }

    private func loadStateFromStore() async throws -> TopologyEditorState {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                do {
                    let loadedState = try projectStore.load()
                    continuation.resume(returning: loadedState)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func saveStateToStore(_ state: TopologyEditorState) async throws {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                do {
                    try projectStore.save(state: state)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func sanitizePersistenceDetail(_ detail: String) -> String {
        let redacted = detail.replacingOccurrences(
            of: #"((file:\/\/)?[A-Za-z]:\\[^\s]+|\/[A-Za-z0-9._\/-]+)"#,
            with: "<path>",
            options: .regularExpression
        )

        return String(redacted.prefix(280))
    }

    private static var defaultAutosaveFileURL: URL {
        let rootDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory

        return rootDirectory
            .appendingPathComponent("FiliusPad", isDirectory: true)
            .appendingPathComponent("autosave.topology.json", isDirectory: false)
    }
}
