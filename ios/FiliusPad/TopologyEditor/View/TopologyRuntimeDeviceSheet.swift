import SwiftUI
import UIKit

struct TopologyRuntimeDeviceSheet: View {
    let nodeID: UUID
    let nodeKind: TopologyNodeKind
    let configuration: TopologyRuntimeDeviceConfiguration?
    let installedPrograms: Set<TopologyRuntimeInstallableProgram>
    let consoleEntries: [String]
    let onSaveConfiguration: (String, String) -> Void
    let onInstallProgram: (TopologyRuntimeInstallableProgram) -> Void
    let onExecuteCommand: (String) -> Void
    let onClose: () -> Void

    @State private var ipAddress: String
    @State private var subnetMask: String
    @State private var command: String
    @State private var installerExpanded = false

    init(
        nodeID: UUID,
        nodeKind: TopologyNodeKind,
        configuration: TopologyRuntimeDeviceConfiguration?,
        installedPrograms: Set<TopologyRuntimeInstallableProgram>,
        consoleEntries: [String],
        onSaveConfiguration: @escaping (String, String) -> Void,
        onInstallProgram: @escaping (TopologyRuntimeInstallableProgram) -> Void,
        onExecuteCommand: @escaping (String) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.nodeID = nodeID
        self.nodeKind = nodeKind
        self.configuration = configuration
        self.installedPrograms = installedPrograms
        self.consoleEntries = consoleEntries
        self.onSaveConfiguration = onSaveConfiguration
        self.onInstallProgram = onInstallProgram
        self.onExecuteCommand = onExecuteCommand
        self.onClose = onClose

        _ipAddress = State(initialValue: configuration?.ipAddress ?? "")
        _subnetMask = State(initialValue: configuration?.subnetMask ?? "")
        _command = State(initialValue: "")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    runtimeHeader

                    switch nodeKind {
                    case .pc:
                        desktopSection
                        if installerExpanded {
                            installerSection
                        }
                        configurationSection
                        if hasCommandPromptInstalled {
                            commandSection
                            consoleSection
                        } else {
                            commandLockedSection
                        }

                    case .networkSwitch:
                        switchInfoSection

                    case .unsupported:
                        unsupportedInfoSection
                    }
                }
                .padding(16)
            }
            .background(Color(red: 0.95, green: 0.95, blue: 0.95))
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
        .preferredColorScheme(.light)
        .onChange(of: nodeID) { _ in
            synchronizeConfigurationFields()
            command = ""
        }
        .onChange(of: configuration) { _ in
            synchronizeConfigurationFields()
        }
        .onChange(of: installedPrograms) { _ in
            if !hasCommandPromptInstalled {
                command = ""
            }
        }
    }

    private var hasCommandPromptInstalled: Bool {
        installedPrograms.contains(.commandPrompt)
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

    private var desktopSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Desktop")
                .font(.subheadline.weight(.semibold))

            ZStack {
                RuntimeDesktopBackgroundView()
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        ForEach(TopologyRuntimeInstallableProgram.allCases.filter { installedPrograms.contains($0) }, id: \.self) { program in
                            RuntimeDesktopProgramIcon(program: program)
                        }

                        RuntimeDesktopInstallerIcon(isExpanded: installerExpanded) {
                            installerExpanded.toggle()
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Text("Installed: \(installedPrograms.map(\.desktopName).sorted().joined(separator: ", ").ifEmpty("none"))")
                        .font(.caption)
                        .foregroundStyle(.white)
                }
                .padding(12)
            }
            .frame(minHeight: 130)
            .accessibilityIdentifier("runtime.device.desktop")
        }
    }

    private var installerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Software Installation")
                .font(.subheadline.weight(.semibold))

            ForEach(TopologyRuntimeInstallableProgram.allCases.filter { !installedPrograms.contains($0) }, id: \.self) { program in
                HStack(spacing: 10) {
                    RuntimeDesktopProgramIcon(program: program, compact: true)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(program.desktopName)
                            .font(.subheadline.weight(.semibold))
                        Text(program.desktopDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 8)

                    Button("Install") {
                        onInstallProgram(program)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("runtime.device.install.\(program.rawValue)")
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityIdentifier("runtime.device.installer")
    }

    private var switchInfoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Switch Configuration")
                .font(.subheadline.weight(.semibold))

            Text("Switches do not have IP addresses in FILIUS. Configure switching behavior and links; host IP configuration belongs to PCs.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("runtime.device.switch.info")
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var unsupportedInfoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Unsupported Device")
                .font(.subheadline.weight(.semibold))
            Text("This runtime device kind is not yet emulated.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
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

            Text("IPv4 is the default transport model. IPv6 may be added later as an optional extension.")
                .font(.caption)
                .foregroundStyle(.secondary)

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

    private var commandLockedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Terminal")
                .font(.subheadline.weight(.semibold))
            Text("Install CMD from Software Installation to run commands.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("runtime.device.command.locked")
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var commandSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CMD")
                .font(.subheadline.weight(.semibold))

            TextField("ping|trace <target-ipv4> or <hostname>", text: $command)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("runtime.device.command")

            Text("Supported: ping <target-ipv4|hostname>, trace <target-ipv4|hostname>, dhcp lease <ipv4> <subnet-mask>, dhcp release, dns add <hostname> <target-ipv4>, dns remove <hostname>, dns resolve <hostname>")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("runtime.device.command.help")

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

private struct RuntimeDesktopBackgroundView: View {
    var body: some View {
        if let image = RuntimeDesktopParityAssetLoader.load(relativePath: "desktop/hintergrundbild.png") {
            Image(uiImage: image)
                .resizable(resizingMode: .tile)
        } else {
            LinearGradient(
                colors: [
                    Color(red: 0.20, green: 0.45, blue: 0.80),
                    Color(red: 0.12, green: 0.30, blue: 0.62)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

private struct RuntimeDesktopInstallerIcon: View {
    let isExpanded: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                RuntimeDesktopImageView(
                    relativePath: "desktop/icon_softwareinstallation.png",
                    fallbackSystemImage: "shippingbox"
                )
                .frame(width: 42, height: 42)

                Text(isExpanded ? "Installer ▾" : "Installer")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
            }
            .padding(6)
            .background(Color.black.opacity(0.18))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("runtime.device.install.open")
    }
}

private struct RuntimeDesktopProgramIcon: View {
    let program: TopologyRuntimeInstallableProgram
    var compact = false

    var body: some View {
        VStack(spacing: 4) {
            RuntimeDesktopImageView(
                relativePath: program.desktopIconRelativePath,
                fallbackSystemImage: program.fallbackSystemImage
            )
            .frame(width: compact ? 24 : 42, height: compact ? 24 : 42)

            if !compact {
                Text(program.desktopName)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
            }
        }
        .padding(compact ? 0 : 6)
        .background(compact ? Color.clear : Color.black.opacity(0.18))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct RuntimeDesktopImageView: View {
    let relativePath: String
    let fallbackSystemImage: String

    var body: some View {
        if let image = RuntimeDesktopParityAssetLoader.load(relativePath: relativePath) {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: fallbackSystemImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(.white)
        }
    }
}

private enum RuntimeDesktopParityAssetLoader {
    static func load(relativePath: String) -> UIImage? {
        guard !relativePath.isEmpty else {
            return nil
        }

        let bundleRelativePath = "JavaParity/\(relativePath)"
        if let directURL = Bundle.main.resourceURL?.appendingPathComponent(bundleRelativePath),
           FileManager.default.fileExists(atPath: directURL.path),
           let image = UIImage(contentsOfFile: directURL.path) {
            return image
        }

        let nsPath = bundleRelativePath as NSString
        let folder = nsPath.deletingPathExtension
        let ext = nsPath.pathExtension

        if !ext.isEmpty,
           let fallbackURL = Bundle.main.url(forResource: folder, withExtension: ext),
           let image = UIImage(contentsOfFile: fallbackURL.path) {
            return image
        }

        return nil
    }
}

private extension TopologyRuntimeInstallableProgram {
    var desktopName: String {
        switch self {
        case .commandPrompt:
            return "CMD"
        case .webServer:
            return "Web Server"
        case .echoServer:
            return "Echo Server"
        case .dnsServer:
            return "DNS Server"
        case .dhcpServer:
            return "DHCP Server"
        }
    }

    var desktopDescription: String {
        switch self {
        case .commandPrompt:
            return "Command shell for ping/trace/dhcp/dns commands"
        case .webServer:
            return "HTTP service placeholder (parity scaffold)"
        case .echoServer:
            return "Echo service placeholder (parity scaffold)"
        case .dnsServer:
            return "DNS service app placeholder (parity scaffold)"
        case .dhcpServer:
            return "DHCP service app placeholder (parity scaffold)"
        }
    }

    var desktopIconRelativePath: String {
        switch self {
        case .commandPrompt:
            return "desktop/icon_terminal.png"
        case .webServer:
            return "desktop/icon_webserver.png"
        case .echoServer:
            return "desktop/icon_serverbaustein.png"
        case .dnsServer:
            return "desktop/icon_dns.png"
        case .dhcpServer:
            return "desktop/icon_serverbaustein.png"
        }
    }

    var fallbackSystemImage: String {
        switch self {
        case .commandPrompt:
            return "terminal"
        case .webServer:
            return "network"
        case .echoServer:
            return "dot.radiowaves.left.and.right"
        case .dnsServer:
            return "globe"
        case .dhcpServer:
            return "server.rack"
        }
    }
}

private extension String {
    func ifEmpty(_ fallback: String) -> String {
        isEmpty ? fallback : self
    }
}
