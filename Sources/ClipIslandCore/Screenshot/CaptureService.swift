import AppKit
import CoreGraphics

/// Screen-freezing, pixel sampling and file saving for the screenshot flow.
public final class CaptureService {
    public struct FrozenScreen {
        public let screen: NSScreen
        public let image: CGImage
        /// RGBA8 bitmap of `image` for O(1) color sampling.
        public let pixels: PixelBuffer
        /// Frame in global flipped coordinates matching the image's layout.
        public let frameInScreen: CGRect

        public init(screen: NSScreen, image: CGImage, pixels: PixelBuffer, frameInScreen: CGRect) {
            self.screen = screen
            self.image = image
            self.pixels = pixels
            self.frameInScreen = frameInScreen
        }
    }

    public static let shared = CaptureService()
    private init() {}

    // MARK: - Permissions

    static var hasScreenCapturePermission: Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Prompts if needed; returns false when the user has denied.
    static func requestScreenCapturePermission() -> Bool {
        if CGPreflightScreenCaptureAccess() { return true }
        return CGRequestScreenCaptureAccess()
    }

    // MARK: - Freeze

    /// Captures every screen before any overlay is shown so selection UI is
    /// never part of the shot.
    func freezeAllScreens() -> [FrozenScreen] {
        var frozen: [FrozenScreen] = []
        for screen in NSScreen.screens {
            let rect = CGRect(origin: .zero, size: screen.frame.size)
            var image: CGImage?
            if let shot = CGWindowListCreateImage(
                rect, .optionOnScreenOnly, kCGNullWindowID,
                [.bestResolution]
            ) {
                image = shot
            } else {
                image = captureViaCLI(screen: screen)
            }
            guard let image, let pixels = PixelBuffer(image: image) else { continue }
            frozen.append(
                FrozenScreen(
                    screen: screen,
                    image: image,
                    pixels: pixels,
                    frameInScreen: CGRect(origin: screen.frame.origin, size: screen.frame.size)
                )
            )
        }
        return frozen
    }

    /// Fallback when CGWindowListCreateImage is blocked: the system
    /// `screencapture` tool writes to a temp file we read back.
    private func captureViaCLI(screen: NSScreen) -> CGImage? {
        let tmp = NSTemporaryDirectory() + "clipisland-capture-\(UUID().uuidString).png"
        defer { try? FileManager.default.removeItem(atPath: tmp) }
        let f = screen.frame
        let rect = "\(f.origin.x),\(f.origin.y),\(f.width),\(f.height)"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-x", "-R", rect, tmp]
        guard (try? process.run()) != nil else { return nil }
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let data = FileManager.default.contents(atPath: tmp),
              let provider = CGDataProvider(data: data as CFData),
              let cg = CGImage(pngDataProviderSource: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        else { return nil }
        return cg
    }

    /// Crops a selection (in screen coordinates, bottom-left origin) from the
    /// matching frozen screen; image rows are top-down, hence the y flip.
    public func crop(selection: CGRect, from frozen: [FrozenScreen]) -> CGImage? {
        guard let target = frozen.first(where: { $0.frameInScreen.intersects(selection) }) else {
            return nil
        }
        let scaleX = CGFloat(target.image.width) / target.frameInScreen.width
        let scaleY = CGFloat(target.image.height) / target.frameInScreen.height
        let local = CGRect(
            x: (selection.minX - target.frameInScreen.minX) * scaleX,
            y: (target.frameInScreen.maxY - selection.maxY) * scaleY,
            width: selection.width * scaleX,
            height: selection.height * scaleY
        )
        let integral = local.integral
        guard integral.width >= 4, integral.height >= 4,
              integral.maxX <= CGFloat(target.image.width), integral.maxY <= CGFloat(target.image.height)
        else { return nil }
        return target.image.cropping(to: integral)
    }

    /// Samples the pixel color at a global screen point.
    public func color(at point: NSPoint, in frozen: [FrozenScreen]) -> NSColor? {
        guard let target = frozen.first(where: { $0.frameInScreen.contains(point) }) else {
            return nil
        }
        // Image rows run top-to-bottom; screen points run bottom-to-top.
        let x = (point.x - target.frameInScreen.minX) * CGFloat(target.image.width) / target.frameInScreen.width
        let yFlipped = target.frameInScreen.maxY - point.y
        let y = yFlipped * CGFloat(target.image.height) / target.frameInScreen.height
        return target.pixels.color(x: Int(x), y: Int(y))
    }

    // MARK: - Export

    public func pngData(from image: CGImage) -> Data? {
        let rep = NSBitmapImageRep(cgImage: image)
        return rep.representation(using: .png, properties: [:])
    }

    @discardableResult
    public func savePNG(_ image: CGImage, to directory: URL) -> URL? {
        guard let data = pngData(from: image) else { return nil }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let stamp = Self.fileTimestamp()
            let url = directory.appendingPathComponent("ClipIsland-\(stamp).png")
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            log("screenshot save failed: \(error.localizedDescription)")
            return nil
        }
    }

    private static func fileTimestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd-HHmmss"
        return f.string(from: Date())
    }
}

/// Simple RGBA8 pixel store for color picking.
public final class PixelBuffer {
    let width: Int
    let height: Int
    private let bytes: [UInt8]

    public init?(image: CGImage) {
        let w = image.width
        let h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let ok: Bool = data.withUnsafeMutableBytes { ptr in
            guard let base = ptr.baseAddress else { return false }
            let ctx = CGContext(
                data: base,
                width: w, height: h,
                bitsPerComponent: 8, bytesPerRow: w * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
            guard let ctx else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard ok else { return nil }
        width = w
        height = h
        bytes = data
    }

    public func color(x: Int, y: Int) -> NSColor? {
        guard x >= 0, y >= 0, x < width, y < height else { return nil }
        let idx = (y * width + x) * 4
        return NSColor(
            srgbRed: CGFloat(bytes[idx]) / 255.0,
            green: CGFloat(bytes[idx + 1]) / 255.0,
            blue: CGFloat(bytes[idx + 2]) / 255.0,
            alpha: 1
        )
    }
}

public extension NSColor {
    /// "#RRGGBB" hex string in sRGB (matches the pixel buffers we sample).
    var hexString: String {
        let rgb = usingColorSpace(.sRGB) ?? self
        return String(
            format: "#%02X%02X%02X",
            Int(round(rgb.redComponent * 255)),
            Int(round(rgb.greenComponent * 255)),
            Int(round(rgb.blueComponent * 255))
        )
    }
}
