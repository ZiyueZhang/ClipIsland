import AppKit
import SwiftUI

/// Borderless panel that can become key (keyboard routing happens in M3).
final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }

    /// Return true when the event was consumed (search chars, arrows, …).
    var keyHandler: ((NSEvent) -> Bool)?

    override func keyDown(with event: NSEvent) {
        if keyHandler?(event) == true { return }
        super.keyDown(with: event)
    }
}

/// Deterministic window-frame interpolation. NSWindow's animator-proxy frame
/// animation is unreliable under a SwiftUI-driven content view, so we drive
/// the frame ourselves with a timer and an ease-in-out curve.
final class FrameAnimator {
    private var timer: Timer?
    private let from: CGRect
    private let to: CGRect
    private let startedAt: Date
    private let duration: Double
    private let apply: (CGRect) -> Void

    init?(from: CGRect, to: CGRect, duration: Double, apply: @escaping (CGRect) -> Void) {
        guard from != to else { return nil }
        self.from = from
        self.to = to
        self.duration = duration
        self.apply = apply
        self.startedAt = Date()
        let timer = Timer(timeInterval: 1.0 / 90.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        let raw = Date().timeIntervalSince(startedAt) / duration
        guard raw < 1 else {
            stop()
            apply(to)
            return
        }
        apply(interpolate(from, to, easeInOut(clamp(raw))))
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func clamp(_ t: Double) -> Double { min(max(t, 0), 1) }

    private func easeInOut(_ t: Double) -> Double {
        t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
    }

    private func interpolate(_ a: CGRect, _ b: CGRect, _ t: Double) -> CGRect {
        let f = CGFloat(t)
        return CGRect(
            x: a.origin.x + (b.origin.x - a.origin.x) * f,
            y: a.origin.y + (b.origin.y - a.origin.y) * f,
            width: a.width + (b.width - a.width) * f,
            height: a.height + (b.height - a.height) * f
        )
    }
}

/// Owns the always-on-top window above the notch/menu-bar area and animates
/// its frame between the collapsed strip and the expanded panel.
public final class NotchWindowController {
    public let model: NotchModel
    private var panel: NotchPanel!
    private var layout: NotchLayout
    private var screenObserver: NSObjectProtocol?
    private var frameAnimator: FrameAnimator?

    public init(model: NotchModel) {
        self.model = model
        self.layout = NotchLayout.compute()
        model.onPhaseChange = { [weak self] phase, animated in
            self?.apply(phase: phase, animated: animated)
        }
        model.onHangingImageChange = { [weak self] _ in
            guard let self else { return }
            self.apply(phase: self.model.phase, animated: true)
        }
        buildPanel()
        panel.keyHandler = { [weak model] event in
            model?.handlePanelKey(event) ?? false
        }
        observeScreenChanges()
        panel.orderFrontRegardless()
        log("notch window ready on \(layout.screen.localizedName), realNotch=\(layout.hasRealNotch)")
    }

    deinit {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
    }

    public var displayInfo: NotchDisplayInfo {
        NotchDisplayInfo(
            hasRealNotch: layout.hasRealNotch,
            headerHeight: layout.notchHeight,
            panelWidth: NotchLayout.panelSize.width
        )
    }

    private func buildPanel() {
        let p = NotchPanel(
            contentRect: layout.collapsedFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.level = .statusBar
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.isMovable = false
        p.hidesOnDeactivate = false
        p.contentView = NSHostingView(rootView: NotchRootView(model: model, info: displayInfo))
        panel = p
    }

    /// Extra height below the strip while a screenshot thumbnail hangs.
    static let hangExtra: CGFloat = 92

    private func collapsedTarget() -> CGRect {
        var frame = layout.collapsedFrame
        if model.hangingImage != nil {
            frame.origin.y -= Self.hangExtra
            frame.size.height += Self.hangExtra
        }
        return frame
    }

    private func apply(phase: NotchModel.Phase, animated: Bool) {
        let target = phase == .collapsed ? collapsedTarget() : layout.expandedFrame
        frameAnimator?.stop()
        guard animated else {
            panel.setFrame(target, display: true)
            if phase == .expanded { panel.makeKeyAndOrderFront(nil); focusSearchField() }
            return
        }
        frameAnimator = FrameAnimator(
            from: panel.frame,
            to: target,
            duration: 0.30
        ) { [weak self] frame in
            self?.panel.setFrame(frame, display: true)
        }
        if phase == .expanded {
            panel.makeKeyAndOrderFront(nil)
            focusSearchField()
        }
    }

    /// The search field lives inside SwiftUI hosting; locate it and give it
    /// keyboard focus once the expanded content has rendered.
    private func focusSearchField() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) { [weak self] in
            guard
                let self,
                let content = self.panel.contentView,
                let field = Self.findSearchField(content)
            else { return }
            if self.panel.firstResponder !== field.currentEditor() {
                self.panel.makeFirstResponder(field)
            }
        }
    }

    private static func findSearchField(_ view: NSView) -> PanelSearchField? {
        if let field = view as? PanelSearchField { return field }
        for sub in view.subviews {
            if let field = findSearchField(sub) { return field }
        }
        return nil
    }

    private func observeScreenChanges() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.layout = NotchLayout.compute()
            self.panel.contentView = NSHostingView(rootView: NotchRootView(model: self.model, info: self.displayInfo))
            self.apply(phase: self.model.phase, animated: false)
        }
    }

    /// Used by the screenshot flow (M5) to keep the island out of captures.
    public func setIsland(hidden: Bool) {
        if hidden {
            panel.orderOut(nil)
        } else {
            panel.orderFrontRegardless()
        }
    }
}

/// Immutable geometry facts the SwiftUI layer needs.
public struct NotchDisplayInfo {
    public let hasRealNotch: Bool
    public let headerHeight: CGFloat
    public let panelWidth: CGFloat

    public init(hasRealNotch: Bool, headerHeight: CGFloat, panelWidth: CGFloat) {
        self.hasRealNotch = hasRealNotch
        self.headerHeight = headerHeight
        self.panelWidth = panelWidth
    }
}
