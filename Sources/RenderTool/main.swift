import AppKit
import SwiftUI
import ClipIslandCore

// Glass has no backdrop to sample offscreen — force the vibrancy fallback so
// the snapshots verify layout/typography (real glass is verified on-screen).
setenv("CLIPISLAND_NO_GLASS", "1", 1)

/// Offscreen UI renderer: instantiates the island's real SwiftUI surfaces in
/// on-screen windows and snapshots them via cacheDisplay (no screen-recording
/// permission needed — it's our own window content). Output: /tmp/ci-render.
final class RendererDelegate: NSObject, NSApplicationDelegate {
    var scenes: [(name: String, view: NSView)] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildScenes()
        renderSequentially()
    }

    private func buildScenes() {
        // Sample data: one image + texts, like a lived-in history.
        let png = NSImage(size: NSSize(width: 320, height: 200))
        png.lockFocus()
        NSColor.systemBlue.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: png.size)).fill()
        NSColor.white.setFill()
        NSBezierPath(ovalIn: NSRect(x: 90, y: 30, width: 140, height: 140)).fill()
        png.unlockFocus()
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("render-sample.png")
        if let tiff = png.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: tmp)
        }

        let now = Date()
        let items = [
            ClipItem(id: 1, kind: .text, text: "把 docs/COMPARISON.md 里的 P0 清单过一遍，窗口捕获先做", sourceName: "ZCode", createdAt: now.addingTimeInterval(-95)),
            ClipItem(id: 2, kind: .link, text: "https://github.com/ZiyueZhang/ClipIsland/releases/tag/v1.2.0", sourceName: "Safari", createdAt: now.addingTimeInterval(-600)),
            ClipItem(id: 3, kind: .image, text: nil, imagePath: tmp.path, imageSize: CGSize(width: 320, height: 200), sourceName: "ClipIsland 截图", createdAt: now.addingTimeInterval(-1800)),
            ClipItem(id: 4, kind: .text, text: "4231 8890 2233 0912", sourceName: "Numbers", createdAt: now.addingTimeInterval(-3600), pinned: true),
        ]
        let info = NotchDisplayInfo(
            hasRealNotch: true, headerHeight: 38, panelWidth: 480,
            notchWidth: 216, stripExtensionLeft: 150, stripExtensionRight: 110
        )

        func model(_ results: [ClipItem], locked: Bool = false, pending: Int = 0) -> NotchModel {
            let m = NotchModel()
            m.expand(animated: false)
            m.clipCount = results.count + 17
            m.vaultLocked = locked
            m.vaultPendingCount = pending
            m.vaultTouchIDEnabled = true
            m.vaultTouchIDAvailable = true
            m.applyResults(results)
            return m
        }

        let empty = NotchModel(); empty.expand(animated: false); empty.clipCount = 0; empty.applyResults([])
        let live = model(items)
        let locked = model([], locked: true, pending: 2)

        // Expanded panel: lived-in / empty / locked
        scenes.append(("panel-lived-dark", hosting(ExpandedPanel(model: live, info: info).frame(width: 480, height: 440), dark: true)))
        scenes.append(("panel-lived-light", hosting(ExpandedPanel(model: live, info: info).frame(width: 480, height: 440), dark: false)))
        scenes.append(("panel-empty-dark", hosting(ExpandedPanel(model: empty, info: info).frame(width: 480, height: 440), dark: true)))
        scenes.append(("panel-locked-dark", hosting(ExpandedPanel(model: locked, info: info).frame(width: 480, height: 440), dark: true)))

        // Collapsed strip at true notch size — plus the extended design.
        let stripModel = model(items)
        stripModel.collapse(animated: false)
        scenes.append(("strip-extended", hosting(CollapsedStrip(model: stripModel, info: info).frame(width: 476, height: 38), dark: true)))

        // Post-capture bar
        let pm = PostCaptureModel()
        pm.thumbnail = NSImage(contentsOfFile: tmp.path)
        pm.canReveal = true
        scenes.append(("popup-bar-dark", hosting(PostCaptureContentView(model: pm, onHoverChange: { _ in }).frame(width: 250, height: 168), dark: true)))
    }

    private func hosting(_ view: some View, dark: Bool) -> NSHostingView<some View> {
        let host = NSHostingView(rootView: view)
        host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        return host
    }

    private func renderSequentially() {
        try? FileManager.default.createDirectory(atPath: "/tmp/ci-render", withIntermediateDirectories: true)
        render(at: 0)
    }

    private func render(at index: Int) {
        guard index < scenes.count else {
            log("render done: \(scenes.count) scenes -> /tmp/ci-render")
            exit(0)
        }
        let scene = scenes[index]
        let window = NSWindow(
            contentRect: NSRect(origin: NSPoint(x: 40, y: 40), size: scene.view.bounds.size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.contentView = scene.view
        window.orderFrontRegardless()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            guard let rep = scene.view.bitmapImageRepForCachingDisplay(in: scene.view.bounds) else {
                print("no rep for \(scene.name)")
                self.render(at: index + 1)
                return
            }
            scene.view.cacheDisplay(in: scene.view.bounds, to: rep)
            if let png = rep.representation(using: .png, properties: [:]) {
                let url = URL(fileURLWithPath: "/tmp/ci-render/\(scene.name).png")
                try? png.write(to: url)
                print("rendered \(url.path) (\(Int(scene.view.bounds.width))x\(Int(scene.view.bounds.height)))")
            }
            window.orderOut(nil)
            self.render(at: index + 1)
        }
    }
}

let app = NSApplication.shared
let delegate = RendererDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
