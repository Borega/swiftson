import Foundation

enum TopologyProjectPersistenceOperation: String, Equatable {
    case load
    case save
}

enum TopologyProjectPersistenceErrorCode: String, Equatable {
    case fileNotFound
    case fileReadFailed
    case fileWriteFailed
    case encodingFailed
    case corruptedPayload
    case malformedPayload
    case invalidFormat
    case unsupportedFormat
    case unsupportedSchemaVersion
}

struct TopologyProjectPersistenceError: Error, Equatable {
    let operation: TopologyProjectPersistenceOperation
    let code: TopologyProjectPersistenceErrorCode
    let detail: String
}

struct TopologyProjectStore {
    static let formatIdentifier = TopologyProjectEnvelope.formatIdentifier
    static let supportedSchemaVersion = TopologyProjectEnvelope.currentSchemaVersion

    let fileURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        fileURL: URL,
        fileManager: FileManager = .default,
        encoder: JSONEncoder = TopologyProjectStore.makeEncoder(),
        decoder: JSONDecoder = TopologyProjectStore.makeDecoder()
    ) {
        self.fileURL = fileURL
        self.fileManager = fileManager
        self.encoder = encoder
        self.decoder = decoder
    }

    func save(
        state: TopologyEditorState,
        savedAt: Date = Date(),
        saveReason: TopologyProjectSaveReason = .autosave
    ) throws {
        let envelope = TopologyProjectEnvelope(
            format: Self.formatIdentifier,
            schemaVersion: Self.supportedSchemaVersion,
            savedAt: savedAt,
            saveReason: saveReason,
            payload: TopologyProjectSnapshot(state: state)
        )

        let data: Data
        do {
            data = try encoder.encode(envelope)
        } catch {
            throw makeError(
                operation: .save,
                code: .encodingFailed,
                detail: "Failed to encode topology project envelope: \(describe(error: error))"
            )
        }

        do {
            try fileManager.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: fileURL, options: .atomic)
        } catch {
            throw makeError(
                operation: .save,
                code: .fileWriteFailed,
                detail: "Failed to write topology project data: \(describe(error: error))"
            )
        }
    }

    func load() throws -> TopologyEditorState {
        let data = try readRawData()

        do {
            _ = try JSONSerialization.jsonObject(with: data, options: [])
        } catch {
            throw makeError(
                operation: .load,
                code: .corruptedPayload,
                detail: "Project payload is not valid JSON: \(describe(error: error))"
            )
        }

        let envelope: TopologyProjectEnvelope
        do {
            envelope = try decoder.decode(TopologyProjectEnvelope.self, from: data)
        } catch {
            throw makeError(
                operation: .load,
                code: .malformedPayload,
                detail: "Failed to decode topology project envelope: \(describe(error: error))"
            )
        }

        let normalizedFormat = envelope.format.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedFormat.isEmpty else {
            throw makeError(
                operation: .load,
                code: .invalidFormat,
                detail: "Project envelope format must be non-empty"
            )
        }

        guard normalizedFormat == Self.formatIdentifier else {
            throw makeError(
                operation: .load,
                code: .unsupportedFormat,
                detail: "Unsupported project format '\(normalizedFormat)'; expected '\(Self.formatIdentifier)'"
            )
        }

        guard envelope.schemaVersion == Self.supportedSchemaVersion else {
            throw makeError(
                operation: .load,
                code: .unsupportedSchemaVersion,
                detail: "Unsupported schemaVersion \(envelope.schemaVersion); expected \(Self.supportedSchemaVersion)"
            )
        }

        do {
            return try envelope.payload.toEditorState()
        } catch {
            throw makeError(
                operation: .load,
                code: .malformedPayload,
                detail: "Decoded snapshot failed validation: \(describe(error: error))"
            )
        }
    }

    private func readRawData() throws -> Data {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            throw makeError(
                operation: .load,
                code: .fileNotFound,
                detail: "Project file was not found at configured URL"
            )
        }

        do {
            return try Data(contentsOf: fileURL, options: .mappedIfSafe)
        } catch {
            throw makeError(
                operation: .load,
                code: .fileReadFailed,
                detail: "Failed to read project file data: \(describe(error: error))"
            )
        }
    }

    private func makeError(
        operation: TopologyProjectPersistenceOperation,
        code: TopologyProjectPersistenceErrorCode,
        detail: String
    ) -> TopologyProjectPersistenceError {
        TopologyProjectPersistenceError(operation: operation, code: code, detail: detail)
    }

    private func describe(error: Error) -> String {
        if let decodingError = error as? DecodingError {
            switch decodingError {
            case let .typeMismatch(_, context):
                return "typeMismatch at \(format(codingPath: context.codingPath)): \(context.debugDescription)"
            case let .valueNotFound(_, context):
                return "valueNotFound at \(format(codingPath: context.codingPath)): \(context.debugDescription)"
            case let .keyNotFound(key, context):
                return "keyNotFound '\(key.stringValue)' at \(format(codingPath: context.codingPath)): \(context.debugDescription)"
            case let .dataCorrupted(context):
                return "dataCorrupted at \(format(codingPath: context.codingPath)): \(context.debugDescription)"
            @unknown default:
                return "unknown decoding error"
            }
        }

        if let encodingError = error as? EncodingError {
            switch encodingError {
            case let .invalidValue(_, context):
                return "invalidValue at \(format(codingPath: context.codingPath)): \(context.debugDescription)"
            @unknown default:
                return "unknown encoding error"
            }
        }

        return String(describing: error)
    }

    private func format(codingPath: [CodingKey]) -> String {
        guard !codingPath.isEmpty else {
            return "<root>"
        }

        return codingPath
            .map(\.stringValue)
            .joined(separator: ".")
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
