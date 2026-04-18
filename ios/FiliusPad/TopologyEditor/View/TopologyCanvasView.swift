import SwiftUI
import UIKit

struct TopologyCanvasView: View {
    let state: TopologyEditorState
    let onTap: (CGPoint) -> Void
    let onNodeDragChanged: (UUID, CGSize) -> Void
    let onNodeDragEnded: (UUID) -> Void
    let onCanvasPan: (CGSize) -> Void
    let onCanvasPanEnded: () -> Void
    let onMagnify: (CGFloat, CGPoint) -> Void
    let onMagnifyEnded: () -> Void

    @State private var panTranslation: CGSize = .zero
    @State private var magnification: CGFloat = 1

    private let nodeDiameter: CGFloat = 68

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemBackground))

                TopologyCanvasParityBackground()
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .opacity(0.3)

                linkLayer
                    .accessibilityIdentifier("canvas.linkLayer")

                nodeLayer
                    .accessibilityIdentifier("canvas.nodeLayer")
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(Rectangle())
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.black.opacity(0.28), lineWidth: 1)
            }
            .accessibilityIdentifier("canvas.surface")
            .simultaneousGesture(tapGesture)
            .simultaneousGesture(canvasPanGesture)
            .simultaneousGesture(magnificationGesture(canvasSize: proxy.size))
        }
    }

    private var linkLayer: some View {
        ZStack {
            ForEach(state.graph.links) { link in
                if let projection = state.graph.linkProjection(for: link) {
                    Path { path in
                        path.move(to: state.viewport.worldToScreen(projection.source))
                        path.addLine(to: state.viewport.worldToScreen(projection.target))
                    }
                    .stroke(
                        Color.black.opacity(0.7),
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
                    )
                    .overlay {
                        Path { path in
                            path.move(to: state.viewport.worldToScreen(projection.source))
                            path.addLine(to: state.viewport.worldToScreen(projection.target))
                        }
                        .stroke(
                            Color.white.opacity(0.25),
                            style: StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round)
                        )
                    }
                    .accessibilityIdentifier("canvas.link.\(link.id.uuidString)")
                }
            }
        }
        .drawingGroup()
    }

    private var nodeLayer: some View {
        ZStack {
            ForEach(state.graph.nodes) { node in
                nodeView(node)
            }
        }
    }

    private func nodeView(_ node: TopologyNode) -> some View {
        let isSelected = state.selectedNodeIDs.contains(node.id)
        let screenPosition = state.viewport.worldToScreen(node.position)

        return VStack(spacing: 4) {
            TopologyCanvasNodeIcon(
                kind: node.kind,
                isSelected: isSelected
            )
            .frame(width: nodeDiameter, height: nodeDiameter)
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.accentColor, lineWidth: 2)
                }
            }

            Text(node.kind.rawValue)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(Color.white.opacity(0.65))
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        }
        .position(screenPosition)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityNodeLabel(for: node.kind))
        .accessibilityHint(state.simulationPhase == .running ? "Opens runtime device panel" : "Topology node")
        .accessibilityAddTraits(state.simulationPhase == .running ? .isButton : [])
        .accessibilityIdentifier("canvas.node.\(node.id.uuidString)")
        .highPriorityGesture(
            DragGesture(minimumDistance: 6)
                .onChanged { drag in
                    onNodeDragChanged(node.id, drag.translation)
                }
                .onEnded { _ in
                    onNodeDragEnded(node.id)
                }
        )
    }

    private var tapGesture: some Gesture {
        SpatialTapGesture()
            .onEnded { value in
                onTap(value.location)
            }
    }

    private var canvasPanGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                let delta = CGSize(
                    width: value.translation.width - panTranslation.width,
                    height: value.translation.height - panTranslation.height
                )
                panTranslation = value.translation
                onCanvasPan(delta)
            }
            .onEnded { _ in
                panTranslation = .zero
                onCanvasPanEnded()
            }
    }

    private func magnificationGesture(canvasSize: CGSize) -> some Gesture {
        MagnificationGesture()
            .onChanged { value in
                let delta = value / magnification
                magnification = value
                onMagnify(
                    delta,
                    CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
                )
            }
            .onEnded { _ in
                magnification = 1
                onMagnifyEnded()
            }
    }

    private func accessibilityNodeLabel(for kind: TopologyNodeKind) -> String {
        switch kind {
        case .pc:
            return "PC node"
        case .networkSwitch:
            return "Switch node"
        case .unsupported:
            return "Unsupported node"
        }
    }
}

private struct TopologyCanvasParityBackground: View {
    var body: some View {
        if let image = TopologyParityAssetLoader.load(relativePath: "allgemein/entwurfshg.png") {
            Image(uiImage: image)
                .resizable(resizingMode: .tile)
                .opacity(0.35)
        } else {
            Color(uiColor: .secondarySystemBackground)
        }
    }
}

private struct TopologyCanvasNodeIcon: View {
    let kind: TopologyNodeKind
    let isSelected: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.22) : Color.black.opacity(0.06))

            if let image = TopologyParityAssetLoader.load(relativePath: iconRelativePath(for: kind)) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(8)
            } else {
                Image(systemName: fallbackSystemImage(for: kind))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(14)
                    .foregroundStyle(Color.primary)
            }
        }
    }

    private func iconRelativePath(for kind: TopologyNodeKind) -> String {
        switch kind {
        case .pc:
            return "hardware/server.png"
        case .networkSwitch:
            return "hardware/switch.png"
        case .unsupported:
            return "hardware/cloud.png"
        }
    }

    private func fallbackSystemImage(for kind: TopologyNodeKind) -> String {
        switch kind {
        case .pc:
            return "desktopcomputer"
        case .networkSwitch:
            return "switch.2"
        case .unsupported:
            return "questionmark.circle"
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
