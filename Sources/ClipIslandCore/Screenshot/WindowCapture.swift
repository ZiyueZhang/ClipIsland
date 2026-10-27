import AppKit
import CoreGraphics

/// One on-screen, layer-0 window from another process that can be captured.
public struct CapturableWindow: Equatable {
    public let windowNumber: CGWindowID
    /// CG global coordinates, top-left origin (as CGWindowList reports).
    public let cgFrame: CGRect
    public let ownerName: String
    public let title: String

    public init(windowNumber: CGWindowID, cgFrame: CGRect, ownerName: String, title: String) {
        self.windowNumber = windowNumber
        self.cgFrame = cgFrame
        self.ownerName = ownerName
        self.title = title
    }
}

/// Enumerates capturable windows and captures one by number, even if it is
/// partially occluded (`.optionIncludingWindow` composites the window itself).
public final class WindowCaptureService {
    public static let shared = WindowCaptureService()
    public static let minimumSize = CGSize(width: 60, height: 40)

    private init() {}

    public func listWindows() -> [CapturableWindow] {
        let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] ?? []
        let ownPID = ProcessInfo.processInfo.processIdentifier

        var result: [CapturableWindow] = []
        for info in list {
            // Normal windows only: skips menu bar items, the Dock, overlays.
            guard (info[kCGWindowLayer as String] as? Int ?? Int.max) == 0 else { continue }
            // Never capture our own windows (island, popup bar, editor…).
            guard (info[kCGWindowOwnerPID as String] as? Int ?? -1) != ownPID else { continue }
            let number = info[kCGWindowNumber as String] as? Int ?? 0
            guard
                let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
                let x = bounds["X"], let y = bounds["Y"],
                let w = bounds["Width"], let h = bounds["Height"],
                w >= Self.minimumSize.width, h >= Self.minimumSize.height
            else { continue }
            let owner = info[kCGWindowOwnerName as String] as? String ?? "Window"
            let title = info[kCGWindowName as String] as? String ?? ""
            result.append(
                CapturableWindow(
                    windowNumber: CGWindowID(number),
                    cgFrame: CGRect(x: x, y: y, width: w, height: h),
                    ownerName: owner,
                    title: title
                )
            )
        }
        return result
    }

    /// The window a CG top-left-origin point lands on: the smallest-area
    /// containing window wins, so an inner panel beats the app's big frame.
    /// Pure — unit tested.
    public static func topWindow(at point: CGPoint, in windows: [CapturableWindow]) -> CapturableWindow? {
        windows
            .filter { $0.cgFrame.contains(point) }
            .min { a, b in
                let areaA = a.cgFrame.width * a.cgFrame.height
                let areaB = b.cgFrame.width * b.cgFrame.height
                if areaA != areaB { return areaA < areaB }
                return a.windowNumber < b.windowNumber
            }
    }

    /// Captures the window contents (occlusion-safe). Returns nil without
    /// screen-recording permission.
    public func capture(_ window: CapturableWindow) -> CGImage? {
        CGWindowListCreateImage(
            window.cgFrame,
            .optionIncludingWindow,
            window.windowNumber,
            [.bestResolution]
        )
    }

    /// Converts a CG top-left-origin rect into AppKit global coordinates
    /// (bottom-left origin). Pure — unit tested. CG's origin is the top-left
    /// of the *main* display; AppKit's is its bottom-left.
    public static func appKitRect(fromCG cg: CGRect, mainDisplayHeight: CGFloat) -> CGRect {
        CGRect(
            x: cg.minX,
            y: mainDisplayHeight - cg.maxY,
            width: cg.width,
            height: cg.height
        )
    }

    /// AppKit point → CG top-left-origin point.
    public static func cgPoint(fromAppKit p: CGPoint, mainDisplayHeight: CGFloat) -> CGPoint {
        CGPoint(x: p.x, y: mainDisplayHeight - p.y)
    }
}
