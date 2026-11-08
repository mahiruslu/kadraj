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
                    .help("\(tool.title) (\(String(tool.shortcut).uppercased()))")
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
                Text("S").tag(StrokeWidth.small)
                Text("M").tag(StrokeWidth.medium)
                Text("L").tag(StrokeWidth.large)
            }
            .pickerStyle(.segmented)
            .frame(width: 96)
            .help("Kalınlık")
            Divider().frame(height: 20)
            Button { model.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                .disabled(!model.history.canUndo).help("Geri Al (⌘Z)")
            Button { model.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                .disabled(!model.history.canRedo).help("Yinele (⇧⌘Z)")
            Spacer()
            Button("Pinle", action: onPin).help("Ekrana sabitle")
            Button("Kopyala", action: onCopy).help("Kopyala (⌘C)")
            Button("Kaydet", action: onSave).help("Kaydet (⌘S)") // no default-button: Return must not overwrite the file
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
