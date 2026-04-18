import SwiftUI

struct TopologyPaletteView: View {
    let activeTool: TopologyEditorToolMode
    let onSelectTool: (TopologyEditorToolMode) -> Void

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
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
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
}
