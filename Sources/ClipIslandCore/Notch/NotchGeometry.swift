import AppKit

/// Layout math for the notch island: detects a real notch and computes the
/// window frames for the collapsed strip and the expanded panel.
public struct NotchLayout {
    public let screen: NSScreen
    public let hasRealNotch: Bool
    public let notchWidth: CGFloat
    public let notchHeight: CGFloat
    public let collapsedFrame: CGRect
    public let expandedFrame: CGRect

    public static let panelSize = CGSize(width: 660, height: 430)
    public static let simulatedNotch = CGSize(width: 210, height: 32)

    public static func compute(preferred: NSScreen? = nil) -> NotchLayout {
        let screen = preferred
            ?? NSScreen.screens.first { $0.safeAreaInsets.top > 0 }
            ?? NSScreen.main
            ?? NSScreen.screens.first
            ?? NSScreen()
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
        let collapsed = CGRect(
            x: visible.midX - width / 2,
            y: topY - height,
            width: width,
            height: height
        )
        let panel = panelSize
        let expanded = CGRect(
            x: visible.midX - panel.width / 2,
            y: topY - panel.height,
            width: panel.width,
            height: panel.height
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
