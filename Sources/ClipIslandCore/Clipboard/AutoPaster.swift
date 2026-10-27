import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Foundation

/// Writes a chosen clip back to the pasteboard and (when allowed) synthesizes
/// ⌘V into the app that was frontmost before the panel expanded.
public final class AutoPaster {
    private let monitor: ClipboardMonitor
    private var lastApp: NSRunningApplication?
    /// Set by the coordinator so image reads go through the vault
    /// (decrypt-at-use instead of raw file reads).
    public var imageLoader: ((ClipItem) -> Data?)?

    public init(monitor: ClipboardMonitor) {
        self.monitor = monitor
    }

    /// Snapshot the frontmost app (before our panel takes keyboard focus) so
    /// auto-paste lands in the right place.
    public func noteFrontmost() {
        let front = NSWorkspace.shared.frontmostApplication
        guard let front, front.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
        lastApp = front
    }

    public static var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    public func paste(_ item: ClipItem) {
        writeToPasteboard(item)
        monitor.markOwnWrite()

        guard SettingsStore.shared.autoPasteEnabled else { return }
        guard Self.isAccessibilityTrusted else {
            log("auto-paste unavailable: accessibility not granted (copied only)")
            return
        }
        let target = lastApp
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) {
            if let target {
                target.activate(options: [.activateIgnoringOtherApps])
            } else {
                NSApp.activate(ignoringOtherApps: true)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
                Self.postCommandV()
            }
        }
    }

    static func postCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        guard
            let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
            let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
        else { return }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    public func writeToPasteboard(_ item: ClipItem) {
        let pb = NSPasteboard.general
        pb.clearContents()
        switch item.kind {
        case .text:
            pb.setString(item.text ?? "", forType: .string)
        case .link:
            var objects: [NSPasteboardWriting] = [NSString(string: item.text ?? "")]
            if let url = URL(string: item.text ?? "") {
                objects.append(url as NSURL)
            }
            pb.writeObjects(objects)
        case .file:
            let urls = (item.text ?? "")
                .split(separator: "\n")
                .map { URL(fileURLWithPath: String($0)) as NSURL }
            if !urls.isEmpty {
                pb.writeObjects(urls)
            }
        case .image:
            guard let data = imageLoader?(item) ?? item.imagePath.flatMap({ FileManager.default.contents(atPath: $0) }) else { return }
            Self.writeImageFlavors(pb, pngData: data)
        }
    }

    /// PNG + TIFF together: some apps (notably Electron-based) refuse plain
    /// TIFF-only or PNG-only image pasteboards.
    public static func writeImageFlavors(_ pb: NSPasteboard, pngData: Data) {
        pb.setData(pngData, forType: .png)
        if let rep = NSBitmapImageRep(data: pngData), let tiff = rep.tiffRepresentation {
            pb.setData(tiff, forType: .tiff)
        }
    }
}
