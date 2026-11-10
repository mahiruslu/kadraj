import KadrajCore
import SwiftUI

struct EditorToolbar: View {
    @ObservedObject var model: EditorModel
    var onCopy: () -> Void
    var onSave: () -> Void
    var onPin: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 2) {
                ForEach(EditorTool.allCases, id: \.self) { tool in
                    Button { model.tool = tool } label: {
                        Image(systemName: tool.symbol)
                            .frame(width: 26, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .background(model.tool == tool ? Color.accentColor.opacity(0.25) : .clear,
                                in: RoundedRectangle(cornerRadius: 5))
                    .help(Text(verbatim: "\(tool.title) (\(String(tool.shortcut).uppercased()))"))
                }
            }
            Divider().frame(height: 20)
            HStack(spacing: 5) {
                ForEach(RGBAColor.palette, id: \.self) { color in
                    Button { model.style.color = color } label: {
                        Circle()
                            .fill(Color(cgColor: color.cgColor))
                            .frame(width: 16, height: 16)
                            .overlay(Circle().stroke(model.style.color == color ? Color.accentColor : .secondary.opacity(0.5),
                                                     lineWidth: model.style.color == color ? 2.5 : 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            Picker("", selection: $model.style.width) {
                Text(verbatim: "S").tag(StrokeWidth.small)
                Text(verbatim: "M").tag(StrokeWidth.medium)
                Text(verbatim: "L").tag(StrokeWidth.large)
            }
            .pickerStyle(.segmented)
            .frame(width: 96)
            .help("Stroke width")
            Divider().frame(height: 20)
            Button { model.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                .disabled(!model.history.canUndo).help("Undo (⌘Z)")
            Button { model.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                .disabled(!model.history.canRedo).help("Redo (⇧⌘Z)")
            Spacer()
            Button("Pin", action: onPin).help("Pin to screen")
            Button("Copy", action: onCopy).help("Copy (⌘C)")
            Button("Save", action: onSave).help("Save (⌘S)") // no default-button: Return must not overwrite the file
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
