import AppKit
import Observation

/// Transient gesture bookkeeping that should NOT trigger view updates.
final class EditorDragState {
    var began = false
    var lastImagePoint: CGPoint?
}

// MARK: - Annotation

public struct Annotation: Identifiable, Equatable {
    public enum Kind: Equatable {
        case rectangle
        case ellipse
        case arrow
        case pen([CGPoint])
        case text
        case highlight
        case mosaic
    }

    public var id = UUID()
    public var kind: Kind
    /// Bounding box in image pixel coordinates (top-left origin).
    public var rect: CGRect
    public var color: NSColor = .systemRed
    public var strokeWidth: CGFloat = 4
    public var fontSize: CGFloat = 22
    public var text: String = ""
    /// For moving a pen stroke: offset all points.
    public var penPoints: [CGPoint] {
        get {
            if case .pen(let pts) = kind { return pts }
            return []
        }
        set {
            kind = .pen(newValue)
        }
    }

    public static func == (lhs: Annotation, rhs: Annotation) -> Bool {
        lhs.id == rhs.id && lhs.rect == rhs.rect && lhs.text == rhs.text
    }

    /// Hit test in image coordinates with slop.
    public func contains(point: CGPoint) -> Bool {
        rect.insetBy(dx: -8, dy: -8).contains(point)
    }

    public func moved(by dx: CGFloat, dy: CGFloat) -> Annotation {
        var copy = self
        copy.rect = rect.offsetBy(dx: dx, dy: dy)
        if case .pen(let pts) = kind {
            copy.kind = .pen(pts.map { CGPoint(x: $0.x + dx, y: $0.y + dy) })
        }
        return copy
    }
}

// MARK: - Model

/// Editor state. All coordinates are image pixels with top-left origin;
/// the canvas view converts to view coordinates.
@Observable
public final class EditorModel {
    public enum Tool: String, CaseIterable, Identifiable {
        case select = "选择"
        case rectangle = "矩形"
        case ellipse = "椭圆"
        case arrow = "箭头"
        case pen = "画笔"
        case text = "文字"
        case highlight = "高亮"
        case mosaic = "马赛克"
        case crop = "裁剪"

        public var id: String { rawValue }

        public var symbolName: String {
            switch self {
            case .select: return "arrow.up.left.and.arrow.down.right"
            case .rectangle: return "rectangle"
            case .ellipse: return "circle"
            case .arrow: return "arrow.up.right"
            case .pen: return "scribble"
            case .text: return "textformat"
            case .highlight: return "highlighter"
            case .mosaic: return "checkerboard.rectangle"
            case .crop: return "crop"
            }
        }
    }

    public private(set) var baseImage: CGImage
    public private(set) var annotations: [Annotation] = []
    public var selectedAnnotationID: UUID?

    /// Mutates an annotation in place (used by the toolbar color action).
    public func updateAnnotation(at index: Int, _ mutate: (inout Annotation) -> Void) {
        guard annotations.indices.contains(index) else { return }
        mutate(&annotations[index])
        invalidate()
    }

    public var tool: Tool = .rectangle
    public var strokeColor: NSColor = .systemRed
    public var strokeWidth: CGFloat = 4
    public var fontSize: CGFloat = 22

    /// In-progress annotation while dragging; drawn but not committed.
    public var draft: Annotation?
    /// Live crop selection in image coords while the crop tool is active.
    public var cropRect: CGRect?
    /// Index of the annotation whose text is being edited (overlay field).
    public var editingTextID: UUID?
    public var editingDraftText = ""

    public enum ExportKind {
        case copy
        case save
        case done
    }

    public var onDirty: (() -> Void)?
    public var onClose: (() -> Void)?
    public var exportAction: ((ExportKind) -> Void)?
    public var ocrRequest: (() -> Void)?

    /// Bumped on every visual change; invalidates the preview cache.
    public private(set) var renderVersion = 0
    var previewCache: (version: Int, maxDimension: CGFloat, image: NSImage)?

    @ObservationIgnored
    let dragState = EditorDragState()

    public func invalidate() {
        renderVersion += 1
    }

    private struct Snapshot {
        let image: CGImage
        let annotations: [Annotation]
    }

    private var undoStack: [Snapshot] = []
    private var redoStack: [Snapshot] = []

    public init(image: CGImage) {
        baseImage = image
    }

    public var imageSize: CGSize {
        CGSize(width: baseImage.width, height: baseImage.height)
    }

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }
    public var hasUnsavedChanges: Bool { !undoStack.isEmpty }

    // MARK: - History

    private func pushSnapshot() {
        undoStack.append(Snapshot(image: baseImage, annotations: annotations))
        if undoStack.count > 60 { undoStack.removeFirst() }
        redoStack.removeAll()
    }

    public func undo() {
        commitTextEditingIfNeeded()
        guard let snap = undoStack.popLast() else { return }
        redoStack.append(Snapshot(image: baseImage, annotations: annotations))
        baseImage = snap.image
        annotations = snap.annotations
        selectedAnnotationID = nil
        mosaicCache.removeAll()
        invalidate()
        onDirty?()
    }

    public func redo() {
        guard let snap = redoStack.popLast() else { return }
        undoStack.append(Snapshot(image: baseImage, annotations: annotations))
        baseImage = snap.image
        annotations = snap.annotations
        selectedAnnotationID = nil
        mosaicCache.removeAll()
        invalidate()
        onDirty?()
    }

    // MARK: - Tool actions

    public func beginDraft(at imagePoint: CGPoint) {
        switch tool {
        case .select:
            selectedAnnotationID = annotations.last(where: { $0.contains(point: imagePoint) })?.id
        case .rectangle, .ellipse, .highlight, .mosaic:
            draft = Annotation(
                kind: toolKind,
                rect: CGRect(origin: imagePoint, size: .zero),
                color: strokeColor,
                strokeWidth: strokeWidth
            )
        case .arrow:
            draft = Annotation(
                kind: .arrow,
                rect: CGRect(origin: imagePoint, size: .zero),
                color: strokeColor,
                strokeWidth: strokeWidth
            )
        case .pen:
            draft = Annotation(
                kind: .pen([imagePoint]),
                rect: CGRect(origin: imagePoint, size: .zero),
                color: strokeColor,
                strokeWidth: strokeWidth
            )
        case .text:
            placeText(at: imagePoint)
        case .crop:
            cropRect = CGRect(origin: imagePoint, size: .zero)
        }
    }

    private var toolKind: Annotation.Kind {
        switch tool {
        case .rectangle: return .rectangle
        case .ellipse: return .ellipse
        case .highlight: return .highlight
        case .mosaic: return .mosaic
        default: return .rectangle
        }
    }

    public func updateDraft(to imagePoint: CGPoint) {
        invalidate()
        if var d = draft {
            switch d.kind {
            case .pen(var pts):
                pts.append(imagePoint)
                d.kind = .pen(pts)
                d.rect = Self.boundingRect(of: pts).union(d.rect)
            default:
                d.rect = Self.rect(from: d.rect.origin, to: imagePoint)
            }
            draft = d
        } else if cropRect != nil {
            cropRect = Self.rect(from: cropRect?.origin ?? imagePoint, to: imagePoint)
        }
    }

    public func endDraft() {
        if var d = draft {
            draft = nil
            if d.rect.width >= 4, d.rect.height >= 4 {
                d.rect = d.rect.integral
                pushSnapshot()
                annotations.append(d)
            }
        }
    }

    /// Dragging an existing annotation with the select tool.
    public func moveSelected(by delta: CGSize) {
        guard
            let id = selectedAnnotationID,
            let idx = annotations.firstIndex(where: { $0.id == id })
        else { return }
        annotations[idx] = annotations[idx].moved(by: delta.width, dy: delta.height)
    }

    public func deleteSelected() {
        guard let id = selectedAnnotationID else { return }
        pushSnapshot()
        annotations.removeAll { $0.id == id }
        selectedAnnotationID = nil
        invalidate()
    }

    public func applyCrop() {
        guard let crop = cropRect, crop.width >= 8, crop.height >= 8 else {
            cropRect = nil
            return
        }
        let integral = crop.integral.intersection(
            CGRect(origin: .zero, size: imageSize)
        )
        guard integral.width >= 8, integral.height >= 8,
              let cropped = baseImage.cropping(to: integral)
        else { return }
        pushSnapshot()
        baseImage = cropped
        // Shift annotations into cropped coordinates.
        annotations = annotations.map { a in
            var copy = a
            copy.rect = a.rect.offsetBy(dx: -integral.minX, dy: -integral.minY)
            if case .pen(let pts) = a.kind {
                copy.kind = .pen(pts.map {
                    CGPoint(x: $0.x - integral.minX, y: $0.y - integral.minY)
                })
            }
            return copy
        }
        cropRect = nil
        mosaicCache.removeAll()
        invalidate()
        onDirty?()
    }

    // MARK: - Text editing

    public func placeText(at point: CGPoint) {
        let a = Annotation(
            kind: .text,
            rect: CGRect(origin: point, size: CGSize(width: 200, height: fontSize * 1.4)),
            color: strokeColor,
            fontSize: fontSize
        )
        pushSnapshot()
        annotations.append(a)
        editingTextID = a.id
        editingDraftText = ""
        invalidate()
    }

    public func commitTextEditingIfNeeded() {
        guard let id = editingTextID,
              let idx = annotations.firstIndex(where: { $0.id == id })
        else {
            editingTextID = nil
            return
        }
        let text = editingDraftText.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            // Empty text: drop the annotation (and its snapshot entry).
            if !undoStack.isEmpty { undoStack.removeLast() }
            annotations.remove(at: idx)
        } else {
            annotations[idx].text = text
        }
        editingTextID = nil
        editingDraftText = ""
        invalidate()
    }

    // MARK: - Keyboard

    public func handleKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let cmd = flags.contains(.command)
        switch event.keyCode {
        case 6 where cmd && !flags.contains(.shift): // z
            undo()
            return true
        case 6 where cmd && flags.contains(.shift): // ⇧⌘Z
            redo()
            return true
        case 51 where selectedAnnotationID != nil: // backspace
            deleteSelected()
            return true
        case 36, 76 where cropRect != nil: // ⏎ applies a pending crop
            applyCrop()
            return true
        case 53: // esc
            if editingTextID != nil {
                editingDraftText = ""
                commitTextEditingIfNeeded()
            } else if cropRect != nil {
                cropRect = nil
            } else {
                onClose?()
            }
            return true
        default:
            return false
        }
    }

    // MARK: - Mosaic

    /// Pixelated tiles per mosaic annotation, keyed by id; regenerated when
    /// the base image changes.
    var mosaicCache: [UUID: CGImage] = [:]

    public func mosaicTile(for annotation: Annotation) -> CGImage? {
        if let cached = mosaicCache[annotation.id] { return cached }
        guard let tile = Self.pixelate(image: baseImage, region: annotation.rect, blockSize: 14) else {
            return nil
        }
        mosaicCache[annotation.id] = tile
        return tile
    }

    public static func pixelate(image: CGImage, region: CGRect, blockSize: CGFloat) -> CGImage? {
        let clamp = region.integral.intersection(CGRect(origin: .zero, size: CGSize(width: image.width, height: image.height)))
        guard clamp.width > 4, clamp.height > 4,
              let crop = image.cropping(to: clamp)
        else { return nil }
        let smallW = max(1, Int(clamp.width / blockSize))
        let smallH = max(1, Int(clamp.height / blockSize))
        guard let smallCtx = CGContext(
            data: nil, width: smallW, height: smallH,
            bitsPerComponent: 8, bytesPerRow: smallW * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        smallCtx.interpolationQuality = .none
        smallCtx.draw(crop, in: CGRect(x: 0, y: 0, width: smallW, height: smallH))
        guard let small = smallCtx.makeImage() else { return nil }
        guard let bigCtx = CGContext(
            data: nil, width: Int(clamp.width), height: Int(clamp.height),
            bitsPerComponent: 8, bytesPerRow: Int(clamp.width) * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        bigCtx.interpolationQuality = .none
        bigCtx.draw(small, in: CGRect(x: 0, y: 0, width: clamp.width, height: clamp.height))
        return bigCtx.makeImage()
    }

    // MARK: - Export

    /// Flattens base + annotations into a single CGImage at image resolution.
    public func composite() -> CGImage? {
        let w = baseImage.width
        let h = baseImage.height
        guard let ctx = CGContext(
            data: nil, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        // Image coords are top-left origin; CG is bottom-left — flip.
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(baseImage, in: CGRect(x: 0, y: 0, width: w, height: h))

        var tiles: [UUID: CGImage] = [:]
        for a in annotations where a.kind == .mosaic {
            tiles[a.id] = mosaicTile(for: a)
        }
        AnnotationRenderer.drawAll(annotations, in: ctx, mosaicTiles: tiles)
        return ctx.makeImage()
    }

    // MARK: - Geometry helpers

    static func rect(from a: CGPoint, to b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
    }

    static func boundingRect(of points: [CGPoint]) -> CGRect {
        guard let first = points.first else { return .zero }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for p in points {
            minX = min(minX, p.x); maxX = max(maxX, p.x)
            minY = min(minY, p.y); maxY = max(maxY, p.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
