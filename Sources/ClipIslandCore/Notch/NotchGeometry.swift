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

    public static let panelSize = CGSize(width: 660, height: 430)
    public static let simulatedNotch = CGSize(width: 210, height: 32)

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
                x: visible.midX - width / 2,
                y: topY - height,
                width: width,
                height: height
            ),
            scale: scale
        )
        let panel = panelSize
        let expanded = snap(
            CGRect(
                x: visible.midX - panel.width / 2,
                y: topY - panel.height,
                width: panel.width,
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
