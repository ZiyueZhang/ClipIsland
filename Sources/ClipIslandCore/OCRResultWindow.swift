import AppKit
import SwiftUI

/// Shows OCR results with copy-to-history actions.
public final class OCRResultWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let model = OCRResultModel()
    private var closed = false

    public override init() {
        super.init()
    }

    public func show(text: String) {
        if window == nil {
            buildWindow()
        }
        model.text = text
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func buildWindow() {
        let frame = NSRect(x: 0, y: 0, width: 460, height: 420)
        let win = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.title = "识别的文字"
        win.isReleasedWhenClosed = false
        win.delegate = self
        win.contentView = NSHostingView(rootView: OCRResultView(model: model))
        if let visible = NSScreen.main?.visibleFrame {
            win.setFrameOrigin(NSPoint(
                x: visible.midX - frame.width / 2,
                y: visible.midY - frame.height / 2
            ))
        }
        window = win
    }

    public func windowWillClose(_ notification: Notification) {
        guard !closed else { return }
        closed = true
        onclose?()
    }

    public var onclose: (() -> Void)?
}

@Observable
final class OCRResultModel {
    var text = ""
}

private struct OCRResultView: View {
    let model: OCRResultModel

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                Text(model.text)
                    .font(.system(size: 13))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
            }
            Divider()
            HStack {
                Spacer()
                Button("复制到剪贴板") {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(model.text, forType: .string)
                    NSApp.keyWindow?.orderOut(nil)
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(10)
        }
        .frame(minWidth: 380, minHeight: 260)
    }
}
