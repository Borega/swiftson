import CoreGraphics
import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

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

enum TopologyFLSCompatibilityErrorCode: String, Equatable {
    case malformedConfigurationXML
    case unsupportedConfigurationStructure
}

struct TopologyFLSCompatibilityError: Error, Equatable {
    let code: TopologyFLSCompatibilityErrorCode
    let detail: String
}

struct TopologyFLSImportReport: Equatable {
    let filiusVersion: String?
    let importedNodeCount: Int
    let skippedNodeCount: Int
    let warnings: [String]
}

struct TopologyFLSImportResult: Equatable {
    let state: TopologyEditorState
    let report: TopologyFLSImportReport
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

    static func importFiliusConfigurationXML(_ xmlData: Data) throws -> TopologyFLSImportResult {
        let parser = TopologyFLSConfigurationParser(data: xmlData)
        let parseResult = try parser.parse()

        var state = TopologyEditorState()
        state.graph = TopologyGraph(nodes: parseResult.nodes, links: [])

        let report = TopologyFLSImportReport(
            filiusVersion: parseResult.filiusVersion,
            importedNodeCount: parseResult.nodes.count,
            skippedNodeCount: parseResult.skippedNodeCount,
            warnings: parseResult.warnings
        )

        return TopologyFLSImportResult(state: state, report: report)
    }

    static func exportFiliusConfigurationXML(
        from state: TopologyEditorState,
        filiusVersion: String = "Filius version: 2.1.0 (iPad compatibility export)"
    ) -> Data {
        var lines: [String] = [
            "<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
            "<java version=\"11.0.17\" class=\"java.beans.XMLDecoder\">",
            " <string>\(escapeXML(filiusVersion))</string>",
            " <object class=\"java.util.LinkedList\">"
        ]

        let sortedNodes = state.graph.nodes.sorted { lhs, rhs in
            lhs.id.uuidString < rhs.id.uuidString
        }

        for (index, node) in sortedNodes.enumerated() {
            let nodeLabel = "\(node.kind == .networkSwitch ? "Switch" : "Computer") \(index + 1)"
            let typeLabel: String
            switch node.kind {
            case .pc:
                typeLabel = "Computer"
            case .networkSwitch:
                typeLabel = "Switch"
            case .unsupported:
                typeLabel = "Unsupported"
            }

            let x = Int(node.position.x.rounded())
            let y = Int(node.position.y.rounded())

            lines.append("  <void method=\"add\">")
            lines.append("   <object class=\"filius.gui.netzwerksicht.GUIKnotenItem\">")
            lines.append("    <void property=\"text\"><string>\(escapeXML(nodeLabel))</string></void>")
            lines.append("    <void property=\"typ\"><string>\(typeLabel)</string></void>")
            lines.append("    <void property=\"bounds\">")
            lines.append("     <object class=\"java.awt.Rectangle\">")
            lines.append("      <void class=\"java.awt.Rectangle\" method=\"getField\"><string>x</string><void method=\"set\"><int>\(x)</int></void></void>")
            lines.append("      <void class=\"java.awt.Rectangle\" method=\"getField\"><string>y</string><void method=\"set\"><int>\(y)</int></void></void>")
            lines.append("     </object>")
            lines.append("    </void>")
            lines.append("   </object>")
            lines.append("  </void>")
        }

        lines.append(" </object>")
        lines.append("</java>")

        return Data(lines.joined(separator: "\n").utf8)
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

private struct TopologyFLSConfigurationParseResult {
    let filiusVersion: String?
    let nodes: [TopologyNode]
    let skippedNodeCount: Int
    let warnings: [String]
}

private final class TopologyFLSConfigurationParser: NSObject, XMLParserDelegate {
    private struct NodeCandidate {
        var typeName: String?
        var x: Int?
        var y: Int?
    }

    private struct VoidContext {
        let property: String?
        let method: String?
    }

    private let data: Data

    private var objectClassStack: [String?] = []
    private var voidStack: [VoidContext] = []
    private var propertyStack: [String] = []

    private var currentNode: NodeCandidate?
    private var nodes: [TopologyNode] = []
    private var warnings: [String] = []
    private var skippedNodeCount = 0

    private var currentTextBuffer = ""
    private var parsingString = false
    private var parsingInt = false

    private var rectangleFieldName: String?
    private var rectangleGetFieldDepth = 0
    private var rectangleSetDepth = 0

    private var filiusVersion: String?
    private var sawXMLDecoderRoot = false
    private var sawNodeListContainer = false

    init(data: Data) {
        self.data = data
    }

    func parse() throws -> TopologyFLSConfigurationParseResult {
        let parser = XMLParser(data: data)
        parser.delegate = self

        guard parser.parse() else {
            let message = parser.parserError?.localizedDescription ?? "unknown XML parser error"
            throw TopologyFLSCompatibilityError(
                code: .malformedConfigurationXML,
                detail: "Failed to parse konfiguration.xml at line \(parser.lineNumber): \(message)"
            )
        }

        guard sawXMLDecoderRoot else {
            throw TopologyFLSCompatibilityError(
                code: .unsupportedConfigurationStructure,
                detail: "Unsupported configuration root: expected <java class=\"java.beans.XMLDecoder\">"
            )
        }

        guard sawNodeListContainer else {
            throw TopologyFLSCompatibilityError(
                code: .unsupportedConfigurationStructure,
                detail: "Unsupported configuration payload: expected node container <object class=\"java.util.LinkedList\">"
            )
        }

        return TopologyFLSConfigurationParseResult(
            filiusVersion: filiusVersion,
            nodes: nodes,
            skippedNodeCount: skippedNodeCount,
            warnings: warnings
        )
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        currentTextBuffer = ""

        switch elementName {
        case "java":
            if attributeDict["class"] == "java.beans.XMLDecoder" {
                sawXMLDecoderRoot = true
            }

        case "object":
            let objectClass = attributeDict["class"]
            objectClassStack.append(objectClass)
            if objectClass == "java.util.LinkedList" {
                sawNodeListContainer = true
            }
            if objectClass == "filius.gui.netzwerksicht.GUIKnotenItem" {
                currentNode = NodeCandidate()
            }

        case "void":
            let context = VoidContext(property: attributeDict["property"], method: attributeDict["method"])
            voidStack.append(context)

            if let property = context.property {
                propertyStack.append(property)
            }

            if context.method == "getField", propertyStack.contains("bounds") {
                rectangleGetFieldDepth += 1
            }

            if context.method == "set", propertyStack.contains("bounds") {
                rectangleSetDepth += 1
            }

        case "string":
            parsingString = true

        case "int":
            parsingInt = true

        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentTextBuffer.append(string)
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let value = currentTextBuffer.trimmingCharacters(in: .whitespacesAndNewlines)

        switch elementName {
        case "string":
            parsingString = false

            if filiusVersion == nil, value.hasPrefix("Filius version:") {
                filiusVersion = value
            }

            guard currentNode != nil else {
                currentTextBuffer = ""
                return
            }

            if let property = propertyStack.last {
                if property == "typ" {
                    currentNode?.typeName = value
                }
            }

            if rectangleGetFieldDepth > 0, propertyStack.contains("bounds") {
                rectangleFieldName = value
            }

        case "int":
            parsingInt = false

            if currentNode != nil,
               rectangleSetDepth > 0,
               propertyStack.contains("bounds"),
               let number = Int(value),
               let fieldName = rectangleFieldName
            {
                if fieldName == "x" {
                    currentNode?.x = number
                } else if fieldName == "y" {
                    currentNode?.y = number
                }
            }

        case "void":
            if let context = voidStack.popLast() {
                if context.method == "getField", rectangleGetFieldDepth > 0 {
                    rectangleGetFieldDepth -= 1
                }

                if context.method == "set", rectangleSetDepth > 0 {
                    rectangleSetDepth -= 1
                }

                if context.property != nil, !propertyStack.isEmpty {
                    _ = propertyStack.popLast()
                }
            }

        case "object":
            let closedClass = objectClassStack.popLast() ?? nil
            if closedClass == "filius.gui.netzwerksicht.GUIKnotenItem" {
                finalizeCurrentNodeCandidate()
            }

        default:
            break
        }

        currentTextBuffer = ""
    }

    private func finalizeCurrentNodeCandidate() {
        guard let candidate = currentNode else {
            return
        }
        currentNode = nil

        guard let typeName = candidate.typeName,
              !typeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            skippedNodeCount += 1
            warnings.append("Skipped FILIUS node with missing type label in konfiguration.xml")
            return
        }

        guard let nodeKind = mapLegacyNodeType(typeName) else {
            skippedNodeCount += 1
            warnings.append("Skipped unsupported FILIUS node type '\(typeName)' in konfiguration.xml")
            return
        }

        guard let x = candidate.x, let y = candidate.y else {
            skippedNodeCount += 1
            warnings.append("Skipped FILIUS node with missing bounds coordinates")
            return
        }

        let node = TopologyNode(
            id: UUID(),
            kind: nodeKind,
            position: CGPoint(x: x, y: y)
        )
        nodes.append(node)
    }

    private func mapLegacyNodeType(_ value: String) -> TopologyNodeKind? {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "computer", "rechner", "laptop", "notebook":
            return .pc
        case "switch", "switchhub":
            return .networkSwitch
        default:
            return nil
        }
    }
}

private func escapeXML(_ value: String) -> String {
    value
        .replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
        .replacingOccurrences(of: "\"", with: "&quot;")
        .replacingOccurrences(of: "'", with: "&apos;")
}
