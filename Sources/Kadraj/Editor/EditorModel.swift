import AppKit
import KadrajCore

enum EditorTool: String, CaseIterable {
    case select, arrow, line, rectangle, ellipse, pen, highlighter, text, step, blur, pixelate, crop

    var title: String {
        switch self {
        case .select: "Seç"
        case .arrow: "Ok"
        case .line: "Çizgi"
        case .rectangle: "Dikdörtgen"
        case .ellipse: "Elips"
        case .pen: "Kalem"
        case .highlighter: "Vurgulayıcı"
        case .text: "Metin"
        case .step: "Numaralı Adım"
        case .blur: "Bulanıklaştır"
        case .pixelate: "Mozaik"
        case .crop: "Kırp"
        }
    }

    var symbol: String {
        switch self {
        case .select: "cursorarrow"
        case .arrow: "arrow.up.right"
        case .line: "line.diagonal"
        case .rectangle: "rectangle"
        case .ellipse: "circle"
        case .pen: "pencil.tip"
        case .highlighter: "highlighter"
        case .text: "textformat"
        case .step: "1.circle"
        case .blur: "drop"
        case .pixelate: "squareshape.split.3x3"
        case .crop: "crop"
        }
    }

    /// Single-key shortcut (no modifiers).
    var shortcut: Character {
        switch self {
        case .select: "v"
        case .arrow: "a"
        case .line: "l"
        case .rectangle: "r"
        case .ellipse: "o"
        case .pen: "p"
        case .highlighter: "h"
        case .text: "t"
        case .step: "n"
        case .blur: "b"
        case .pixelate: "m"
        case .crop: "c"
        }
    }
}

@MainActor
final class EditorModel: ObservableObject {
    @Published private(set) var history: EditHistory
    @Published var tool: EditorTool = .arrow {
        didSet { if tool != .select { selection = nil } }
    }
    @Published var style = AnnotationStyle(color: .red, width: .medium) {
        didSet { applyStyleToSelection() }
    }
    @Published var selection: UUID?
    let base: CGImage
    private(set) var sourceURL: URL?
    /// Document state at the last save; used to detect unsaved changes.
    private var savedDocument: AnnotationDocument

    init(base: CGImage, sourceURL: URL?) {
        self.base = base
        self.sourceURL = sourceURL
        let doc = AnnotationDocument(imageSize: CGSize(width: base.width, height: base.height))
        history = EditHistory(doc)
        savedDocument = doc
    }

    var document: AnnotationDocument { history.current }
    var hasUnsavedChanges: Bool { document != savedDocument }

    func add(_ annotation: Annotation) {
        history.apply { $0.annotations.append(annotation) }
    }

    func replace(_ annotation: Annotation) {
        history.apply { doc in
            if let i = doc.annotations.firstIndex(where: { $0.id == annotation.id }) { doc.annotations[i] = annotation }
        }
    }

    func deleteSelection() {
        guard let id = selection else { return }
        history.apply { $0.annotations.removeAll { $0.id == id } }
        selection = nil
    }

    func setCrop(_ rect: CGRect?) {
        history.apply { $0.crop = rect }
    }

    func undo() { history.undo(); dropStaleSelection() }
    func redo() { history.redo(); dropStaleSelection() }

    func render() -> CGImage? { AnnotationRenderer.render(base: base, document: document) }

    func markSaved(at url: URL) {
        sourceURL = url
        savedDocument = document
    }

    private func dropStaleSelection() {
        if let id = selection, !document.annotations.contains(where: { $0.id == id }) { selection = nil }
    }

    /// Changing color or width while something is selected restyles it (one undo step).
    private func applyStyleToSelection() {
        guard let id = selection, var annotation = document.annotations.first(where: { $0.id == id }),
              annotation.style != style else { return }
        annotation.style = style
        replace(annotation)
    }
}
