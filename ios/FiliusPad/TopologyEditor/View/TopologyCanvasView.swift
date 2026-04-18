import SwiftUI

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

    private let nodeDiameter: CGFloat = 56

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemBackground))

                linkLayer
                    .accessibilityIdentifier("canvas.linkLayer")

                nodeLayer
                    .accessibilityIdentifier("canvas.nodeLayer")
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(Rectangle())
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.secondary.opacity(0.35), lineWidth: 1)
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
                    .stroke(Color.secondary, style: StrokeStyle(lineWidth: 3, lineCap: .round))
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
            Text(nodeLabel(for: node.kind))
                .font(.caption.weight(.bold))

            Text(node.kind.rawValue)
                .font(.caption2)
        }
        .foregroundStyle(isSelected ? Color.white : Color.primary)
        .frame(width: nodeDiameter, height: nodeDiameter)
        .background(nodeBackground(for: node.kind, isSelected: isSelected))
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

    private func nodeLabel(for kind: TopologyNodeKind) -> String {
        switch kind {
        case .pc:
            return "PC"
        case .networkSwitch:
            return "SW"
        case .unsupported:
            return "?"
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

    @ViewBuilder
    private func nodeBackground(for kind: TopologyNodeKind, isSelected: Bool) -> some View {
        switch kind {
        case .pc:
            Circle()
                .fill(isSelected ? Color.accentColor : Color.blue.opacity(0.25))
        case .networkSwitch:
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? Color.accentColor : Color.green.opacity(0.25))
        case .unsupported:
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? Color.accentColor : Color.red.opacity(0.3))
        }
    }
}
