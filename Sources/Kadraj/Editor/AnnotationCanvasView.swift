import AppKit
import Combine
import KadrajCore

/// Shows the image fitted into the view and turns mouse input into annotations.
/// Drawing uses `AnnotationRenderer.draw` in image-pixel space, so the canvas and the
/// exported image always match.
final class AnnotationCanvasView: NSView, NSTextFieldDelegate {
    private let model: EditorModel
    private var cancellable: AnyCancellable?
    private var styleCancellable: AnyCancellable?
    /// The annotation being drawn or dragged (not yet in the history).
    private var draft: Annotation?
    private var dragStart: CGPoint?
    private var moveOriginal: Annotation?
    /// Crop rectangle being dragged (image pixels).
    private var cropDraft: CGRect?
    /// Inline text editor and what it edits.
    var textField: NSTextField?
    var textOrigin: CGPoint = .zero
    var editingTextID: UUID?
    /// An annotation hidden while it is edited inline.
    var draftHiddenID: UUID?
    var textStyle = AnnotationStyle(color: .red, width: .medium)
    var textSize: CGFloat = 40

    enum Command { case copy, save, saveAs }
    /// ⌘C / ⌘S / ⇧⌘S (the menu-less accessory app has no menu key equivalents).
    var onCommand: (Command) -> Void = { _ in }

    init(model: EditorModel) {
        self.model = model
        super.init(frame: .zero)
        styleCancellable = model.$style.dropFirst().sink { [weak self] style in
            DispatchQueue.main.async { self?.textStyleChanged(style) }
        }
        cancellable = model.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.needsDisplay = true }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: Geometry

    private var imageSize: CGSize { CGSize(width: model.base.width, height: model.base.height) }

    /// Fit with a margin, never larger than the image's natural (on-screen) size.
    private var scale: CGFloat {
        let margin: CGFloat = 24
        let natural = 1 / (window?.backingScaleFactor ?? 2)
        let fit = min((bounds.width - margin * 2) / imageSize.width, (bounds.height - margin * 2) / imageSize.height)
        return max(0.05, min(natural, fit))
    }

    private var imageRect: CGRect {
        let s = scale
        let size = CGSize(width: imageSize.width * s, height: imageSize.height * s)
        return CGRect(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2,
                      width: size.width, height: size.height)
    }

    /// View point → image pixel.
    func imagePoint(_ event: NSEvent) -> CGPoint {
        let p = convert(event.locationInWindow, from: nil)
        let r = imageRect, s = scale
        return CGPoint(x: (p.x - r.minX) / s, y: (p.y - r.minY) / s)
    }

    /// Image pixel → view point.
    func viewPoint(_ p: CGPoint) -> CGPoint {
        let r = imageRect, s = scale
        return CGPoint(x: r.minX + p.x * s, y: r.minY + p.y * s)
    }

    var viewScale: CGFloat { scale }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        NSColor.windowBackgroundColor.blended(withFraction: 0.15, of: .black)?.setFill()
        bounds.fill()

        let r = imageRect, s = scale
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: 2), blur: 12, color: NSColor.black.withAlphaComponent(0.35).cgColor)
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fill(r)
        ctx.restoreGState()

        ctx.saveGState()
        ctx.clip(to: r)
        ctx.translateBy(x: r.minX, y: r.minY)
        ctx.scaleBy(x: s, y: s)
        ctx.interpolationQuality = .high
        // Committed annotations come from a cached full-resolution layer (CoreImage blur/pixelate
        // runs once per edit, not on every mouse-drag frame); only the draft is drawn live.
        let excluded = draft?.id ?? draftHiddenID
        if let layer = committedLayer(excluding: excluded) {
            AnnotationRenderer.drawImage(layer, in: CGRect(origin: .zero, size: imageSize), ctx: ctx)
        }
        if let draft {
            AnnotationRenderer.draw(draft, in: ctx, base: model.base, imageHeight: imageSize.height)
        }
        let annotations = model.document.annotations.map { $0.id == draft?.id ? draft! : $0 }
        drawSelection(in: ctx, annotations: annotations)
        drawCrop(in: ctx)
        ctx.restoreGState()
    }

    private func drawSelection(in ctx: CGContext, annotations: [Annotation]) {
        guard let id = model.selection, let annotation = annotations.first(where: { $0.id == id }) else { return }
        let box = AnnotationGeometry.bounds(of: annotation.kind, width: annotation.style.width.rawValue).insetBy(dx: -4, dy: -4)
        ctx.saveGState()
        ctx.setStrokeColor(NSColor.controlAccentColor.cgColor)
        ctx.setLineWidth(1.5 / scale)
        ctx.setLineDash(phase: 0, lengths: [5 / scale, 4 / scale])
        ctx.stroke(box)
        ctx.restoreGState()
    }

    private var layerCache: (document: AnnotationDocument, excluded: UUID?, image: CGImage)?

    /// Base image + committed annotations (except `excluded`), without the crop.
    private func committedLayer(excluding excluded: UUID?) -> CGImage? {
        var doc = model.document
        doc.crop = nil
        if let cache = layerCache, cache.document == doc, cache.excluded == excluded { return cache.image }
        doc.annotations.removeAll { $0.id == excluded }
        guard let image = AnnotationRenderer.render(base: model.base, document: doc) else { return nil }
        var key = model.document
        key.crop = nil
        layerCache = (key, excluded, image)
        return image
    }

    /// Darkens everything outside the crop.
    func drawCrop(in ctx: CGContext) {
        guard let crop = cropDraft ?? model.document.crop else { return }
        let full = CGRect(origin: .zero, size: imageSize)
        ctx.saveGState()
        let path = CGMutablePath()
        path.addRect(full)
        path.addRect(crop)
        ctx.addPath(path)
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.55).cgColor)
        ctx.fillPath(using: .evenOdd)
        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.setLineWidth(1.5 / scale)
        ctx.setLineDash(phase: 0, lengths: [6 / scale, 4 / scale])
        ctx.stroke(crop)
        ctx.restoreGState()
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        if textField != nil { commitText() }
        window?.makeFirstResponder(self)
        let p = imagePoint(event)
        dragStart = p
        switch model.tool {
        case .select where event.clickCount == 2:
            if let id = AnnotationGeometry.hitTest(p, annotations: AnnotationRenderer.drawingOrder(model.document.annotations), tolerance: 8 / scale),
               let annotation = model.document.annotations.first(where: { $0.id == id }),
               case .text(let origin, let string, let size) = annotation.kind {
                model.selection = nil
                beginText(at: origin, editing: annotation.id, initial: string, style: annotation.style, size: size)
            }
        case .select:
            model.selection = AnnotationGeometry.hitTest(p, annotations: AnnotationRenderer.drawingOrder(model.document.annotations),
                                                         tolerance: 8 / scale)
            moveOriginal = model.document.annotations.first { $0.id == model.selection }
        case .pen, .highlighter:
            draft = Annotation(kind: model.tool == .pen ? .pen([p]) : .highlighter([p]), style: model.style)
        case .step:
            model.add(Annotation(kind: .step(center: p, number: model.document.nextStepNumber), style: model.style))
            dragStart = nil
        case .text:
            beginText(at: p, editing: nil, initial: "")
            dragStart = nil
        default:
            break
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart else { return }
        var p = imagePoint(event)
        let shift = event.modifierFlags.contains(.shift)
        let id = draft?.id ?? UUID()
        switch model.tool {
        case .select:
            if let original = moveOriginal {
                draft = original.translated(dx: p.x - start.x, dy: p.y - start.y)
            }
        case .arrow, .line:
            if shift { p = Self.snapTo45(from: start, to: p) }
            draft = Annotation(id: id, kind: model.tool == .arrow ? .arrow(start, p) : .line(start, p), style: model.style)
        case .rectangle, .ellipse, .blur, .pixelate:
            var rect = SelectionGeometry.normalizedRect(from: start, to: p)
            if shift, model.tool == .rectangle || model.tool == .ellipse {
                let side = max(rect.width, rect.height)
                rect = CGRect(x: p.x < start.x ? start.x - side : start.x, y: p.y < start.y ? start.y - side : start.y,
                              width: side, height: side)
            }
            let kind: AnnotationKind = switch model.tool {
            case .rectangle: .rectangle(rect)
            case .ellipse: .ellipse(rect)
            case .blur: .blur(rect)
            default: .pixelate(rect)
            }
            draft = Annotation(id: id, kind: kind, style: model.style)
        case .crop:
            let full = CGRect(origin: .zero, size: imageSize)
            cropDraft = SelectionGeometry.normalizedRect(from: start, to: p).intersection(full)
        case .pen, .highlighter:
            if case .pen(let points) = draft?.kind { draft?.kind = .pen(points + [p]) }
            if case .highlighter(let points) = draft?.kind { draft?.kind = .highlighter(points + [p]) }
        default:
            break
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if model.tool == .crop, let crop = cropDraft {
            cropDraft = nil
            dragStart = nil
            // Undoable; a tiny drag is ignored.
            if crop.width > 8, crop.height > 8 { model.setCrop(crop.integral) }
            needsDisplay = true
            return
        }
        defer {
            draft = nil
            dragStart = nil
            moveOriginal = nil
            needsDisplay = true
        }
        guard let draft else { return }
        if model.tool == .select {
            model.replace(draft)
        } else if Self.isMeaningful(draft) {
            model.add(draft)
        }
    }

    // MARK: Keyboard

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let chars = event.charactersIgnoringModifiers?.lowercased() ?? ""
        if flags.contains(.command) {
            switch chars {
            case "z": flags.contains(.shift) ? model.redo() : model.undo()
            case "c": onCommand(.copy)
            case "s": onCommand(flags.contains(.shift) ? .saveAs : .save)
            default: super.keyDown(with: event)
            }
            return
        }
        switch event.keyCode {
        case 51, 117: model.deleteSelection()          // Delete, Forward Delete
        case 53:                                       // Esc
            if cropDraft != nil {
                cropDraft = nil
                needsDisplay = true
            } else if model.tool == .crop, model.document.crop != nil {
                model.setCrop(nil) // Esc in the crop tool removes the crop (undoable)
            } else {
                model.selection = nil
            }
        default:
            if let c = chars.first, let tool = EditorTool.allCases.first(where: { $0.shortcut == c }), flags.isEmpty {
                model.tool = tool
            } else {
                super.keyDown(with: event)
            }
        }
    }

    // MARK: Helpers

    static func snapTo45(from a: CGPoint, to b: CGPoint) -> CGPoint {
        let dx = b.x - a.x, dy = b.y - a.y
        let length = hypot(dx, dy)
        let angle = (atan2(dy, dx) / (.pi / 4)).rounded() * (.pi / 4)
        return CGPoint(x: a.x + length * cos(angle), y: a.y + length * sin(angle))
    }

    /// Ignore accidental clicks that would create invisible annotations.
    static func isMeaningful(_ a: Annotation) -> Bool {
        switch a.kind {
        case .arrow(let p, let q), .line(let p, let q): return hypot(q.x - p.x, q.y - p.y) > 4
        case .rectangle(let r), .ellipse(let r), .blur(let r), .pixelate(let r): return r.width > 3 && r.height > 3
        case .pen(let pts), .highlighter(let pts): return pts.count > 1
        default: return true
        }
    }
}

// MARK: - Text tool

extension AnnotationCanvasView {
    /// Text size in image pixels for each stroke width.
    static func fontSize(for width: StrokeWidth) -> CGFloat {
        switch width {
        case .small: 28
        case .medium: 40
        case .large: 60
        }
    }

    /// `style`/`size` default to the toolbar; when editing, the annotation keeps its own.
    func beginText(at origin: CGPoint, editing id: UUID?, initial: String,
                   style: AnnotationStyle? = nil, size: CGFloat? = nil) {
        let style = style ?? model.style
        let size = size ?? Self.fontSize(for: model.style.width)
        textStyle = style
        textSize = size
        let field = NSTextField(string: initial)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = NSFont.boldSystemFont(ofSize: size * viewScale)
        field.textColor = NSColor(cgColor: style.color.cgColor)
        field.placeholderString = "Metin"
        field.delegate = self
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        let p = viewPoint(origin)
        field.frame = CGRect(x: p.x - 2, y: p.y, width: max(240, bounds.maxX - p.x - 8), height: size * viewScale * 1.4)
        addSubview(field)
        window?.makeFirstResponder(field)
        textField = field
        textOrigin = origin
        editingTextID = id
        if let id { // hide the original while editing
            draftHiddenID = id
        }
        needsDisplay = true
    }

    /// Toolbar color/width changes while typing restyle the text being edited.
    func textStyleChanged(_ style: AnnotationStyle) {
        guard let field = textField else { return }
        textStyle = style
        textSize = Self.fontSize(for: style.width)
        field.textColor = NSColor(cgColor: style.color.cgColor)
        field.font = NSFont.boldSystemFont(ofSize: textSize * viewScale)
    }

    func commitText() {
        guard let field = textField else { return }
        let string = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        // Detach first: removing an editing field fires controlTextDidEndEditing synchronously,
        // which would otherwise commit a second time.
        textField = nil
        field.delegate = nil
        field.removeFromSuperview()
        draftHiddenID = nil
        let size = textSize
        let style = textStyle
        if let id = editingTextID, var annotation = model.document.annotations.first(where: { $0.id == id }) {
            if string.isEmpty {
                model.selection = id
                model.deleteSelection()
            } else {
                annotation.kind = .text(origin: textOrigin, string: string, fontSize: size)
                annotation.style = style
                model.replace(annotation)
            }
        } else if editingTextID == nil, !string.isEmpty {
            // (If the edited text was undone away meanwhile, it isn't re-created.)
            model.add(Annotation(kind: .text(origin: textOrigin, string: string, fontSize: size), style: style))
        }
        editingTextID = nil
        window?.makeFirstResponder(self)
        needsDisplay = true
    }

    func cancelText() {
        let field = textField
        textField = nil
        field?.delegate = nil
        field?.removeFromSuperview()
        editingTextID = nil
        draftHiddenID = nil
        window?.makeFirstResponder(self)
        needsDisplay = true
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)): commitText(); return true
        case #selector(NSResponder.cancelOperation(_:)): cancelText(); return true
        default: return false
        }
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        if textField != nil { commitText() }
    }
}
