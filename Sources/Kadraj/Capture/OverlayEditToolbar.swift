import KadrajCore
import SwiftUI

/// Tools and actions under a fresh selection: annotate in place, then copy, save, pin,
/// read text / QR, open the big editor — or just press Return.
struct OverlayEditToolbar: View {
    @ObservedObject var model: EditorModel
    var onAction: (OverlayAction) -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 2) {
                ForEach(EditorTool.allCases.filter { $0 != .crop }, id: \.self) { tool in
                    Button { model.tool = tool } label: {
                        Image(systemName: tool.symbol).frame(width: 24, height: 22).contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .background(model.tool == tool ? Color.accentColor.opacity(0.3) : .clear, in: RoundedRectangle(cornerRadius: 5))
                    .help("\(tool.title) (\(String(tool.shortcut).uppercased()))")
                }
                Divider().frame(height: 18).padding(.horizontal, 4)
                ForEach(RGBAColor.palette, id: \.self) { color in
                    Button { model.style.color = color } label: {
                        Circle().fill(Color(cgColor: color.cgColor)).frame(width: 14, height: 14)
                            .overlay(Circle().stroke(model.style.color == color ? Color.accentColor : .secondary.opacity(0.5),
                                                     lineWidth: model.style.color == color ? 2.5 : 1))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 1)
                }
                Picker("", selection: $model.style.width) {
                    Text("S").tag(StrokeWidth.small)
                    Text("M").tag(StrokeWidth.medium)
                    Text("L").tag(StrokeWidth.large)
                }
                .pickerStyle(.segmented).frame(width: 84).padding(.leading, 4)
                Button { model.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                    .buttonStyle(.borderless).disabled(!model.history.canUndo).help("Geri Al (⌘Z)")
                Button { model.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                    .buttonStyle(.borderless).disabled(!model.history.canRedo).help("Yinele (⇧⌘Z)")
            }
            HStack(spacing: 6) {
                action("Metin", "text.viewfinder", .ocr, help: "Metni tanı ve kopyala")
                action("QR", "qrcode.viewfinder", .qr, help: "QR kodu oku")
                action("Pinle", "pin", .pin, help: "Ekrana sabitle")
                action("Editör", "macwindow", .editor, help: "Büyük editörde aç")
                Spacer(minLength: 12)
                Button { onCancel() } label: { Image(systemName: "xmark") }.help("İptal (Esc)")
                action("Kaydet", "square.and.arrow.down", .save, help: "Klasöre kaydet (⌘S)")
                action("Kopyala", "doc.on.doc", .copy, help: "Panoya kopyala (⌘C)")
                Button { onAction(.done) } label: { Label("Bitti", systemImage: "checkmark") }
                    .buttonStyle(.borderedProminent).help("Ayarlardaki gibi kaydet / kopyala (Return)")
            }
            .controlSize(.small)
        }
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.15), lineWidth: 1))
    }

    private func action(_ title: String, _ symbol: String, _ value: OverlayAction, help: String) -> some View {
        Button { onAction(value) } label: { Label(title, systemImage: symbol) }.help(help)
    }
}
