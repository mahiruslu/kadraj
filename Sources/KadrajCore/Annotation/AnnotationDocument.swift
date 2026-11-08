import CoreGraphics

public struct AnnotationDocument: Equatable, Sendable {
    public let imageSize: CGSize
    public var annotations: [Annotation]
    /// Crop in image pixels (top-left origin); nil = whole image.
    public var crop: CGRect?

    public init(imageSize: CGSize, annotations: [Annotation] = [], crop: CGRect? = nil) {
        self.imageSize = imageSize
        self.annotations = annotations
        self.crop = crop
    }

    /// Numbers never shift when a step is deleted: the next one is the highest + 1.
    public var nextStepNumber: Int {
        annotations.reduce(0) { current, annotation in
            if case .step(_, let number) = annotation.kind { return max(current, number) }
            return current
        } + 1
    }
}

/// Snapshot-based undo/redo.
public struct EditHistory: Sendable {
    public static let limit = 100
    private var undoStack: [AnnotationDocument] = []
    private var redoStack: [AnnotationDocument] = []
    public private(set) var current: AnnotationDocument

    public init(_ document: AnnotationDocument) { current = document }

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }

    public mutating func apply(_ change: (inout AnnotationDocument) -> Void) {
        var next = current
        change(&next)
        guard next != current else { return }
        undoStack.append(current)
        if undoStack.count > Self.limit { undoStack.removeFirst(undoStack.count - Self.limit) }
        redoStack.removeAll()
        current = next
    }

    public mutating func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(current)
        current = previous
    }

    public mutating func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(current)
        current = next
    }
}
