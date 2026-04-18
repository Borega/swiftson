import CoreGraphics
import XCTest
@testable import FiliusPad

final class TopologyProjectPersistenceTests: XCTestCase {
    private var tempDirectoryURL: URL!

    override func setUpWithError() throws {
        tempDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("TopologyProjectPersistenceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectoryURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDirectoryURL {
            try? FileManager.default.removeItem(at: tempDirectoryURL)
        }
        tempDirectoryURL = nil
    }

    func testRoundTripPreservesDurableStateAndExcludesTransientFields() throws {
        var state = TopologyEditorState()

        let pcNode = TopologyNode(
            id: uuid("11111111-1111-1111-1111-111111111111"),
            kind: .pc,
            position: CGPoint(x: 140.25, y: 88.5),
            ports: [TopologyPortMetadata(id: uuid("11111111-1111-1111-1111-111111111112"), label: "eth0")]
        )
        let switchNode = TopologyNode(
            id: uuid("22222222-2222-2222-2222-222222222222"),
            kind: .networkSwitch,
            position: CGPoint(x: 380.5, y: 130.75)
        )

        let link = TopologyLink(
            id: uuid("33333333-3333-3333-3333-333333333333"),
            sourceNodeID: pcNode.id,
            sourcePortID: pcNode.ports[0].id,
            targetNodeID: switchNode.id,
            targetPortID: switchNode.ports[0].id
        )

        state.graph = TopologyGraph(nodes: [pcNode, switchNode], links: [link])
        state.viewport = ViewportTransform(offset: CGSize(width: 120.5, height: -34.25), scale: 1.75)
        state.runtimeDeviceConfigurations[pcNode.id] = TopologyRuntimeDeviceConfiguration(
            ipAddress: "192.168.50.2",
            subnetMask: "255.255.255.0"
        )

        state.selectedNodeIDs = [pcNode.id, switchNode.id]
        state.activeTool = .connect
        state.pendingConnection = TopologyConnectionDraft(sourceNodeID: pcNode.id, sourcePortID: pcNode.ports[0].id)
        state.simulationPhase = .running
        state.simulationTick = 19
        state.lastRuntimeEvent = TopologyRuntimeEvent(code: .simulationTickAdvanced, detail: "step=1")
        state.lastRuntimeFault = TopologyRuntimeFault(category: .runtimeFault, code: "fault", message: "fault")
        state.openedRuntimeDeviceID = pcNode.id
        state.runtimeConsoleEntriesByNodeID[pcNode.id] = ["ping 192.168.50.1"]
        state.lastPingEvent = TopologyRuntimeEvent(code: .pingSucceeded, detail: "ok")
        state.lastPingFault = TopologyRuntimeFault(category: .networkRouting, code: "pingTargetUnknown", message: "missing")
        state.lastValidationError = .duplicateLink
        state.lastAction = "zoomCanvas"
        state.lastActionAt = Date(timeIntervalSince1970: 500)
        state.lastInteractionMode = "canvasTap:place:pc"
        state.transitionCount = 72
        state.persistenceRevision = 42

        let store = TopologyProjectStore(fileURL: tempDirectoryURL.appendingPathComponent("project.json"))
        try store.save(state: state, savedAt: Date(timeIntervalSince1970: 1_700_000_000))

        let loaded = try store.load()

        XCTAssertEqual(loaded.graph, state.graph)
        XCTAssertEqual(loaded.viewport, state.viewport)
        XCTAssertEqual(loaded.runtimeDeviceConfigurations, state.runtimeDeviceConfigurations)
        XCTAssertEqual(loaded.persistenceRevision, 42)
        XCTAssertEqual(loaded.lastPersistedRevision, 42)
        XCTAssertEqual(loaded.graph.nodes.first(where: { $0.id == switchNode.id })?.ports.count, 8)

        XCTAssertTrue(loaded.selectedNodeIDs.isEmpty)
        XCTAssertEqual(loaded.activeTool, .select)
        XCTAssertNil(loaded.pendingConnection)
        XCTAssertEqual(loaded.simulationPhase, .stopped)
        XCTAssertEqual(loaded.simulationTick, 0)
        XCTAssertNil(loaded.lastRuntimeEvent)
        XCTAssertNil(loaded.lastRuntimeFault)
        XCTAssertNil(loaded.openedRuntimeDeviceID)
        XCTAssertTrue(loaded.runtimeConsoleEntriesByNodeID.isEmpty)
        XCTAssertNil(loaded.lastPingEvent)
        XCTAssertNil(loaded.lastPingFault)
        XCTAssertNil(loaded.lastValidationError)
        XCTAssertNil(loaded.lastAction)
        XCTAssertNil(loaded.lastActionAt)
        XCTAssertNil(loaded.lastInteractionMode)
        XCTAssertEqual(loaded.transitionCount, 0)
    }

    func testEmptyTopologyRoundTripSucceeds() throws {
        let store = TopologyProjectStore(fileURL: tempDirectoryURL.appendingPathComponent("empty.json"))
        try store.save(state: TopologyEditorState(), savedAt: Date(timeIntervalSince1970: 1_700_000_100))

        let loaded = try store.load()

        XCTAssertTrue(loaded.graph.nodes.isEmpty)
        XCTAssertTrue(loaded.graph.links.isEmpty)
        XCTAssertEqual(loaded.viewport, .identity)
    }

    func testLoadRejectsUnsupportedSchemaVersion() throws {
        let fileURL = tempDirectoryURL.appendingPathComponent("unsupported-schema.json")
        try writeJSON(
            envelopeDictionary(schemaVersion: 99),
            to: fileURL
        )

        let store = TopologyProjectStore(fileURL: fileURL)

        XCTAssertThrowsError(try store.load()) { error in
            self.assertPersistenceError(
                error,
                expectedOperation: .load,
                expectedCode: .unsupportedSchemaVersion
            )
        }
    }

    func testLoadRejectsCorruptedJSONPayload() throws {
        let fileURL = tempDirectoryURL.appendingPathComponent("corrupted.json")
        try Data("{not-json".utf8).write(to: fileURL)

        let store = TopologyProjectStore(fileURL: fileURL)

        XCTAssertThrowsError(try store.load()) { error in
            self.assertPersistenceError(
                error,
                expectedOperation: .load,
                expectedCode: .corruptedPayload
            )
        }
    }

    func testLoadRejectsMalformedEnvelopeMissingRequiredKey() throws {
        let fileURL = tempDirectoryURL.appendingPathComponent("missing-payload.json")

        var malformed = envelopeDictionary()
        malformed.removeValue(forKey: "payload")
        try writeJSON(malformed, to: fileURL)

        let store = TopologyProjectStore(fileURL: fileURL)

        XCTAssertThrowsError(try store.load()) { error in
            self.assertPersistenceError(
                error,
                expectedOperation: .load,
                expectedCode: .malformedPayload
            )
        }
    }

    func testLoadLegacyPayloadWithoutRecoveryMetadataDefaultsSafely() throws {
        let fileURL = tempDirectoryURL.appendingPathComponent("legacy-without-recovery-metadata.json")

        var legacyEnvelope = envelopeDictionary()
        legacyEnvelope.removeValue(forKey: "saveReason")

        if var payload = legacyEnvelope["payload"] as? [String: Any] {
            payload.removeValue(forKey: "persistenceRevision")
            legacyEnvelope["payload"] = payload
        }

        try writeJSON(legacyEnvelope, to: fileURL)

        let store = TopologyProjectStore(fileURL: fileURL)
        let loaded = try store.load()

        XCTAssertEqual(loaded.persistenceRevision, 0)
        XCTAssertEqual(loaded.lastPersistedRevision, 0)
    }

    func testLoadRejectsUnknownEnvelopeField() throws {
        let fileURL = tempDirectoryURL.appendingPathComponent("unknown-envelope-field.json")
        try writeJSON(
            envelopeDictionary(extraEnvelopeFields: ["unexpected": true]),
            to: fileURL
        )

        let store = TopologyProjectStore(fileURL: fileURL)

        XCTAssertThrowsError(try store.load()) { error in
            self.assertPersistenceError(
                error,
                expectedOperation: .load,
                expectedCode: .malformedPayload
            )
        }
    }

    func testLoadRejectsEmptyFormatIdentifier() throws {
        let fileURL = tempDirectoryURL.appendingPathComponent("empty-format.json")
        try writeJSON(envelopeDictionary(format: "   "), to: fileURL)

        let store = TopologyProjectStore(fileURL: fileURL)

        XCTAssertThrowsError(try store.load()) { error in
            self.assertPersistenceError(
                error,
                expectedOperation: .load,
                expectedCode: .invalidFormat
            )
        }
    }

    func testLoadRejectsUnknownFormatIdentifier() throws {
        let fileURL = tempDirectoryURL.appendingPathComponent("unknown-format.json")
        try writeJSON(envelopeDictionary(format: "com.filius.legacy.project"), to: fileURL)

        let store = TopologyProjectStore(fileURL: fileURL)

        XCTAssertThrowsError(try store.load()) { error in
            self.assertPersistenceError(
                error,
                expectedOperation: .load,
                expectedCode: .unsupportedFormat
            )
        }
    }

    func testLoadRejectsDuplicateRuntimeConfigurationEntries() throws {
        let nodeID = uuid("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")
        let payloadWithDuplicates: [String: Any] = [
            "graph": [
                "nodes": [],
                "links": []
            ],
            "viewport": [
                "offset": ["width": 0.0, "height": 0.0],
                "scale": 1.0
            ],
            "runtimeDeviceConfigurations": [
                [
                    "nodeID": nodeID.uuidString,
                    "ipAddress": "192.168.0.10",
                    "subnetMask": "255.255.255.0"
                ],
                [
                    "nodeID": nodeID.uuidString,
                    "ipAddress": "192.168.0.11",
                    "subnetMask": "255.255.255.0"
                ]
            ]
        ]

        let fileURL = tempDirectoryURL.appendingPathComponent("duplicate-runtime-config.json")
        try writeJSON(
            envelopeDictionary(payload: payloadWithDuplicates),
            to: fileURL
        )

        let store = TopologyProjectStore(fileURL: fileURL)

        XCTAssertThrowsError(try store.load()) { error in
            self.assertPersistenceError(
                error,
                expectedOperation: .load,
                expectedCode: .malformedPayload
            )
        }
    }

    func testLoadDirectoryURLReturnsFileReadFailed() throws {
        let directoryURL = tempDirectoryURL.appendingPathComponent("read-directory", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: false)

        let store = TopologyProjectStore(fileURL: directoryURL)

        XCTAssertThrowsError(try store.load()) { error in
            self.assertPersistenceError(
                error,
                expectedOperation: .load,
                expectedCode: .fileReadFailed
            )
        }
    }

    func testSaveDirectoryURLReturnsFileWriteFailed() throws {
        let directoryURL = tempDirectoryURL.appendingPathComponent("write-directory", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: false)

        let store = TopologyProjectStore(fileURL: directoryURL)

        XCTAssertThrowsError(try store.save(state: TopologyEditorState())) { error in
            self.assertPersistenceError(
                error,
                expectedOperation: .save,
                expectedCode: .fileWriteFailed
            )
        }
    }

    // MARK: - Helpers

    private func writeJSON(_ object: [String: Any], to fileURL: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        try data.write(to: fileURL)
    }

    private func envelopeDictionary(
        format: String = TopologyProjectStore.formatIdentifier,
        schemaVersion: Int = TopologyProjectStore.supportedSchemaVersion,
        payload: [String: Any]? = nil,
        extraEnvelopeFields: [String: Any] = [:]
    ) -> [String: Any] {
        let defaultPayload: [String: Any] = [
            "graph": [
                "nodes": [],
                "links": []
            ],
            "viewport": [
                "offset": ["width": 0.0, "height": 0.0],
                "scale": 1.0
            ],
            "runtimeDeviceConfigurations": [],
            "persistenceRevision": 0
        ]

        var envelope: [String: Any] = [
            "format": format,
            "schemaVersion": schemaVersion,
            "savedAt": ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: 1_700_000_000)),
            "saveReason": TopologyProjectSaveReason.autosave.rawValue,
            "payload": payload ?? defaultPayload
        ]

        for (key, value) in extraEnvelopeFields {
            envelope[key] = value
        }

        return envelope
    }

    private func assertPersistenceError(
        _ error: Error,
        expectedOperation: TopologyProjectPersistenceOperation,
        expectedCode: TopologyProjectPersistenceErrorCode,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let persistenceError = error as? TopologyProjectPersistenceError else {
            XCTFail("Expected TopologyProjectPersistenceError, got \(type(of: error))", file: file, line: line)
            return
        }

        XCTAssertEqual(persistenceError.operation, expectedOperation, file: file, line: line)
        XCTAssertEqual(persistenceError.code, expectedCode, file: file, line: line)
        XCTAssertFalse(persistenceError.detail.isEmpty, file: file, line: line)
    }

    private func uuid(_ rawValue: String) -> UUID {
        UUID(uuidString: rawValue) ?? UUID()
    }
}
