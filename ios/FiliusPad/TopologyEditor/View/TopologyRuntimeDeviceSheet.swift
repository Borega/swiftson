import SwiftUI

struct TopologyRuntimeDeviceSheet: View {
    let nodeID: UUID
    let nodeKind: TopologyNodeKind
    let configuration: TopologyRuntimeDeviceConfiguration?
    let consoleEntries: [String]
    let onSaveConfiguration: (String, String) -> Void
    let onExecuteCommand: (String) -> Void
    let onClose: () -> Void

    @State private var ipAddress: String
    @State private var subnetMask: String
    @State private var command: String

    init(
        nodeID: UUID,
        nodeKind: TopologyNodeKind,
        configuration: TopologyRuntimeDeviceConfiguration?,
        consoleEntries: [String],
        onSaveConfiguration: @escaping (String, String) -> Void,
        onExecuteCommand: @escaping (String) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.nodeID = nodeID
        self.nodeKind = nodeKind
        self.configuration = configuration
        self.consoleEntries = consoleEntries
        self.onSaveConfiguration = onSaveConfiguration
        self.onExecuteCommand = onExecuteCommand
        self.onClose = onClose

        _ipAddress = State(initialValue: configuration?.ipAddress ?? "")
        _subnetMask = State(initialValue: configuration?.subnetMask ?? "")
        _command = State(initialValue: "")
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                runtimeHeader
                configurationSection
                commandSection
                consoleSection
                Spacer(minLength: 0)
            }
            .padding(16)
            .navigationTitle("Runtime Device")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done", action: onClose)
                        .accessibilityIdentifier("runtime.device.close")
                }
            }
        }
        .accessibilityIdentifier("runtime.device.sheet")
        .onChange(of: nodeID) { _ in
            synchronizeConfigurationFields()
            command = ""
        }
        .onChange(of: configuration) { _ in
            synchronizeConfigurationFields()
        }
    }

    private var runtimeHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Device: \(deviceTitle)")
                .font(.headline)
                .accessibilityIdentifier("runtime.device.sheet.title")

            Text("Node ID: \(nodeID.uuidString)")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .accessibilityIdentifier("runtime.device.sheet.nodeID")
        }
    }

    private var configurationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("IP Configuration")
                .font(.subheadline.weight(.semibold))

            TextField("IPv4 address", text: $ipAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.numbersAndPunctuation)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("runtime.device.ip")

            TextField("Subnet mask", text: $subnetMask)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.numbersAndPunctuation)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("runtime.device.subnet")

            Button("Save IP Configuration") {
                onSaveConfiguration(ipAddress, subnetMask)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("runtime.device.save")
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var commandSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Command")
                .font(.subheadline.weight(.semibold))

            TextField("ping <target-ipv4>", text: $command)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("runtime.device.command")

            Button("Execute") {
                onExecuteCommand(command)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("runtime.device.execute")
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var consoleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Console")
                .font(.subheadline.weight(.semibold))

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    if consoleEntries.isEmpty {
                        Text("No runtime output yet")
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("runtime.device.console.empty")
                    } else {
                        ForEach(Array(consoleEntries.enumerated()), id: \.offset) { index, line in
                            Text(line)
                                .font(.caption.monospaced())
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .accessibilityIdentifier("runtime.device.console.line.\(index)")
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 120, maxHeight: 220)
            .accessibilityIdentifier("runtime.device.console.list")
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var deviceTitle: String {
        switch nodeKind {
        case .pc:
            return "PC"
        case .networkSwitch:
            return "Switch"
        case .unsupported:
            return "Unsupported"
        }
    }

    private func synchronizeConfigurationFields() {
        ipAddress = configuration?.ipAddress ?? ""
        subnetMask = configuration?.subnetMask ?? ""
    }
}
