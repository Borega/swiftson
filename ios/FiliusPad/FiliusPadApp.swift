import Foundation
import SwiftUI

@main
struct FiliusPadApp: App {
    @State private var editorState = TopologyEditorState()
    @State private var autosaveTask: Task<Void, Never>?
    @State private var hasAttemptedLaunchRestore = false

    private let launchConfiguration: PersistenceLaunchConfiguration
    private let projectStore: TopologyProjectStore
    private let autosaveDebounceNanoseconds: UInt64 = 500_000_000

    init() {
        let launchConfiguration = Self.resolvePersistenceLaunchConfiguration()
        self.launchConfiguration = launchConfiguration
        self.projectStore = TopologyProjectStore(fileURL: launchConfiguration.autosaveFileURL)
    }

    init(projectStore: TopologyProjectStore) {
        let launchConfiguration = Self.resolvePersistenceLaunchConfiguration()
        self.launchConfiguration = launchConfiguration
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
        prepareLaunchAutosaveFixtureIfNeeded()

        do {
            var restoredState = try await loadStateFromStore()
            restoredState.recordPersistenceLoad()
            restoredState.recordRecoverySuccess(
                message: "Recovered autosave (revision: \(restoredState.persistenceRevision))"
            )
            editorState = restoredState
        } catch let persistenceError as TopologyProjectPersistenceError {
            if persistenceError.code == .fileNotFound {
                return
            }

            let sanitizedDetail = sanitizePersistenceDetail(persistenceError.detail)

            editorState.recordPersistenceFailure(
                operation: persistenceError.operation,
                code: persistenceError.code,
                detail: sanitizedDetail
            )
            editorState.recordRecoveryFailure(
                message: "Recovery failed: \(persistenceError.code.rawValue)"
            )
        } catch {
            editorState.recordPersistenceFailure(
                operation: .load,
                code: .malformedPayload,
                detail: "Unexpected persistence load failure"
            )
            editorState.recordRecoveryFailure(
                message: "Recovery failed: malformedPayload"
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

    private func prepareLaunchAutosaveFixtureIfNeeded() {
        guard launchConfiguration.shouldInjectMalformedAutosave else {
            return
        }

        do {
            let parentDirectory = projectStore.fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: parentDirectory,
                withIntermediateDirectories: true
            )
            try Data("{malformed-autosave".utf8).write(to: projectStore.fileURL, options: .atomic)
        } catch {
            editorState.recordPersistenceFailure(
                operation: .save,
                code: .fileWriteFailed,
                detail: "Failed to seed malformed autosave fixture"
            )
        }
    }

    private static func resolvePersistenceLaunchConfiguration() -> PersistenceLaunchConfiguration {
        let processInfo = ProcessInfo.processInfo
        let environment = processInfo.environment
        let arguments = Set(processInfo.arguments)

        let isUITesting = arguments.contains("-ui-testing")

        let autosaveFileURL: URL = {
            if let overridePath = environment["FILIUSPAD_AUTOSAVE_FILE"]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !overridePath.isEmpty {
                return URL(fileURLWithPath: overridePath)
            }

            if isUITesting {
                let filename = "ui-testing-autosave-\(UUID().uuidString).topology.json"
                return FileManager.default.temporaryDirectory.appendingPathComponent(filename)
            }

            return defaultAutosaveFileURL
        }()

        let shouldInjectMalformedAutosave = arguments.contains("-inject-malformed-autosave")

        return PersistenceLaunchConfiguration(
            autosaveFileURL: autosaveFileURL,
            shouldInjectMalformedAutosave: shouldInjectMalformedAutosave
        )
    }

    private static var defaultAutosaveFileURL: URL {
        let rootDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory

        return rootDirectory
            .appendingPathComponent("FiliusPad", isDirectory: true)
            .appendingPathComponent("autosave.topology.json", isDirectory: false)
    }
}

private struct PersistenceLaunchConfiguration {
    let autosaveFileURL: URL
    let shouldInjectMalformedAutosave: Bool
}
