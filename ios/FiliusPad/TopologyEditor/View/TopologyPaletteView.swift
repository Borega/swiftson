import SwiftUI
import UIKit

struct TopologyPaletteView: View {
    let activeTool: TopologyEditorToolMode
    let simulationPhase: TopologySimulationPhase
    let onSelectTool: (TopologyEditorToolMode) -> Void
    let onStartSimulation: () -> Void
    let onStopSimulation: () -> Void
    let onPaletteDragPrepared: (TopologyNodeKind) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                toolButton(
                    title: "Select",
                    mode: .select,
                    draggableNodeKind: nil,
                    iconRelativePath: "allgemein/markierung.png",
                    fallbackSystemImage: "cursorarrow",
                    identifier: "palette.tool.select"
                )

                toolButton(
                    title: "Connect",
                    mode: .connect,
                    draggableNodeKind: nil,
                    iconRelativePath: "hardware/kabel.png",
                    fallbackSystemImage: "link",
                    identifier: "palette.tool.connect"
                )

                toolButton(
                    title: "PC",
                    mode: .place(.pc),
                    draggableNodeKind: .pc,
                    iconRelativePath: "hardware/server.png",
                    fallbackSystemImage: "desktopcomputer",
                    identifier: "palette.tool.place.pc"
                )

                toolButton(
                    title: "Switch",
                    mode: .place(.networkSwitch),
                    draggableNodeKind: .networkSwitch,
                    iconRelativePath: "hardware/switch.png",
                    fallbackSystemImage: "switch.2",
                    identifier: "palette.tool.place.switch"
                )

                Divider()
                    .frame(height: 42)
                    .padding(.horizontal, 4)

                runtimeControlButton(
                    title: "Start",
                    tint: .green,
                    isEnabled: simulationPhase == .stopped,
                    fallbackSystemImage: "play.fill",
                    identifier: "runtime.control.start",
                    action: onStartSimulation
                )

                runtimeControlButton(
                    title: "Stop",
                    tint: .red,
                    isEnabled: simulationPhase == .running,
                    fallbackSystemImage: "stop.fill",
                    identifier: "runtime.control.stop",
                    action: onStopSimulation
                )
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .accessibilityIdentifier("palette.toolbar.content")
        }
        .accessibilityIdentifier("palette.toolbar")
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))

            TopologyParityImageView(
                relativePath: "allgemein/leisten_hg.png",
                fallbackSystemImage: nil,
                contentMode: .fill
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .opacity(0.35)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.black.opacity(0.18), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var isEditingEnabled: Bool {
        simulationPhase == .stopped
    }

    private func toolButton(
        title: String,
        mode: TopologyEditorToolMode,
        draggableNodeKind: TopologyNodeKind?,
        iconRelativePath: String,
        fallbackSystemImage: String,
        identifier: String
    ) -> some View {
        let isSelected = activeTool == mode

        let label = VStack(spacing: 4) {
            TopologyParityImageView(
                relativePath: iconRelativePath,
                fallbackSystemImage: fallbackSystemImage,
                contentMode: .fit
            )
            .frame(width: 28, height: 24)
            .accessibilityHidden(true)

            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .frame(minWidth: 74)
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(isSelected ? Color.accentColor.opacity(0.9) : Color.black.opacity(0.08))
        .foregroundStyle(isSelected ? Color.white : Color.primary)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .opacity(isEditingEnabled ? 1 : 0.45)

        let baseButton = Button {
            onSelectTool(mode)
        } label: {
            label
        }
        .buttonStyle(.plain)
        .disabled(!isEditingEnabled)

        guard let draggableNodeKind, isEditingEnabled else {
            return AnyView(baseButton.accessibilityIdentifier(identifier))
        }

        return AnyView(
            baseButton
                .onDrag {
                    onPaletteDragPrepared(draggableNodeKind)
                    return NSItemProvider(object: draggableNodeKind.rawValue as NSString)
                }
                .accessibilityIdentifier(identifier)
        )
    }

    private func runtimeControlButton(
        title: String,
        tint: Color,
        isEnabled: Bool,
        fallbackSystemImage: String,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: fallbackSystemImage)
                    .font(.system(size: 14, weight: .bold))
                    .accessibilityHidden(true)

                Text(title)
                    .font(.caption.weight(.semibold))
            }
            .frame(minWidth: 74)
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(tint.opacity(isEnabled ? 0.92 : 0.35))
            .foregroundStyle(.white.opacity(isEnabled ? 1 : 0.8))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityIdentifier(identifier)
    }
}

private struct TopologyParityImageView: View {
    let relativePath: String
    let fallbackSystemImage: String?
    let contentMode: ContentMode

    var body: some View {
        if let image = TopologyParityAssetLoader.load(relativePath: relativePath) {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: contentMode)
        } else if let fallbackSystemImage {
            Image(systemName: fallbackSystemImage)
                .resizable()
                .aspectRatio(contentMode: contentMode)
        } else {
            Color.clear
        }
    }
}

private enum TopologyParityAssetLoader {
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
