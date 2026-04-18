import SwiftUI

struct TopologyPaletteView: View {
    let activeTool: TopologyEditorToolMode
    let simulationPhase: TopologySimulationPhase
    let onSelectTool: (TopologyEditorToolMode) -> Void
    let onStartSimulation: () -> Void
    let onStopSimulation: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                toolButton(
                    title: "Select",
                    mode: .select,
                    identifier: "palette.tool.select"
                )

                toolButton(
                    title: "Connect",
                    mode: .connect,
                    identifier: "palette.tool.connect"
                )

                toolButton(
                    title: "Place PC",
                    mode: .place(.pc),
                    identifier: "palette.tool.place.pc"
                )

                toolButton(
                    title: "Place Switch",
                    mode: .place(.networkSwitch),
                    identifier: "palette.tool.place.switch"
                )

                Divider()
                    .frame(height: 30)
                    .padding(.horizontal, 4)

                runtimeControlButton(
                    title: "Start",
                    tint: .green,
                    isEnabled: simulationPhase == .stopped,
                    identifier: "runtime.control.start",
                    action: onStartSimulation
                )

                runtimeControlButton(
                    title: "Stop",
                    tint: .red,
                    isEnabled: simulationPhase == .running,
                    identifier: "runtime.control.stop",
                    action: onStopSimulation
                )
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .accessibilityIdentifier("palette.toolbar.content")
        }
        .accessibilityIdentifier("palette.toolbar")
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func toolButton(title: String, mode: TopologyEditorToolMode, identifier: String) -> some View {
        let isSelected = activeTool == mode

        return Button {
            onSelectTool(mode)
        } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(minWidth: 90)
                .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.15))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }

    private func runtimeControlButton(
        title: String,
        tint: Color,
        isEnabled: Bool,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(minWidth: 90)
                .background(tint.opacity(isEnabled ? 0.95 : 0.25))
                .foregroundStyle(Color.white.opacity(isEnabled ? 1 : 0.85))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityIdentifier(identifier)
    }
}
