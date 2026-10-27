import AppKit
import Quartz

/// Space-bar Quick Look for history items. Images/files preview straight
/// from disk; text and links materialize into a temp file so QL can render.
public final class QuickLookController: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    public static let shared = QuickLookController()

    private var urls: [URL] = []
    private var tempFiles: [URL] = []

    public func show(urls: [URL], index: Int) {
        guard !urls.isEmpty, let panel = QLPreviewPanel.shared() else { return }
        self.urls = urls
        if urls.indices.contains(index) {
            panel.currentPreviewItemIndex = index
        }
        panel.dataSource = self
        panel.delegate = self
        panel.makeKeyAndOrderFront(nil)
    }

    /// Convenience: preview a single clip item (decrypts to a temp file when
    /// the vault is on).
    public func show(item: ClipItem, decryptedText: String?, decryptedImageData: Data?) {
        switch item.kind {
        case .image:
            if let path = item.imagePath {
                show(urls: [URL(fileURLWithPath: path)], index: 0)
            }
        case .file:
            let paths = (item.text ?? "")
                .split(separator: "\n")
                .map { URL(fileURLWithPath: String($0)) }
                .filter { FileManager.default.fileExists(atPath: $0.path) }
            show(urls: paths, index: 0)
        case .text, .link:
            guard let text = decryptedText ?? item.text else { return }
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("clipisland-ql-\(UUID().uuidString).txt")
            do {
                try text.write(to: url, atomically: true, encoding: .utf8)
                tempFiles.append(url)
                show(urls: [url], index: 0)
            } catch {
                log("quick look temp file failed: \(error.localizedDescription)")
            }
        }
    }

    public func close() {
        if let panel = QLPreviewPanel.shared(), panel.isVisible {
            panel.orderOut(nil)
        }
        tempFiles.forEach { try? FileManager.default.removeItem(at: $0) }
        tempFiles.removeAll()
        urls.removeAll()
    }

    public func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { urls.count }

    public func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        urls.indices.contains(index) ? urls[index] as NSURL : nil
    }

    public func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        if event.type == .keyDown, event.keyCode == 53 { // Esc closes
            close()
            return true
        }
        return false
    }
}
