import AppKit

/// Watches for the pointer resting in the dwell zone — the strip directly
/// below the notch (its own width, padded downward) — and fires a callback
/// after a short dwell. Clicks inside the zone suppress triggering briefly,
/// so interacting with real menu items never slides the panel down.
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
    private var zoneProvider: (() -> CGRect?)?

    public init() {}

    /// How far below the strip the dwell zone reaches.
    public static let belowPadding: CGFloat = 36

    /// The dwell zone: the strip's own footprint extended straight down.
    /// Pure — unit tested.
    public static func dwellZone(stripFrame: CGRect, belowPadding: CGFloat = 36) -> CGRect {
        stripFrame.insetBy(dx: 0, dy: -belowPadding / 2)
    }

    /// `shouldRun` gates every tick (panel collapsed, hover enabled, vault
    /// unlocked); `zoneProvider` supplies the live dwell zone.
    public func start(shouldRun: @escaping () -> Bool, zoneProvider: @escaping () -> CGRect?) {
        stop()
        self.zoneProvider = zoneProvider
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
        guard let zone = zoneProvider?() else {
            dwellStart = nil
            return
        }
        guard zone.contains(NSEvent.mouseLocation) else {
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

    /// Any click resets a pending dwell; clicks inside the zone also suppress
    /// triggering for a beat so the panel never drops right after a click.
    private func installClickMonitors() {
        let handler: (NSEvent) -> Void = { [weak self] event in
            guard let self else { return }
            dwellStart = nil
            if let zone = self.zoneProvider?(), zone.contains(NSEvent.mouseLocation) {
                self.suppressUntil = Date().addingTimeInterval(Self.clickSuppression)
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
