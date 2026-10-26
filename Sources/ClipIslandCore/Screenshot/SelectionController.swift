import AppKit

/// Full-screen selection overlays showing frozen screens. Drag to pick a
/// region, Esc cancels, Return captures the whole screen under the mouse,
/// ⌘C copies the color under the cursor.
final class SelectionController {
    struct Completion {
        enum Result {
            case region(CGImage)
            case fullscreen(CGImage)
            case cancelled
        }
        let result: Result
        let hoveredColor: NSColor? // when ⌘C was used instead of a region
    }

    /// Internal, pre-crop outcome (selections are screen-coordinate rects).
    private enum Pending {
        case region(CGRect)
        case fullscreen(CGRect)
        case cancelled
    }

    private var windows: [SelectionWindow] = []
    private let service = CaptureService.shared
    private var frozen: [CaptureService.FrozenScreen] = []
    private var completionHandler: ((Completion) -> Void)?
    private var pickedColor: NSColor?
    fileprivate weak var activeWindow: SelectionWindow?

    func begin(completion: @escaping (Completion) -> Void) {
        guard windows.isEmpty else { return } // already selecting
        completionHandler = completion
        frozen = service.freezeAllScreens()
        guard !frozen.isEmpty else {
            completion(Completion(result: .cancelled, hoveredColor: nil))
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        for target in frozen {
            let window = SelectionWindow(
                frame: target.frameInScreen,
                frozen: target,
                controller: self
            )
            windows.append(window)
            window.makeKeyAndOrderFront(nil)
        }
        windows.first?.makeKeyAndOrderFront(nil)
    }

    func end() {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        frozen = []
    }

    // MARK: - Called by SelectionWindow/View

    fileprivate func selectionDragged(in window: SelectionWindow, rect: CGRect?) {
        // Mirror the in-progress selection on the other screens' overlays.
        for other in windows where other !== window {
            other.showGhost(selection: rect, in: window)
        }
    }

    fileprivate func finished(on window: SelectionWindow, rect: CGRect) {
        let global = CGRect(
            x: window.frame.origin.x + rect.minX,
            y: window.frame.origin.y + rect.minY,
            width: rect.width,
            height: rect.height
        )
        finish(.region(global))
    }

    fileprivate func fullscreenRequested(on window: SelectionWindow) {
        let target = activeWindow ?? window
        finish(.fullscreen(target.frame))
    }

    fileprivate func cancelled() {
        finish(.cancelled)
    }

    fileprivate func color(at point: NSPoint) -> NSColor? {
        service.color(at: point, in: frozen)
    }

    fileprivate func copyColor(_ color: NSColor) {
        pickedColor = color
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(color.hexString, forType: .string)
        log("color copied: \(color.hexString)")
    }

    private func finish(_ pending: Pending) {
        let handler = completionHandler
        completionHandler = nil
        end()

        let outcome: Completion.Result
        switch pending {
        case .region(let global):
            outcome = service.crop(selection: global, from: frozen)
                .map { .region($0) } ?? .cancelled
        case .fullscreen(let frame):
            outcome = service.crop(selection: frame, from: frozen)
                .map { .fullscreen($0) } ?? .cancelled
        case .cancelled:
            outcome = .cancelled
        }
        frozen = []
        handler?(Completion(result: outcome, hoveredColor: pickedColor))
    }
}

// MARK: - Window

final class SelectionWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    fileprivate let view: SelectionView

    init(frame: CGRect, frozen: CaptureService.FrozenScreen, controller: SelectionController) {
        view = SelectionView(frozen: frozen, controller: controller)
        super.init(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        level = .screenSaver
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        acceptsMouseMovedEvents = true
        ignoresMouseEvents = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        contentView = view
    }

    override func keyDown(with event: NSEvent) {
        view.handleKey(event)
    }

    fileprivate func showGhost(selection: CGRect?, in source: SelectionWindow) {
        view.showGhost(selection: selection, sourceFrame: source.frame)
    }
}

// MARK: - Selection view

final class SelectionView: NSView {
    private let frozen: CaptureService.FrozenScreen
    private weak var controller: SelectionController?

    private var dragStart: NSPoint?
    private var dragCurrent: NSPoint?
    private var hoverPoint: NSPoint?
    private var ghostRect: CGRect?

    override var acceptsFirstResponder: Bool { true }
    override var isOpaque: Bool { false }

    init(frozen: CaptureService.FrozenScreen, controller: SelectionController) {
        self.frozen = frozen
        self.controller = controller
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    func handleKey(_ event: NSEvent) {
        switch event.keyCode {
        case 53: // Esc
            controller?.cancelled()
        case 36, 76: // Return / keypad enter
            controller?.fullscreenRequested(on: window as! SelectionWindow)
        case 8 where event.modifierFlags.contains(.command): // ⌘C
            if let point = hoverPoint, let color = controller?.color(at: global(point)) {
                controller?.copyColor(color)
            }
        default:
            break
        }
    }

    private func global(_ local: NSPoint) -> NSPoint {
        guard let windowFrame = window?.frame.origin else { return local }
        return NSPoint(x: windowFrame.x + local.x, y: windowFrame.y + local.y)
    }

    func showGhost(selection: CGRect?, sourceFrame: CGRect) {
        guard let selection, let myOrigin = window?.frame.origin else {
            ghostRect = nil
            needsDisplay = true
            return
        }
        // selection is local to the source window; convert into our coords.
        ghostRect = selection.offsetBy(
            dx: sourceFrame.minX - myOrigin.x,
            dy: sourceFrame.minY - myOrigin.y
        )
        needsDisplay = true
    }

    // MARK: Events

    override func mouseDown(with event: NSEvent) {
        dragStart = convert(event.locationInWindow, from: nil)
        dragCurrent = dragStart
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        dragCurrent = convert(event.locationInWindow, from: nil)
        hoverPoint = dragCurrent
        if let selectionWindow = window as? SelectionWindow {
            controller?.activeWindow = selectionWindow
            controller?.selectionDragged(in: selectionWindow, rect: selectionRect())
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let start = dragStart else { return }
        let end = convert(event.locationInWindow, from: nil)
        dragStart = nil
        dragCurrent = nil
        let rect = CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
                          width: abs(end.x - start.x), height: abs(end.y - start.y))
        // Treat a click as a cancel (too small to be a region).
        if rect.width >= 8, rect.height >= 8 {
            controller?.finished(on: window as! SelectionWindow, rect: rect)
        } else {
            controller?.cancelled()
        }
    }

    override func mouseMoved(with event: NSEvent) {
        hoverPoint = convert(event.locationInWindow, from: nil)
        if let selectionWindow = window as? SelectionWindow {
            controller?.activeWindow = selectionWindow
        }
        needsDisplay = true
    }

    private func selectionRect() -> CGRect? {
        guard let start = dragStart, let current = dragCurrent else { return nil }
        return CGRect(
            x: min(start.x, current.x), y: min(start.y, current.y),
            width: abs(current.x - start.x), height: abs(current.y - start.y)
        )
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        // Frozen screen
        ctx.saveGState()
        ctx.translateBy(x: 0, y: bounds.height)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(frozen.image, in: bounds)
        ctx.restoreGState()

        let active = selectionRect() ?? ghostRect
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.32).cgColor)

        if let sel = active {
            // Dim everything except the selection: fill four side rects.
            for side in [
                CGRect(x: 0, y: 0, width: bounds.width, height: sel.minY),
                CGRect(x: 0, y: sel.maxY, width: bounds.width, height: bounds.height - sel.maxY),
                CGRect(x: 0, y: sel.minY, width: sel.minX, height: sel.height),
                CGRect(x: sel.maxX, y: sel.minY, width: bounds.width - sel.maxX, height: sel.height),
            ] {
                ctx.fill(side)
            }
            drawSelectionBorder(ctx, sel)
            drawInfoLabels(ctx, sel: sel, isLive: selectionRect() != nil)
        } else {
            ctx.fill(bounds)
            // Crosshair through the cursor.
            if let hover = hoverPoint {
                ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.7).cgColor)
                ctx.setLineWidth(1)
                ctx.move(to: CGPoint(x: hover.x, y: 0))
                ctx.addLine(to: CGPoint(x: hover.x, y: bounds.height))
                ctx.move(to: CGPoint(x: 0, y: hover.y))
                ctx.addLine(to: CGPoint(x: bounds.width, y: hover.y))
                ctx.strokePath()
            }
            if let hover = hoverPoint {
                drawColorChip(ctx, at: hover)
            }
        }
    }

    private func drawSelectionBorder(_ ctx: CGContext, _ rect: CGRect) {
        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.setLineWidth(1.5)
        ctx.stroke(rect)
        // Corner handles
        let len: CGFloat = 14
        ctx.setLineWidth(3)
        for corner in [
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.minX, y: rect.maxY),
            CGPoint(x: rect.maxX, y: rect.maxY),
        ] {
            ctx.move(to: corner)
            ctx.addLine(to: CGPoint(x: corner.x + (corner.x == rect.minX ? len : -len), y: corner.y))
            ctx.move(to: corner)
            ctx.addLine(to: CGPoint(x: corner.x, y: corner.y + (corner.y == rect.minY ? len : -len)))
        }
        ctx.strokePath()
    }

    private func drawInfoLabels(_ ctx: CGContext, sel: CGRect, isLive: Bool) {
        let size = "\(Int(sel.width)) × \(Int(sel.height))"
        drawLabel(ctx, text: size, at: CGPoint(x: sel.midX, y: sel.minY - 26), center: true)
    }

    private func drawColorChip(_ ctx: CGContext, at point: NSPoint) {
        guard let controller else { return }
        let globalPoint = global(point)
        guard let color = controller.color(at: globalPoint) else { return }
        let text = color.hexString
        // Swatch + hex to the bottom-right of the cursor.
        let chip = CGRect(x: point.x + 14, y: point.y - 36, width: 14, height: 14)
        ctx.setFillColor(color.cgColor)
        ctx.fill(chip)
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.8).cgColor)
        ctx.setLineWidth(1)
        ctx.stroke(chip)
        drawLabel(
            ctx,
            text: text,
            at: CGPoint(x: chip.maxX + 4, y: chip.minY - 1),
            center: false
        )
    }

    private func drawLabel(_ ctx: CGContext, text: String, at point: CGPoint, center: Bool) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let attributed = NSAttributedString(string: text, attributes: attributes)
        let size = attributed.size()
        let origin = center
            ? CGPoint(x: point.x - size.width / 2, y: point.y)
            : CGPoint(x: point.x, y: point.y)
        let box = CGRect(origin: origin, size: size).insetBy(dx: -6, dy: -3)
        let path = CGPath(
            roundedRect: box, cornerWidth: 6, cornerHeight: 6, transform: nil
        )
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.75).cgColor)
        ctx.addPath(path)
        ctx.fillPath()
        attributed.draw(at: CGPoint(x: box.minX + 6, y: box.minY + 3))
    }
}
