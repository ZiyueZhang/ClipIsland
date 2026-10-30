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
    private var lastChangeDate = Date()
    /// Poll cadence: snappy while the user is working, backed off when the
    /// pasteboard has been quiet, restored the moment anything changes.
    private var currentInterval: TimeInterval = 0.35

    public init() {
        lastChangeCount = pasteboard.changeCount
    }

    public func start(interval: TimeInterval = 0.35) {
        stop()
        paused = false
        lastChangeCount = pasteboard.changeCount
        lastChangeDate = Date()
        currentInterval = interval
        scheduleTimer()
    }

    private func scheduleTimer() {
        let timer = Timer(timeInterval: currentInterval, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.poll()
            self.scheduleTimer()
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
        guard count != lastChangeCount else {
            // Quiet pasteboard: back off to a low cadence.
            if -lastChangeDate.timeIntervalSinceNow > 120, currentInterval < 1 {
                currentInterval = 1.2
            }
            return
        }
        lastChangeCount = count
        lastChangeDate = Date()
        if currentInterval > 0.35 {
            currentInterval = 0.35
            timer?.invalidate()
            scheduleTimer()
        }
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

        // Plain string: classify as link or text; keep the rich flavors
        // (HTML/RTF) that browsers and rich editors attach alongside, so
        // paste-back preserves formatting.
        guard let raw = pb.string(forType: .string), !raw.isEmpty else {
            return nil
        }
        let string = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !string.isEmpty else { return nil }
        let html = pb.data(forType: NSPasteboard.PasteboardType("public.html"))
        let rtf = pb.data(forType: .rtf)
        if isLink(string) {
            return NewClip(kind: .link, text: string, htmlData: html, rtfData: rtf)
        }
        return NewClip(kind: .text, text: string, htmlData: html, rtfData: rtf)
    }

    /// Rich flavors above this size are dropped — a browser can attach
    /// megabytes of markup for one paragraph.
    public static let maxRichPayload = 512 * 1024

    public static func isLink(_ string: String) -> Bool {
        guard let url = URL(string: string),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host != nil else { return false }
        return true
    }
}
