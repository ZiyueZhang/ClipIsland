import AppKit
import ImageIO

public final class AppDelegate: NSObject, NSApplicationDelegate {
    var appCoordinator: AppCoordinator?

    public func applicationDidFinishLaunching(_ notification: Notification) {
        log("ClipIsland launching")
        appCoordinator = AppCoordinator()
        appCoordinator!.start()
    }

    public func applicationWillTerminate(_ notification: Notification) {
        appCoordinator?.stop()
        log("ClipIsland terminated")
    }
}

/// Owns and wires every module of the app. Grows with the milestones.
public final class AppCoordinator: NSObject {
    private var statusItem: NSStatusItem?
    private let notchModel = NotchModel()
    private var notchWindow: NotchWindowController?

    private let settings = SettingsStore.shared
    private var store: ClipStore?
    private let monitor = ClipboardMonitor()
    private var paster: AutoPaster?
    private let hotkeys = HotkeyManager()
    private let selectionController = SelectionController()
    private var editors: [EditorWindowController] = []
    private var settingsWindow: SettingsWindowController?
    private var ocrWindow: OCRResultWindowController?
    private let hoverMonitor = MenuBarHoverMonitor()
    private let postCaptureBar = PostCaptureBar()
    private let vault = Vault.shared

    public override init() {
        super.init()
    }

    public func start() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        )[0].appendingPathComponent("ClipIsland", isDirectory: true)
        do {
            store = try ClipStore(directory: appSupport)
        } catch {
            log("store open failed: \(error)")
        }

        paster = AutoPaster(monitor: monitor)

        monitor.onCapture = { [weak self] clip in
            guard let self else { return }
            self.store?.add(clip)
            log("captured \(clip.kind.rawValue)")
        }
        monitor.start()

        notchModel.clipCount = store?.count ?? 0
        notchModel.setPaused(settings.paused)
        notchModel.expandOnHover = settings.expandOnHover
        store?.onDidChange = { [weak self] in
            guard let self else { return }
            self.notchModel.clipCount = self.store?.count ?? 0
            self.notchModel.reloadResults()
            self.refreshStatusMenu()
        }

        wirePanelActions()
        hotkeys.onPanelHotkey = { [weak self] in
            self?.notchModel.toggle()
        }
        hotkeys.onScreenshotHotkey = { [weak self] in
            self?.startScreenshot()
        }
        hotkeys.onWindowCaptureHotkey = { [weak self] in
            self?.startWindowScreenshot()
        }
        if ProcessInfo.processInfo.environment["CLIPISLAND_NO_HOTKEY"] != "1" {
            hotkeys.start(
                panelCombo: settings.panelHotkey,
                screenshotCombo: settings.screenshotHotkey,
                windowCombo: settings.windowCaptureHotkey
            )
        } else {
            log("hotkeys disabled via env")
        }

        notchWindow = NotchWindowController(model: notchModel)
        wireHoverMonitor()
        wireVault()
        wireSettingsWindow()
        buildStatusBarMenu()
        installTestHook()

        if !UserDefaults.standard.bool(forKey: "firstRunDone") {
            UserDefaults.standard.set(true, forKey: "firstRunDone")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                self?.openSettings()
            }
        }
    }

    /// The island can be summoned by resting the pointer anywhere in the
    /// menu bar (tendedero-style), not just on the 220pt notch itself.
    /// Vault state ↔ UI: lock screen in the panel, decryption routing for
    /// thumbnails/paste/drag/QL/editor, auto-lock on inactivity.
    private func wireVault() {
        syncVaultState()
        vault.onChange = { [weak self] in
            self?.syncVaultState()
            self?.notchModel.reloadResults()
            self?.refreshStatusMenu()
        }
        vault.onAutoLock = { [weak self] in
            self?.notchModel.collapse()
        }

        paster?.imageLoader = { [weak self] item in
            self?.store?.decryptedImageData(for: item)
        }
        ThumbnailCache.storeLoader = { [weak self] item in
            self?.store?.downsampledThumbnail(for: item, maxPixel: ThumbnailCache.maxPixel)
        }
        notchModel.dragProvider = { [weak self] item -> NSItemProvider? in
            guard let self, item.kind == .image, let data = self.store?.decryptedImageData(for: item) else {
                return nil
            }
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("clipisland-drag-\(item.id).png")
            do {
                try data.write(to: url, options: .atomic)
                return NSItemProvider(object: url as NSURL)
            } catch {
                log("drag decrypt failed: \(error.localizedDescription)")
                return nil
            }
        }
        notchModel.onVaultUnlockPassword = { [weak self] password in
            guard let self else { return }
            do {
                try vault.unlock(password: password)
                store?.flushPendingCaptures()
                notchModel.vaultUnlockError = nil
            } catch VaultError.wrongPassword {
                notchModel.vaultUnlockError = "密码错误"
            } catch {
                notchModel.vaultUnlockError = "\(error)"
            }
        }
        notchModel.onVaultUnlockTouchID = { [weak self] in
            guard let self else { return }
            do {
                try vault.unlockTouchID()
                store?.flushPendingCaptures()
                notchModel.vaultUnlockError = nil
            } catch {
                notchModel.vaultUnlockError = "触控 ID 失败：\(error)"
            }
        }
    }

    private func syncVaultState() {
        notchModel.vaultLocked = vault.isEnabled && !vault.isUnlocked
        notchModel.vaultTouchIDEnabled = vault.metadata?.touchIDEnabled ?? false
        notchModel.vaultTouchIDAvailable = Vault.isTouchIDAvailable
        notchModel.vaultPendingCount = store?.pendingCaptureCount ?? 0
        if notchModel.vaultLocked { notchModel.expandOnHoverGateForLock() }
    }

    private func wireHoverMonitor() {
        hoverMonitor.onDwell = { [weak self] in
            guard let self else { return }
            self.notchModel.expand()
        }
        hoverMonitor.start(
            shouldRun: { [weak self] in
                guard let self else { return false }
                return self.notchModel.phase == .collapsed
                    && self.notchModel.expandOnHover
                    && !self.notchModel.vaultLocked
            },
            zoneProvider: { [weak self] in self?.notchWindow?.dwellZone }
        )
    }

    private func wireSettingsWindow() {
        let controller = SettingsWindowController(settings: settings)
        controller.onChangeCapacity = { [weak self] capacity in
            self?.store?.capacity = capacity
        }
        controller.onChangeVaultEnabled = { [weak self] enabled in
            guard let self else { return }
            self.store?.migrateAll(enabled: enabled)
            self.syncVaultState()
            self.notchModel.reloadResults()
            self.refreshStatusMenu()
        }
        controller.onChangeVaultUnlocked = { [weak self] in
            guard let self else { return }
            self.store?.flushPendingCaptures()
            self.syncVaultState()
            self.notchModel.reloadResults()
        }
        controller.onChangeHotkeys = { [weak self] in
            guard let self else { return }
            self.hotkeys.reregister(
                panelCombo: self.settings.panelHotkey,
                screenshotCombo: self.settings.screenshotHotkey,
                windowCombo: self.settings.windowCaptureHotkey
            )
        }
        controller.onclose = { [weak self, weak controller] in
            guard let self, let controller else { return }
            if self.settingsWindow === controller {
                self.settingsWindow = nil
            }
        }
        settingsWindow = controller
    }

    @objc private func openSettings() {
        settingsWindow?.show()
    }

    private func startScreenshot() {
        guard CaptureService.requestScreenCapturePermission() else {
            log("screen capture denied; opening System Settings")
            NSWorkspace.shared.open(
                URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
            )
            return
        }

        notchModel.collapse(animated: false)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.beginSelection()
        }
    }

    private func beginSelection() {
        notchWindow?.setIsland(hidden: true)
        selectionController.begin { [weak self] completion in
            guard let self else { return }
            self.notchWindow?.setIsland(hidden: false)
            switch completion.result {
            case .region(let image), .fullscreen(let image):
                self.deliverScreenshot(image)
            case .cancelled:
                log("selection cancelled")
            }
        }
    }

    private func deliverScreenshot(_ image: CGImage) {
        guard let png = CaptureService.shared.pngData(from: image) else { return }

        let item = store?.add(
            NewClip(
                kind: .image, imageData: png,
                sourceBundle: Bundle.main.bundleIdentifier, sourceName: "ClipIsland 截图"
            )
        )

        // Hanging thumbnail at display size — never decodes the capture at
        // full resolution just to show a 64pt strip.
        if let thumb = Self.downsampledPNG(png, maxPixel: 480) {
            notchModel.flashHangingImage(thumb)
        }

        // Immediately pasteable (PNG + TIFF), without re-recording our own write.
        AutoPaster.writeImageFlavors(.general, pngData: png)
        monitor.markOwnWrite()

        let savedURL = settings.saveScreenshotsToFile
            ? CaptureService.shared.savePNG(image, to: URL(fileURLWithPath: settings.screenshotSaveDirectory))
            : nil

        if settings.openEditorAfterCapture {
            openEditor(image: image)
        } else {
            postCaptureBar.show(
                thumbnail: Self.downsampledPNG(png, maxPixel: 500) ?? NSImage(),
                onCopy: { [weak self] in
                    guard let self else { return }
                    AutoPaster.writeImageFlavors(.general, pngData: png)
                    self.monitor.markOwnWrite()
                },
                onEdit: { [weak self] in self?.openEditor(image: image) },
                onReveal: savedURL.map { url in
                    { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                },
                dragProvider: { [weak self] in
                    guard let self, let item, let data = self.store?.decryptedImageData(for: item) else {
                        return nil
                    }
                    let url = FileManager.default.temporaryDirectory
                        .appendingPathComponent("clipisland-capture.png")
                    do {
                        try data.write(to: url, options: .atomic)
                        return NSItemProvider(object: url as NSURL)
                    } catch { return nil }
                }
            )
        }
    }

    /// ImageIO thumbnail straight off the encoded data; never decodes the
    /// full-resolution bitmap.
    private static func downsampledPNG(_ data: Data, maxPixel: Int) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }

    // MARK: - Editor

    private static func loadImage(from item: ClipItem) -> CGImage? {
        guard
            let path = item.imagePath,
            let data = FileManager.default.contents(atPath: path),
            let provider = CGDataProvider(data: data as CFData)
        else { return nil }
        return CGImage(
            pngDataProviderSource: provider, decode: nil,
            shouldInterpolate: true, intent: .defaultIntent
        )
    }

    private func runOCR(image: CGImage) {
        OCRService.recognizeText(in: image) { [weak self] text in
            guard let self else { return }
            guard let text, !text.isEmpty else {
                log("ocr: no text found")
                return
            }
            if ocrWindow == nil {
                let win = OCRResultWindowController()
                win.onclose = { [weak self] in self?.ocrWindow = nil }
                ocrWindow = win
            }
            ocrWindow?.show(text: text)
        }
    }

    private func openEditor(image: CGImage) {
        let controller = EditorWindowController(image: image)
        controller.onExport = { [weak self] composite, kind in
            self?.handleEditorExport(composite, kind: kind)
        }
        controller.onOCR = { [weak self] composite in
            self?.runOCR(image: composite)
        }
        controller.onClose = { [weak self, weak controller] in
            guard let self, let controller else { return }
            self.editors.removeAll { $0 === controller }
        }
        editors.append(controller)
        controller.show()
        log("editor opened (\(editors.count) active)")
    }

    private func handleEditorExport(_ image: CGImage, kind: EditorModel.ExportKind) {
        guard let png = CaptureService.shared.pngData(from: image) else { return }
        switch kind {
        case .copy:
            AutoPaster.writeImageFlavors(.general, pngData: png)
            monitor.markOwnWrite()
            store?.add(
                NewClip(kind: .image, imageData: png,
                        sourceBundle: Bundle.main.bundleIdentifier, sourceName: "ClipIsland 编辑")
            )
        case .save:
            if let url = CaptureService.shared.savePNG(
                image, to: URL(fileURLWithPath: settings.screenshotSaveDirectory)
            ) {
                log("edited image saved: \(url.lastPathComponent)")
                notchModel.flashHangingImage(NSImage(cgImage: image, size: NSSize(
                    width: image.width, height: image.height
                )))
            }
        case .done:
            break
        }
    }

    private func wirePanelActions() {
        notchModel.onWillExpand = { [weak self] in
            self?.paster?.noteFrontmost()
            self?.vault.noteActivity()
            self?.notchModel.showAccessibilityHint =
                (self?.settings.autoPasteEnabled ?? false)
                && !AutoPaster.isAccessibilityTrusted
        }
        notchModel.refreshResults = { [weak self] in
            guard let self else { return }
            self.notchModel.applyResults(
                self.store?.search(query: self.notchModel.query, kind: self.notchModel.kindFilter) ?? []
            )
        }
        notchModel.onSelectItem = { [weak self] item in
            self?.select(item)
        }
        notchModel.onTogglePin = { [weak self] item in
            self?.store?.setPinned(!item.pinned, id: item.id)
            self?.notchModel.reloadResults()
        }
        notchModel.onDeleteItem = { [weak self] item in
            self?.store?.remove(id: item.id)
            self?.notchModel.reloadResults()
        }
        notchModel.onOCRItem = { [weak self] item in
            guard let self, let cg = Self.loadImage(from: item) else { return }
            self.runOCR(image: cg)
        }
        notchModel.onEditItem = { [weak self] item in
            guard let self, let cg = Self.loadImage(from: item) else { return }
            self.notchModel.collapse()
            self.openEditor(image: cg)
        }
        notchModel.onOpenAccessibilitySettings = {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    private func select(_ item: ClipItem) {
        notchModel.collapse()
        vault.noteActivity()
        paster?.paste(item)
    }

    public func stop() {
        monitor.stop()
    }

    // MARK: - Status bar

    private func buildStatusBarMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "clipboard", accessibilityDescription: "ClipIsland")
        item.menu = NSMenu()
        statusItem = item
        refreshStatusMenu()
    }

    private func refreshStatusMenu() {
        guard let item = statusItem, let menu = item.menu else { return }
        menu.removeAllItems()

        menu.addItem(withTitle: "展开 / 收起面板", action: #selector(togglePanel), keyEquivalent: "")
        menu.addItem(withTitle: monitor.paused ? "恢复监控" : "暂停监控", action: #selector(togglePause), keyEquivalent: "")
        if vault.isEnabled {
            menu.addItem(withTitle: "立即锁定", action: #selector(lockNow), keyEquivalent: "l")
        }
        menu.addItem(withTitle: "截图（选区）", action: #selector(takeScreenshot), keyEquivalent: "")
        menu.addItem(withTitle: "截图（窗口）", action: #selector(takeWindowScreenshot), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "清空历史", action: #selector(clearHistory), keyEquivalent: "")
        menu.addItem(withTitle: "设置…", action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 ClipIsland", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        for mi in menu.items where mi.action != #selector(NSApplication.terminate(_:)) {
            mi.target = self
        }
    }

    @objc private func togglePanel() {
        notchModel.toggle()
    }

    @objc private func togglePause() {
        let paused = !monitor.paused
        monitor.paused = paused
        settings.paused = paused
        notchModel.setPaused(paused)
        refreshStatusMenu()
    }

    @objc private func takeScreenshot() {
        startScreenshot()
    }

    @objc private func takeWindowScreenshot() {
        startWindowScreenshot()
    }

    private func startWindowScreenshot() {
        guard CaptureService.requestScreenCapturePermission() else {
            log("screen capture denied; opening System Settings")
            NSWorkspace.shared.open(
                URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
            )
            return
        }
        notchModel.collapse(animated: false)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.beginWindowSelection()
        }
    }

    private func beginWindowSelection() {
        notchWindow?.setIsland(hidden: true)
        selectionController.beginWindowCapture { [weak self] completion in
            guard let self else { return }
            self.notchWindow?.setIsland(hidden: false)
            switch completion.result {
            case .region(let image), .fullscreen(let image):
                self.deliverScreenshot(image)
            case .cancelled:
                log("window capture cancelled")
            }
        }
    }

    @objc private func clearHistory() {
        store?.clear()
    }

    @objc private func lockNow() {
        vault.lock()
    }

    // MARK: - Test hook

    /// Distributed-notification test hook so the UI state machine can be
    /// exercised from a terminal without accessibility permissions.
    private func installTestHook() {
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleTestNotification(_:)),
            name: NSNotification.Name("com.clipisland.test"),
            object: nil
        )
    }

    @objc private func handleTestNotification(_ note: Notification) {
        let action = note.userInfo?["action"] as? String ?? ""
        switch action {
        case "toggle":
            notchModel.toggle()
        case "expand":
            notchModel.expand()
        case "expandfast":
            notchModel.expand(animated: false)
        case "collapse":
            notchModel.collapse()
        case "count":
            log("store count=\(store?.count ?? -1)")
        case "pause":
            togglePause()
            log("pause -> \(monitor.paused)")
        case "pin":
            if let item = notchModel.results.first {
                notchModel.onTogglePin?(item)
                log("pin -> \(!item.pinned) id=\(item.id)")
            }
        case "delete":
            if let item = notchModel.results.first {
                notchModel.onDeleteItem?(item)
                log("deleted id=\(item.id)")
            }
        case "clear":
            store?.clear()
            log("cleared")
        case "flash": {
            let img = NSImage(size: NSSize(width: 300, height: 180))
            img.lockFocus()
            NSColor.systemBlue.setFill()
            NSBezierPath(rect: NSRect(origin: .zero, size: img.size)).fill()
            img.unlockFocus()
            notchModel.flashHangingImage(img)
        }()
        case "settings":
            openSettings()
        case "lock":
            vault.lock()
        case "setuppw": // faithful settings flow: setup + migration
            do {
                try vault.setup(password: "test1234")
                store?.migrateAll(enabled: true)
            } catch { log("setuppw: \(error)") }
            syncVaultState()
        case "unlockpw":
            do {
                try vault.unlock(password: "test1234")
                store?.flushPendingCaptures()
            } catch { log("unlockpw: \(error)") }
            syncVaultState()
        case "vaultstate":
            syncVaultState()
            log("vault state=\(vault.state) pending=\(store?.pendingCaptureCount ?? -1)")
        case "popup": {
            let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
            let ctx = CGContext(
                data: nil, width: 900, height: 560,
                bitsPerComponent: 8, bytesPerRow: 900 * 4,
                space: srgb,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            ctx.setFillColor(CGColor(srgbRed: 0.15, green: 0.4, blue: 0.9, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: 900, height: 560))
            guard let image = ctx.makeImage(),
                  let png = CaptureService.shared.pngData(from: image) else { return }
            postCaptureBar.show(
                thumbnail: Self.downsampledPNG(png, maxPixel: 500) ?? NSImage(),
                onCopy: { log("popup copy tapped") },
                onEdit: { log("popup edit tapped") },
                onReveal: { log("popup reveal tapped") }
            )
        }()
        case "kindfilter":
            notchModel.kindFilter = notchModel.kindFilter == .link ? nil : .link
            notchModel.reloadResults()
        case "digit2", "digit3":
            notchModel.handleSpecial(.digit(action.hasSuffix("3") ? 3 : 2))
        case "screenshot":
            startScreenshot()
        case "windowcapture":
            startWindowScreenshot()
        case "ocr": {
            // Renders "ClipIsland OCR 测试 2026" and runs OCR on it.
            let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
            let ctx = CGContext(
                data: nil, width: 600, height: 160,
                bitsPerComponent: 8, bytesPerRow: 600 * 4,
                space: srgb,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: 600, height: 160))
            let attr: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 44, weight: .semibold),
                .foregroundColor: NSColor.black,
            ]
            let str = NSAttributedString(string: "ClipIsland OCR 2026", attributes: attr)
            let nsCtx = NSGraphicsContext(cgContext: ctx, flipped: false)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = nsCtx
            str.draw(at: NSPoint(x: 30, y: 55))
            NSGraphicsContext.restoreGraphicsState()
            if let image = ctx.makeImage() {
                OCRService.recognizeText(in: image) { text in
                    log("ocr result: \(text ?? "nil")")
                }
            }
        }()
        case "editor":
            // Opens the editor with a synthetic gradient for smoke-testing.
            let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
            let ctx = CGContext(
                data: nil, width: 800, height: 500,
                bitsPerComponent: 8, bytesPerRow: 800 * 4,
                space: srgb,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            ctx.setFillColor(CGColor(srgbRed: 0.16, green: 0.18, blue: 0.22, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: 800, height: 500))
            for i in 0..<10 {
                ctx.setFillColor(CGColor(
                    srgbRed: CGFloat(i) / 10, green: 0.4, blue: 1 - CGFloat(i) / 10, alpha: 1
                ))
                ctx.fill(CGRect(x: CGFloat(i * 80), y: 0, width: 80, height: 500))
            }
            if let image = ctx.makeImage() {
                openEditor(image: image)
            }
        case "enter":
            notchModel.handleSpecial(.enter)
        case "down":
            notchModel.handleSpecial(.down)
        case "up":
            notchModel.handleSpecial(.up)
        case "results":
            log("results count=\(notchModel.results.count) selected=\(notchModel.selectedIndex)")
        case let q where q.hasPrefix("query:"):
            notchModel.query = String(q.dropFirst("query:".count))
            notchModel.reloadResults()
            log("query='\(notchModel.query)' results=\(notchModel.results.count)")
        default:
            break
        }
    }
}
