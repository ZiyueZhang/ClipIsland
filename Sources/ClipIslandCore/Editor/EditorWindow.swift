import AppKit
import SwiftUI

/// Editor window: a regular titled window so it participates in normal
/// window management (unlike the notch island panel).
final class EditorWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    var keyHandler: ((NSEvent) -> Bool)?

    override func keyDown(with event: NSEvent) {
        if keyHandler?(event) == true { return }
        super.keyDown(with: event)
    }
}

public final class EditorWindowController: NSObject, NSWindowDelegate {
    public let model: EditorModel
    private var window: EditorWindow?

    /// Called when the user hits 复制/保存/完成 with the flattened image.
    /// `.done` also closes the window afterwards.
    public var onExport: ((CGImage, EditorModel.ExportKind) -> Void)?

    /// Called with the flattened image when the user requests OCR.
    public var onOCR: ((CGImage) -> Void)?

    public init(image: CGImage, title: String = "ClipIsland 编辑器") {
        self.model = EditorModel(image: image)
        super.init()

        let aspect = CGSize(width: image.width, height: image.height)
        let screenVisible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let maxW = min(screenVisible.width * 0.8, 1100)
        let maxH = min(screenVisible.height * 0.8, 780)
        var w = maxW
        var h = w * aspect.height / max(aspect.width, 1)
        if h > maxH {
            h = maxH
            w = h * aspect.width / max(aspect.height, 1)
        }
        w = max(w, 540)
        h = max(h, 420)

        let frame = NSRect(
            x: screenVisible.midX - w / 2,
            y: screenVisible.midY - h / 2,
            width: w,
            height: h
        )
        let win = EditorWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.title = title
        win.isReleasedWhenClosed = false
        win.delegate = self
        win.contentView = NSHostingView(rootView: EditorRootView(model: model))
        self.window = win

        model.onClose = { [weak self] in
            self?.close()
        }
        model.exportAction = { [weak self] kind in
            guard let self else { return }
            self.model.commitTextEditingIfNeeded()
            guard let composite = self.model.composite() else { return }
            self.onExport?(composite, kind)
            if kind == .done {
                self.close()
            }
        }
        model.ocrRequest = { [weak self] in
            guard let self else { return }
            self.model.commitTextEditingIfNeeded()
            if let composite = self.model.composite() {
                self.onOCR?(composite)
            }
        }
        win.keyHandler = { [weak self] event in
            self?.model.handleKey(event) ?? false
        }
    }

    public func show() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private var closed = false

    public func close() {
        guard !closed else { return }
        closed = true
        window?.orderOut(nil)
        onClose?()
    }

    /// Fired when the window is closed (button or programmatically).
    public var onClose: (() -> Void)?

    public func windowWillClose(_ notification: Notification) {
        close()
    }
}
