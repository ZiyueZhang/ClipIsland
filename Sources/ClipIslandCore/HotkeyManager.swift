import AppKit
import Carbon.HIToolbox
import Foundation

/// Global hotkeys via Carbon's RegisterEventHotKey — still the standard way
/// for system-wide shortcuts without helper processes.
public final class HotkeyManager {
    public var onPanelHotkey: (() -> Void)?
    public var onScreenshotHotkey: (() -> Void)?
    public var onWindowCaptureHotkey: (() -> Void)?

    private var panelRef: EventHotKeyRef?
    private var shotRef: EventHotKeyRef?
    private var windowRef: EventHotKeyRef?
    private var handlerInstalled = false

    private let panelSignature: OSType = 0x4350_4950 // "CLIP"
    private let shotSignature: OSType = 0x434C_4953 // "CLIS"
    private let windowSignature: OSType = 0x434C_5744 // "CLWD"

    public init() {}

    public func start(panelCombo: String, screenshotCombo: String, windowCombo: String? = nil) {
        installHandlerIfNeeded()
        reregister(panelCombo: panelCombo, screenshotCombo: screenshotCombo, windowCombo: windowCombo)
    }

    public func reregister(panelCombo: String, screenshotCombo: String, windowCombo: String? = nil) {
        unregister()
        if let combo = Self.parse(panelCombo) {
            let id = EventHotKeyID(signature: panelSignature, id: 1)
            let status = RegisterEventHotKey(UInt32(combo.keyCode), combo.carbonFlags, id, GetApplicationEventTarget(), 0, &panelRef)
            log("panel hotkey \(panelCombo): \(status == noErr ? "ok" : "failed(\(status))")")
        }
        if let combo = Self.parse(screenshotCombo) {
            let id = EventHotKeyID(signature: shotSignature, id: 2)
            let status = RegisterEventHotKey(UInt32(combo.keyCode), combo.carbonFlags, id, GetApplicationEventTarget(), 0, &shotRef)
            log("screenshot hotkey \(screenshotCombo): \(status == noErr ? "ok" : "failed(\(status))")")
        }
        if let windowCombo, let combo = Self.parse(windowCombo) {
            let id = EventHotKeyID(signature: windowSignature, id: 3)
            let status = RegisterEventHotKey(UInt32(combo.keyCode), combo.carbonFlags, id, GetApplicationEventTarget(), 0, &windowRef)
            log("window capture hotkey \(windowCombo): \(status == noErr ? "ok" : "failed(\(status))")")
        }
    }

    private func unregister() {
        if let panelRef { UnregisterEventHotKey(panelRef); self.panelRef = nil }
        if let shotRef { UnregisterEventHotKey(shotRef); self.shotRef = nil }
        if let windowRef { UnregisterEventHotKey(windowRef); self.windowRef = nil }
    }

    private func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        var installed: EventHandlerRef?
        // One static trampoline dispatches to the shared instance.
        HotkeyManager.sharedForCallbacks = self
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ in
                HotkeyManager.handleCarbonEvent(event)
            },
            1,
            &spec,
            nil,
            &installed
        )
        handlerInstalled = installed != nil
    }

    // MARK: - Static dispatch bridge

    private static weak var sharedForCallbacks: HotkeyManager?

    private static func handleCarbonEvent(_ event: EventRef?) -> OSStatus {
        guard let event else { return noErr }
        var id = EventHotKeyID()
        GetEventParameter(
            event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
            nil, MemoryLayout<EventHotKeyID>.size, nil, &id
        )
        guard let manager = sharedForCallbacks else { return noErr }
        if id.signature == manager.panelSignature {
            DispatchQueue.main.async { manager.onPanelHotkey?() }
        } else if id.signature == manager.shotSignature {
            DispatchQueue.main.async { manager.onScreenshotHotkey?() }
        } else if id.signature == manager.windowSignature {
            DispatchQueue.main.async { manager.onWindowCaptureHotkey?() }
        }
        return noErr
    }

    // MARK: - Combo parsing ("cmd+shift+v" → flags + keycode)

    public struct Combo: Equatable {
        public let keyCode: Int
        public let carbonFlags: UInt32
        public let display: String
    }

    public static func parse(_ combo: String) -> Combo? {
        let parts = combo.lowercased()
            .split(separator: "+")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard parts.count >= 2 else { return nil } // at least one modifier + one key

        var flags: UInt32 = 0
        var key: Int?
        for part in parts {
            switch part {
            case "cmd", "command": flags |= UInt32(cmdKey)
            case "shift": flags |= UInt32(shiftKey)
            case "opt", "option", "alt": flags |= UInt32(optionKey)
            case "ctrl", "control": flags |= UInt32(controlKey)
            default:
                guard key == nil, let code = keyCode(for: part) else { return nil }
                key = code
            }
        }
        guard flags != 0, let key else { return nil }
        return Combo(keyCode: key, carbonFlags: flags, display: combo)
    }

    static func keyCode(for name: String) -> Int? {
        if name.count == 1 {
            if let code = Self.letterKeyCodes[name] {
                return code
            }
            if let digits = Self.digitKeyCodes[name] {
                return digits
            }
        }
        return Self.namedKeys[name]
    }

    /// ANSI virtual keycodes are laid out by physical key, not alphabet.
    static let letterKeyCodes: [String: Int] = [
        "a": Int(kVK_ANSI_A), "b": Int(kVK_ANSI_B), "c": Int(kVK_ANSI_C),
        "d": Int(kVK_ANSI_D), "e": Int(kVK_ANSI_E), "f": Int(kVK_ANSI_F),
        "g": Int(kVK_ANSI_G), "h": Int(kVK_ANSI_H), "i": Int(kVK_ANSI_I),
        "j": Int(kVK_ANSI_J), "k": Int(kVK_ANSI_K), "l": Int(kVK_ANSI_L),
        "m": Int(kVK_ANSI_M), "n": Int(kVK_ANSI_N), "o": Int(kVK_ANSI_O),
        "p": Int(kVK_ANSI_P), "q": Int(kVK_ANSI_Q), "r": Int(kVK_ANSI_R),
        "s": Int(kVK_ANSI_S), "t": Int(kVK_ANSI_T), "u": Int(kVK_ANSI_U),
        "v": Int(kVK_ANSI_V), "w": Int(kVK_ANSI_W), "x": Int(kVK_ANSI_X),
        "y": Int(kVK_ANSI_Y), "z": Int(kVK_ANSI_Z),
    ]

    static let digitKeyCodes: [String: Int] = [
        "0": Int(kVK_ANSI_0), "1": Int(kVK_ANSI_1), "2": Int(kVK_ANSI_2),
        "3": Int(kVK_ANSI_3), "4": Int(kVK_ANSI_4), "5": Int(kVK_ANSI_5),
        "6": Int(kVK_ANSI_6), "7": Int(kVK_ANSI_7), "8": Int(kVK_ANSI_8),
        "9": Int(kVK_ANSI_9),
    ]

    static let namedKeys: [String: Int] = [
        "space": Int(kVK_Space),
        "tab": Int(kVK_Tab),
        "delete": Int(kVK_Delete),
        "escape": Int(kVK_Escape),
        "f1": Int(kVK_F1), "f2": Int(kVK_F2), "f3": Int(kVK_F3), "f4": Int(kVK_F4),
        "f5": Int(kVK_F5), "f6": Int(kVK_F6), "f7": Int(kVK_F7), "f8": Int(kVK_F8),
        "f9": Int(kVK_F9), "f10": Int(kVK_F10), "f11": Int(kVK_F11), "f12": Int(kVK_F12),
    ]
}
