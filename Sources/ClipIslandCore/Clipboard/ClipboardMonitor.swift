import AppKit
import Foundation

/// Polls NSPasteboard.general and emits captured clips. Skips sensitive
/// content (password-manager markers per nspasteboard.org) and the app's own
/// pasteboard writes.
public final class ClipboardMonitor {
    /// Pasteboard types that mark concealed/transient content (password
    /// managers, token generators). See https://nspasteboard.org.
    public static let sensitiveTypes: Set<String> = [
        "org.nspasteboard.ConcealedType",
        "org.nspasteboard.TransientType",
        "de.petermaurer.TransientPasteboardType",
        "com.typeit4me.clipping",
        "com.agilebits.onepassword",
        "com.lastpass.LastPass",
        "ch.proton.proton-pass",
        "com.bitwarden.desktop.clipboard",
    ]

    public var onCapture: ((NewClip) -> Void)?
    public var paused: Bool = false

    private var timer: Timer?
    private let pasteboard = NSPasteboard.general
    private var lastChangeCount: Int

    public init() {
        lastChangeCount = pasteboard.changeCount
    }

    public func start(interval: TimeInterval = 0.35) {
        stop()
        paused = false
        lastChangeCount = pasteboard.changeCount
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.poll()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Call right after this app writes to the pasteboard (auto-paste / copy
    /// actions) so the monitor does not record its own writes.
    public func markOwnWrite() {
        lastChangeCount = pasteboard.changeCount
    }

    private func poll() {
        guard !paused else { return }
        let count = pasteboard.changeCount
        guard count != lastChangeCount else { return }
        lastChangeCount = count
        guard var clip = Self.capture(from: pasteboard) else { return }
        let front = NSWorkspace.shared.frontmostApplication
        clip.sourceBundle = front?.bundleIdentifier
        clip.sourceName = front?.localizedName
        onCapture?(clip)
    }

    /// Pure-ish extraction used by tests and the monitor. Returns nil for
    /// sensitive or empty content.
    public static func capture(from pb: NSPasteboard) -> NewClip? {
        if let types = pb.types, !types.isEmpty,
           types.contains(where: { sensitiveTypes.contains($0.rawValue) }) {
            return nil
        }

        // Images first: a screenshot or copied picture wins over its metadata strings.
        if let png = pb.data(forType: .png) {
            return NewClip(kind: .image, imageData: png)
        }
        if let tiff = pb.data(forType: .tiff),
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            return NewClip(kind: .image, imageData: png)
        }

        // File URLs.
        if let urls = pb.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true] as [NSPasteboard.ReadingOptionKey: Any]
        ) as? [URL], !urls.isEmpty {
            return NewClip(kind: .file, text: urls.map(\.path).joined(separator: "\n"))
        }

        // Plain string: classify as link or text.
        guard let string = pb.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !string.isEmpty else {
            return nil
        }
        if isLink(string) {
            return NewClip(kind: .link, text: string)
        }
        return NewClip(kind: .text, text: string)
    }

    public static func isLink(_ string: String) -> Bool {
        guard let url = URL(string: string),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host != nil else { return false }
        return true
    }
}
