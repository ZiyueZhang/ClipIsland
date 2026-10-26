import Foundation

/// UserDefaults-backed app settings. Written from the settings UI, read by
/// the monitor / paster / screenshot modules.
public final class SettingsStore {
    public static let shared = SettingsStore()

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var capacity: Int {
        get { defaults.object(forKey: "capacity") as? Int ?? 500 }
        set { defaults.set(newValue, forKey: "capacity") }
    }

    public var autoPasteEnabled: Bool {
        get { defaults.object(forKey: "autoPasteEnabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "autoPasteEnabled") }
    }

    public var paused: Bool {
        get { defaults.bool(forKey: "monitorPaused") }
        set { defaults.set(newValue, forKey: "monitorPaused") }
    }

    public var expandOnHover: Bool {
        get { defaults.object(forKey: "expandOnHover") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "expandOnHover") }
    }

    public var saveScreenshotsToFile: Bool {
        get { defaults.object(forKey: "saveScreenshotsToFile") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "saveScreenshotsToFile") }
    }

    public var openEditorAfterCapture: Bool {
        get { defaults.object(forKey: "openEditorAfterCapture") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "openEditorAfterCapture") }
    }

    public var screenshotSaveDirectory: String {
        get {
            defaults.string(forKey: "screenshotSaveDirectory")
                ?? picturesDirectoryURL().path
        }
        set { defaults.set(newValue, forKey: "screenshotSaveDirectory") }
    }

    /// Combo strings like "cmd+shift+v". Parsed by HotkeyManager.
    public var panelHotkey: String {
        get { defaults.string(forKey: "panelHotkey") ?? "cmd+shift+v" }
        set { defaults.set(newValue, forKey: "panelHotkey") }
    }

    public var screenshotHotkey: String {
        get { defaults.string(forKey: "screenshotHotkey") ?? "cmd+shift+6" }
        set { defaults.set(newValue, forKey: "screenshotHotkey") }
    }

    public func picturesDirectoryURL() -> URL {
        FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ClipIsland", isDirectory: true)
    }
}
