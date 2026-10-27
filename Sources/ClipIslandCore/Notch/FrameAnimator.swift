import AppKit
import QuartzCore

/// Spring-driven window-frame animation. One physical system (stiffness +
/// damping derived from SwiftUI-style response/dampingFraction) drives the
/// NSPanel frame, so the window outline and the SwiftUI content inside share
/// the same motion feel. Steps at 120Hz on the main queue; CADisplayLink is
/// unavailable on macOS, and vsync alignment matters less than the physics.
public final class FrameAnimator {
    private var timer: DispatchSourceTimer?
    private var s: Double = 0 // progress 0...1 (may overshoot for underdamped)
    private var v: Double = 0
    private var last: CFTimeInterval = 0
    private let from: CGRect
    private let to: CGRect
    private let k: Double
    private let c: Double
    private let apply: (CGRect) -> Void

    /// Integrates one step of the scalar spring; exposed for tests.
    public static func advance(s: Double, v: Double, k: Double, c: Double, dt: Double) -> (s: Double, v: Double) {
        var v2 = v + (k * (1 - s) - c * v) * dt
        var s2 = s + v2 * dt
        // Midpoint correction for stability at large dt.
        if dt > 1 / 90 {
            let mid = dt / 2
            let vm = v + (k * (1 - s) - c * v) * mid
            let sm = s + vm * mid
            v2 = v + (k * (1 - sm) - c * vm) * dt
            s2 = s + v2 * dt
        }
        if s2.isNaN || v2.isNaN { return (1, 0) }
        return (s2, v2)
    }

    /// stiffness/damping from SwiftUI-style parameters.
    public static func coefficients(response: Double, dampingFraction: Double) -> (k: Double, c: Double) {
        let omega = 2 * .pi / max(response, 0.05)
        return (omega * omega, 2 * dampingFraction * omega)
    }

    init?(
        from: CGRect,
        to: CGRect,
        response: Double = 0.4,
        dampingFraction: Double = 0.82,
        reduceMotion: Bool = false,
        apply: @escaping (CGRect) -> Void
    ) {
        guard from != to else { return nil }
        self.from = from
        self.to = to
        self.apply = apply
        if reduceMotion {
            apply(to)
            return nil
        }
        (k, c) = Self.coefficients(response: response, dampingFraction: dampingFraction)
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: 1.0 / 120.0, leeway: .milliseconds(1))
        timer.setEventHandler { [weak self] in
            self?.step()
        }
        timer.resume()
        self.timer = timer
    }

    func cancel() {
        timer?.cancel()
        timer = nil
    }

    deinit {
        timer?.cancel()
    }

    private func step() {
        let now = CACurrentMediaTime()
        let dt = min(last == 0 ? 1 / 120 : now - last, 1 / 30)
        last = now
        (s, v) = Self.advance(s: s, v: v, k: k, c: c, dt: dt)
        if abs(1 - s) < 0.002, abs(v) < 0.004 {
            cancel()
            apply(to)
            return
        }
        apply(Self.lerp(from, to, CGFloat(s)))
    }

    private static func lerp(_ a: CGRect, _ b: CGRect, _ t: CGFloat) -> CGRect {
        CGRect(
            x: a.origin.x + (b.origin.x - a.origin.x) * t,
            y: a.origin.y + (b.origin.y - a.origin.y) * t,
            width: a.width + (b.width - a.width) * t,
            height: a.height + (b.height - a.height) * t
        )
    }
}
