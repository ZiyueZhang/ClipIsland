import AppKit

/// Watches for the pointer resting in the menu-bar band and fires a dwell
/// callback (tendedero-style). Lets the island be summoned from anywhere in
/// the menu bar, not just the 220pt notch area.
///
/// Clicking any menu-bar item suppresses triggering for a moment, so using
/// real menus never slides the panel down mid-click.
public final class MenuBarHoverMonitor {
    public var onDwell: (() -> Void)?

    static let dwell: TimeInterval = 0.25
    static let clickSuppression: TimeInterval = 1.2
    /// Poll rate; NSEvent.mouseLocation is a cheap struct read.
    static let tickInterval: TimeInterval = 1.0 / 30.0

    private var timer: Timer?
    private var dwellStart: Date?
    private var suppressUntil = Date.distantPast
    private var clickMonitors: [Any] = []

    public init() {}

    /// The menu-bar band of a screen: from the top of the screen down to the
    /// visible area. Pure for tests. With an auto-hiding menu bar the visible
    /// frame reaches the top, so fall back to system thickness / safe inset.
    public static func band(
        screenFrame: CGRect,
        visibleFrame: CGRect,
        statusBarThickness: CGFloat,
        topInset: CGFloat
    ) -> CGRect {
        var h = screenFrame.maxY - visibleFrame.maxY
        if h < 1 { h = max(statusBarThickness, topInset, 24) }
        return CGRect(x: screenFrame.minX, y: screenFrame.maxY - h, width: screenFrame.width, height: h)
    }

    /// `shouldRun` gates every tick so the monitor idles while the panel is
    /// expanded or hover-expand is disabled in settings.
    public func start(shouldRun: @escaping () -> Bool) {
        stop()
        installClickMonitors()
        let timer = Timer(timeInterval: Self.tickInterval, repeats: true) { [weak self] _ in
            self?.tick(shouldRun: shouldRun)
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
        dwellStart = nil
        for monitor in clickMonitors {
            NSEvent.removeMonitor(monitor)
        }
        clickMonitors.removeAll()
    }

    deinit {
        stop()
    }

    private func tick(shouldRun: () -> Bool) {
        guard shouldRun(), Date() >= suppressUntil else {
            dwellStart = nil
            return
        }
        let point = NSEvent.mouseLocation
        guard isInsideBand(point) else {
            dwellStart = nil
            return
        }
        let since = dwellStart ?? Date()
        dwellStart = since
        if Date().timeIntervalSince(since) >= Self.dwell {
            dwellStart = nil
            onDwell?()
        }
    }

    private func isInsideBand(_ point: NSPoint) -> Bool {
        // The band is recomputed per tick: cheap, and tracks display changes.
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(point, $0.frame, false) }) else {
            return false
        }
        let band = Self.band(
            screenFrame: screen.frame,
            visibleFrame: screen.visibleFrame,
            statusBarThickness: NSStatusBar.system.thickness,
            topInset: screen.safeAreaInsets.top
        )
        return band.contains(point)
    }

    /// Any click in the band (menu items, menu bar icons) postpones triggering
    /// until the pointer has left and re-entered with intent.
    private func installClickMonitors() {
        let handler: (NSEvent) -> Void = { [weak self] event in
            guard let self else { return }
            let point = NSEvent.mouseLocation
            guard let screen = NSScreen.screens.first(where: { NSMouseInRect(point, $0.frame, false) }) else {
                return
            }
            let band = Self.band(
                screenFrame: screen.frame,
                visibleFrame: screen.visibleFrame,
                statusBarThickness: NSStatusBar.system.thickness,
                topInset: screen.safeAreaInsets.top
            )
            if band.contains(point) {
                self.suppressUntil = Date().addingTimeInterval(Self.clickSuppression)
                self.dwellStart = nil
            }
        }
        // Global mouse monitors need no special permission; keyboard would.
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown], handler: handler) {
            clickMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown], handler: { event in
            handler(event)
            return event
        }) {
            clickMonitors.append(local)
        }
    }
}
