import AppKit
import Observation

/// State machine for the notch island plus the expanded panel's content
/// state (query, selection, results). Keyboard events are routed here from
/// the panel and the search field.
@Observable
public final class NotchModel {
    public enum Phase: Equatable {
        case collapsed
        case expanded
    }

    public enum SpecialKey {
        case up
        case down
        case enter
        case escape
        case digit(Int)
        case quickLook
    }

    public private(set) var phase: Phase = .collapsed

    // Island status
    public var clipCount = 0
    public private(set) var paused = false
    public var expandOnHover = true
    public var showAccessibilityHint = false

    /// Screenshot thumbnail that "hangs" under the collapsed strip briefly.
    public var hangingImage: NSImage?
    private var hangClearTask: DispatchWorkItem?
    /// True when a hanging thumbnail is showing (window needs extra height).
    public var onHangingImageChange: ((Bool) -> Void)?

    public func flashHangingImage(_ image: NSImage, for seconds: TimeInterval = 2.5) {
        hangClearTask?.cancel()
        hangingImage = image
        onHangingImageChange?(true)
        let task = DispatchWorkItem { [weak self] in
            self?.hangingImage = nil
            self?.onHangingImageChange?(false)
        }
        hangClearTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: task)
    }

    // Panel content state
    public var query = ""
    public var kindFilter: ClipKind?
    public private(set) var results: [ClipItem] = []
    public var selectedIndex = 0
    public var hoveredItemID: Int64?

    // Wired by the coordinator.
    public var refreshResults: (() -> Void)?
    public var onSelectItem: ((ClipItem) -> Void)?
    public var onTogglePin: ((ClipItem) -> Void)?
    public var onDeleteItem: ((ClipItem) -> Void)?
    public var onEditItem: ((ClipItem) -> Void)?
    public var onOCRItem: ((ClipItem) -> Void)?
    public var onOpenAccessibilitySettings: (() -> Void)?
    public var onQuickLookItem: ((ClipItem) -> Void)?
    public var onVaultUnlockPassword: ((String) -> Void)?
    public var onVaultUnlockTouchID: (() -> Void)?

    // Vault lock screen state
    public var vaultLocked = false
    public var vaultUnlockError: String?
    public var vaultTouchIDEnabled = false
    public var vaultTouchIDAvailable = Vault.isTouchIDAvailable
    public var vaultPendingCount = 0
    public var vaultPasswordField = ""
    public var hoverInside = false
    public var dragProvider: ((ClipItem) -> NSItemProvider?)?

    /// Coordinator hook: hover summon is suppressed while the vault is locked.
    func expandOnHoverGateForLock() {}

    /// Fired before the panel expands (e.g. to snapshot the frontmost app).
    public var onWillExpand: (() -> Void)?
    public var onPhaseChange: ((Phase, Bool) -> Void)?

    private var hoverTask: DispatchWorkItem?

    public init() {}

    public func setPaused(_ value: Bool) {
        paused = value
    }

    // MARK: - Phase

    public func setHover(inside: Bool) {
        if inside {
            hoverTask?.cancel()
            guard expandOnHover, phase == .collapsed else { return }
            let task = DispatchWorkItem { [weak self] in
                self?.expand()
            }
            hoverTask = task
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: task)
        } else {
            hoverTask?.cancel()
            guard phase == .expanded else { return }
            let task = DispatchWorkItem { [weak self] in
                self?.collapse()
            }
            hoverTask = task
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.30, execute: task)
        }
    }

    public func expand(animated: Bool = true) {
        hoverTask?.cancel()
        setPhase(.expanded, animated: animated)
    }

    public func collapse(animated: Bool = true) {
        hoverTask?.cancel()
        setPhase(.collapsed, animated: animated)
    }

    public func toggle() {
        phase == .collapsed ? expand() : collapse()
    }

    private func setPhase(_ new: Phase, animated: Bool) {
        guard new != phase else { return }
        if new == .expanded {
            onWillExpand?()
            selectedIndex = 0
        }
        phase = new
        log("notch phase -> \(new == .collapsed ? "collapsed" : "expanded")")
        onPhaseChange?(new, animated)
    }

    // MARK: - Results

    /// Called by the coordinator's refreshResults closure.
    public func applyResults(_ newResults: [ClipItem]) {
        results = newResults
        if selectedIndex >= results.count { selectedIndex = 0 }
    }

    public func reloadResults() {
        refreshResults?()
        if selectedIndex >= results.count { selectedIndex = 0 }
    }

    /// Index (1-based digit) of a result, nil if out of range.
    public var digitTargets: [ClipItem] {
        Array(results.prefix(9))
    }

    // MARK: - Keyboard

    public func handleSpecial(_ key: SpecialKey) {
        switch key {
        case .down:
            if !results.isEmpty {
                selectedIndex = (selectedIndex + 1) % results.count
            }
        case .up:
            if !results.isEmpty {
                selectedIndex = (selectedIndex - 1 + results.count) % results.count
            }
        case .enter:
            guard results.indices.contains(selectedIndex) else { return }
            onSelectItem?(results[selectedIndex])
        case .escape:
            if !query.isEmpty {
                query = ""
                reloadResults()
            } else if kindFilter != nil {
                kindFilter = nil
                reloadResults()
            } else {
                collapse()
            }
        case .digit(let n):
            let targets = digitTargets
            guard targets.indices.contains(n - 1) else { return }
            onSelectItem?(targets[n - 1])
        case .quickLook:
            guard results.indices.contains(selectedIndex) else { return }
            onQuickLookItem?(results[selectedIndex])
        }
    }

    /// Panel-level fallback when the search field is not first responder.
    /// Returns true when consumed.
    public func handlePanelKey(_ event: NSEvent) -> Bool {
        if event.charactersIgnoringModifiers == "\u{1b}" {
            handleSpecial(.escape)
            return true
        }
        guard event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty else { return false }
        if event.specialKey == .downArrow { handleSpecial(.down); return true }
        if event.specialKey == .upArrow { handleSpecial(.up); return true }
        if event.specialKey == .carriageReturn || event.keyCode == 76 { handleSpecial(.enter); return true }
        if event.keyCode == 49 { handleSpecial(.quickLook); return true } // space
        if let c = event.charactersIgnoringModifiers, c.count == 1, let d = Int(c), (1...9).contains(d) {
            handleSpecial(.digit(d))
            return true
        }
        return false
    }
}
