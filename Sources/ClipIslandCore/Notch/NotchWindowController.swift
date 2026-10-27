import AppKit
import SwiftUI

/// Borderless panel that can become key (keyboard routing happens here).
final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }

    /// Return true when the event was consumed (search chars, arrows, …).
    var keyHandler: ((NSEvent) -> Bool)?

    override func keyDown(with event: NSEvent) {
        if keyHandler?(event) == true { return }
        super.keyDown(with: event)
    }
}

/// Owns the always-on-top window above the notch/menu-bar area and animates
/// its frame between the collapsed strip and the expanded panel. Frame motion
/// runs on a spring (FrameAnimator) so it reads as one system with the
/// SwiftUI content springs inside.
public final class NotchWindowController {
    public let model: NotchModel
    private var panel: NotchPanel!
    private var layout: NotchLayout
    private var screenObserver: NSObjectProtocol?
    private var frameAnimator: FrameAnimator?
    /// Momentum carried across retargets so mid-flight redirects feel liquid.
    private var lastVelocity: Double = 0
    private var lastFrom: CGRect = .zero
    private var lastTo: CGRect = .zero

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
            panelWidth: NotchLayout.panelSize.width,
            notchWidth: layout.notchWidth,
            stripExtensionLeft: NotchLayout.stripExtensionLeft,
            stripExtensionRight: NotchLayout.stripExtensionRight
        )
    }

    // MARK: Island screen facts (used by the menu-bar hover monitor)

    /// Live dwell zone for the hover monitor: the collapsed strip's frame
    /// (which already extends past the notch) padded straight down.
    public var dwellZone: CGRect {
        MenuBarHoverMonitor.dwellZone(stripFrame: collapsedTarget())
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
        let previousSpan = frameAnimator != nil ? abs(lastFrom.width - lastTo.width) : 0
        frameAnimator?.cancel()
        guard animated else {
            lastVelocity = 0
            panel.setFrame(target, display: true)
            if phase == .expanded { panel.makeKeyAndOrderFront(nil); focusSearchField() }
            return
        }
        let profileName = SettingsStore.shared.animationProfile
        let profile: FrameAnimator.Profile = profileName == "bouncy" ? .bouncy : (profileName == "calm" ? .calm : .snappy)
        let from = panel.frame
        // Carry momentum: scale the previous progress-velocity into the new span.
        let newSpan = abs(from.width - target.width) + abs(from.height - target.height) + 1
        let carried = previousSpan > 0 ? lastVelocity * (previousSpan / newSpan) : 0
        if phase == .collapsed {
            // The strip view is what shows during the collapse animation —
            // its radii are final from the first frame.
            model.cornerTop = 6
            model.cornerBottom = 14
        }
        frameAnimator = FrameAnimator(
            from: from,
            to: target,
            profile: profile,
            expanding: phase == .expanded,
            initialVelocity: carried,
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        ) { [weak self] frame in
            guard let self else { return }
            self.panel.setFrame(frame, display: true)
            // Corner radii ride the same physics: content and window morph
            // in lockstep (boring.notch's animatable radii, Sapphire's single
            // motion system).
            let span = abs(lastFrom.width - lastTo.width)
            let t = span > 1 ? max(0, min(1, (frame.width - min(lastFrom.width, lastTo.width)) / span)) : (phase == .expanded ? 1 : 0)
            if phase == .expanded {
                self.model.cornerTop = 6 + (18 - 6) * CGFloat(t)
                self.model.cornerBottom = 14 + (26 - 14) * CGFloat(t)
            }
        }
        lastFrom = from
        lastTo = target
        if phase == .expanded, NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            model.cornerTop = 18
            model.cornerBottom = 26
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

    /// Used by the screenshot flow to keep the island out of captures.
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
    public let notchWidth: CGFloat
    public let stripExtensionLeft: CGFloat
    public let stripExtensionRight: CGFloat

    public init(
        hasRealNotch: Bool,
        headerHeight: CGFloat,
        panelWidth: CGFloat,
        notchWidth: CGFloat,
        stripExtensionLeft: CGFloat,
        stripExtensionRight: CGFloat
    ) {
        self.hasRealNotch = hasRealNotch
        self.headerHeight = headerHeight
        self.panelWidth = panelWidth
        self.notchWidth = notchWidth
        self.stripExtensionLeft = stripExtensionLeft
        self.stripExtensionRight = stripExtensionRight
    }
}
