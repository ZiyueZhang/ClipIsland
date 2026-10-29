import AppKit

/// Layout math for the notch island: detects a real notch and computes the
/// window frames for the collapsed strip and the expanded panel. All frames
/// are snapped to physical pixels so the collapsed strip sits flush against
/// the hardware notch with no half-pixel seams on Retina displays.
public struct NotchLayout {
    public let screen: NSScreen
    public let hasRealNotch: Bool
    public let notchWidth: CGFloat
    public let notchHeight: CGFloat
    public let collapsedFrame: CGRect
    public let expandedFrame: CGRect

    /// The expanded panel keeps the strip's exact width — expansion animates
    /// height only, so nothing reflows horizontally mid-animation (no jank).
    public static let panelSize = CGSize(width: 480, height: 440)
    public static let simulatedNotch = CGSize(width: 210, height: 32)
    /// The collapsed strip extends past the hardware notch into the menu-bar
    /// areas on both sides so its content is actually visible — the notch
    /// itself is opaque hardware that would hide anything drawn over it.
    public static let stripExtensionLeft: CGFloat = 150
    public static let stripExtensionRight: CGFloat = 110

    /// Snaps a point value to the screen's physical pixel grid.
    static func snap(_ v: CGFloat, scale: CGFloat) -> CGFloat {
        guard scale > 0 else { return v }
        return (v * scale).rounded() / scale
    }

    static func snap(_ rect: CGRect, scale: CGFloat) -> CGRect {
        CGRect(
            x: snap(rect.minX, scale: scale),
            y: snap(rect.minY, scale: scale),
            width: snap(rect.width, scale: scale),
            height: snap(rect.height, scale: scale)
        )
    }

    public static func compute(preferred: NSScreen? = nil) -> NotchLayout {
        let screen = preferred
            ?? NSScreen.screens.first { $0.safeAreaInsets.top > 0 }
            ?? NSScreen.main
            ?? NSScreen.screens.first
            ?? NSScreen()
        let scale = screen.backingScaleFactor
        let topInset = screen.safeAreaInsets.top
        let hasNotch = topInset > 0
        var width = simulatedNotch.width
        if hasNotch,
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            width = max(0, right.minX - left.maxX)
        }
        let height = hasNotch ? topInset : simulatedNotch.height
        let visible = screen.frame
        let topY = visible.maxY
        let collapsed = snap(
            CGRect(
                x: visible.midX - width / 2 - Self.stripExtensionLeft,
                y: topY - height,
                width: width + Self.stripExtensionLeft + Self.stripExtensionRight,
                height: height
            ),
            scale: scale
        )
        let panel = panelSize
        let expanded = snap(
            CGRect(
                x: collapsed.minX,
                y: topY - panel.height,
                width: collapsed.width,
                height: panel.height
            ),
            scale: scale
        )
        return NotchLayout(
            screen: screen,
            hasRealNotch: hasNotch,
            notchWidth: width,
            notchHeight: height,
            collapsedFrame: collapsed,
            expandedFrame: expanded
        )
    }
}
