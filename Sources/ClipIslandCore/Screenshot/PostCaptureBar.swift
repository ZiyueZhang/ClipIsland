import AppKit
import Observation
import SwiftUI

/// Small quick-action bar that appears bottom-left after a capture:
/// Copy / Edit / Reveal, auto-dismisses, hover pauses the countdown.
/// (shotx-style popup-first flow; the editor becomes an explicit choice.)
@Observable
final class PostCaptureModel {
    var thumbnail: NSImage?
    var canReveal = false
    var onCopy: () -> Void = {}
    var onEdit: () -> Void = {}
    var onReveal: () -> Void = {}
}

public final class PostCaptureBar {
    static let lifetime: TimeInterval = 6

    private let model = PostCaptureModel()
    private var panel: NSPanel?
    private var dismissTask: DispatchWorkItem?
    private var isHovering = false
    private var closed = true

    public init() {}

    public func show(
        thumbnail: NSImage,
        onCopy: @escaping () -> Void,
        onEdit: @escaping () -> Void,
        onReveal: (() -> Void)?
    ) {
        model.thumbnail = thumbnail
        model.onCopy = { onCopy(); self.hide() }
        model.onEdit = { onEdit(); self.hide() }
        model.canReveal = onReveal != nil
        model.onReveal = { onReveal?(); self.hide() }

        closed = false
        if panel == nil {
            buildPanel()
        }
        positionAndShow()
        scheduleDismiss()
    }

    public func hide() {
        closed = true
        dismissTask?.cancel()
        panel?.orderOut(nil)
    }

    // MARK: - Internals

    private func buildPanel() {
        let frame = NSRect(x: 0, y: 0, width: 250, height: 168)
        let p = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.level = .floating
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.isMovableByWindowBackground = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        p.contentView = NSHostingView(
            rootView: PostCaptureContentView(model: model,
                                             onHoverChange: { [weak self] hovering in
                                                 self?.isHovering = hovering
                                                 if hovering {
                                                     self?.dismissTask?.cancel()
                                                 } else {
                                                     self?.scheduleDismiss()
                                                 }
                                             })
        )
        panel = p
    }

    private func positionAndShow() {
        guard let visible = NSScreen.main?.visibleFrame else { return }
        let size = CGSize(width: 250, height: 168)
        panel?.setFrame(
            CGRect(
                x: visible.minX + 20,
                y: visible.minY + 20,
                width: size.width,
                height: size.height
            ),
            display: true
        )
        panel?.orderFrontRegardless()
    }

    private func scheduleDismiss() {
        dismissTask?.cancel()
        guard !closed, !isHovering else { return }
        let task = DispatchWorkItem { [weak self] in
            self?.hide()
        }
        dismissTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.lifetime, execute: task)
    }
}

// MARK: - Content

struct PostCaptureContentView: View {
    let model: PostCaptureModel
    let onHoverChange: (Bool) -> Void

    var body: some View {
        VStack(spacing: 10) {
            if let image = model.thumbnail {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 226, maxHeight: 104)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(.white.opacity(0.15), lineWidth: 1)
                    )
            }
            HStack(spacing: 8) {
                action("复制", symbol: "doc.on.doc", primary: true, action: model.onCopy)
                action("编辑", symbol: "wand.and.stars", primary: false, action: model.onEdit)
                if model.canReveal {
                    action("显示", symbol: "folder", primary: false, action: model.onReveal)
                }
            }
        }
        .padding(12)
        .frame(width: 250, height: 168)
        .background(
            ZStack {
                VisualEffectView(material: .hudWindow)
                RoundedRectangle(cornerRadius: 14)
                    .stroke(.white.opacity(0.10), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 14))
        )
        .shadow(color: .black.opacity(0.32), radius: 18, y: 6)
        .onHover { onHoverChange($0) }
    }

    private func action(_ label: String, symbol: String, primary: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 10, weight: .medium))
                Text(label).font(.system(size: 11, weight: primary ? .semibold : .regular))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(primary ? Color.accentColor : Color.primary.opacity(0.10))
            )
            .foregroundStyle(primary ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }
}
