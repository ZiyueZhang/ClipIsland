import AppKit
import ServiceManagement
import SwiftUI

// MARK: - Controller

public final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let model: SettingsUIModel
    private var closed = false

    public var onChangeCapacity: ((Int) -> Void)?
    public var onChangeHotkeys: (() -> Void)?

    public init(settings: SettingsStore) {
        model = SettingsUIModel(settings: settings)
        super.init()
        model.controller = self
    }

    public func show() {
        closed = false
        if window == nil {
            let frame = NSRect(x: 0, y: 0, width: 480, height: 560)
            let win = NSWindow(
                contentRect: frame,
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            win.title = "ClipIsland 设置"
            win.isReleasedWhenClosed = false
            win.delegate = self
            win.contentView = NSHostingView(rootView: SettingsRootView(model: model))
            if let visible = NSScreen.main?.visibleFrame {
                win.setFrameOrigin(NSPoint(
                    x: visible.midX - frame.width / 2,
                    y: visible.midY - frame.height / 2
                ))
            }
            window = win
        }
        model.refreshPermissions()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    public func windowWillClose(_ notification: Notification) {
        guard !closed else { return }
        closed = true
        onclose?()
    }

    public var onclose: (() -> Void)?
}

// MARK: - Model

@Observable
final class SettingsUIModel {
    let settings: SettingsStore
    weak var controller: SettingsWindowController?

    var accessibilityGranted = AutoPaster.isAccessibilityTrusted
    var screenCaptureGranted = CaptureService.hasScreenCapturePermission
    var loginItemStatus: SMAppService.Status = SMAppService.mainApp.status
    var loginItemError: String?

    init(settings: SettingsStore) {
        self.settings = settings
    }

    func refreshPermissions() {
        accessibilityGranted = AutoPaster.isAccessibilityTrusted
        screenCaptureGranted = CaptureService.hasScreenCapturePermission
        loginItemStatus = SMAppService.mainApp.status
    }

    func toggleLaunchAtLogin(_ on: Bool) {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginItemError = nil
        } catch {
            loginItemError = "注册失败：请确认从 ClipIsland.app 启动（\(error.localizedDescription)）"
        }
        loginItemStatus = SMAppService.mainApp.status
    }

    func capacityChanged(_ value: Int) {
        settings.capacity = value
        controller?.onChangeCapacity?(value)
    }

    func hotkeyChanged() {
        controller?.onChangeHotkeys?()
    }

    func pickSaveDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowedContentTypes = []
        if panel.runModal() == .OK, let url = panel.url {
            settings.screenshotSaveDirectory = url.path
        }
    }

    func openAccessibilitySettings() {
        NSWorkspace.shared.open(
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        )
    }

    func openScreenCaptureSettings() {
        NSWorkspace.shared.open(
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        )
    }
}

// MARK: - Views

private struct SettingsRootView: View {
    let model: SettingsUIModel

    var body: some View {
        TabView {
            GeneralTab(model: model)
                .tabItem { Label("通用", systemImage: "gearshape") }
            HotkeyTab(model: model)
                .tabItem { Label("快捷键", systemImage: "keyboard") }
            PermissionsTab(model: model)
                .tabItem { Label("权限与关于", systemImage: "lock.shield") }
        }
        .padding(16)
        .frame(minWidth: 440, minHeight: 460)
    }
}

private struct GeneralTab: View {
    let model: SettingsUIModel
    var settings: SettingsStore { model.settings }

    var body: some View {
        Form {
            Section("启动") {
                toggle(
                    title: "开机自动启动",
                    isOn: Binding(
                        get: { model.loginItemStatus == .enabled },
                        set: { model.toggleLaunchAtLogin($0) }
                    )
                )
                if let err = model.loginItemError {
                    Text(err).font(.caption).foregroundStyle(.red)
                }
            }

            Section("剪贴板") {
                Picker("历史容量", selection: Binding(
                    get: { settings.capacity },
                    set: { model.capacityChanged($0) }
                )) {
                    ForEach([100, 200, 500, 1000, 2000], id: \.self) { n in
                        Text("\(n) 条").tag(n)
                    }
                }
                Picker("点击条目行为", selection: Binding(
                    get: { settings.autoPasteEnabled },
                    set: { settings.autoPasteEnabled = $0 }
                )) {
                    Text("复制并自动粘贴").tag(true)
                    Text("仅复制").tag(false)
                }
                toggle(
                    title: "鼠标悬停刘海展开面板",
                    isOn: Binding(
                        get: { settings.expandOnHover },
                        set: { settings.expandOnHover = $0 }
                    )
                )
            }

            Section("截图") {
                toggle(
                    title: "截图后自动保存文件",
                    isOn: Binding(
                        get: { settings.saveScreenshotsToFile },
                        set: { settings.saveScreenshotsToFile = $0 }
                    )
                )
                HStack {
                    Text("保存目录")
                    Spacer()
                    Text(settings.screenshotSaveDirectory)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: 200)
                    Button("修改…") { model.pickSaveDirectory() }
                }
                toggle(
                    title: "截图后打开编辑器",
                    isOn: Binding(
                        get: { settings.openEditorAfterCapture },
                        set: { settings.openEditorAfterCapture = $0 }
                    )
                )
            }
        }
        .formStyle(.grouped)
    }

    private func toggle(title: String, isOn: Binding<Bool>) -> some View {
        Toggle(title, isOn: isOn)
    }
}

private struct HotkeyTab: View {
    let model: SettingsUIModel
    var settings: SettingsStore { model.settings }

    static let panelPresets = ["cmd+shift+v", "option+shift+v", "ctrl+shift+v", "cmd+shift+b"]
    static let shotPresets = ["cmd+shift+6", "cmd+shift+7", "option+shift+s", "ctrl+shift+6"]

    var body: some View {
        Form {
            Section("面板") {
                Picker("呼出剪贴板面板", selection: Binding(
                    get: { settings.panelHotkey },
                    set: {
                        settings.panelHotkey = $0
                        model.hotkeyChanged()
                    }
                )) {
                    ForEach(Self.panelPresets, id: \.self) { Text($0.replacingCombo).tag($0) }
                }
            }
            Section("截图") {
                Picker("区域截图", selection: Binding(
                    get: { settings.screenshotHotkey },
                    set: {
                        settings.screenshotHotkey = $0
                        model.hotkeyChanged()
                    }
                )) {
                    ForEach(Self.shotPresets, id: \.self) { Text($0.replacingCombo).tag($0) }
                }
            }
        }
        .formStyle(.grouped)
    }
}

private extension String {
    var replacingCombo: String {
        replacingOccurrences(of: "cmd", with: "⌘")
            .replacingOccurrences(of: "shift", with: "⇧")
            .replacingOccurrences(of: "option", with: "⌥")
            .replacingOccurrences(of: "ctrl", with: "⌃")
            .replacingOccurrences(of: "+", with: "")
    }
}

private struct PermissionsTab: View {
    let model: SettingsUIModel

    var body: some View {
        Form {
            Section("权限") {
                permissionRow(
                    granted: model.accessibilityGranted,
                    title: "辅助功能（自动粘贴）",
                    open: { model.openAccessibilitySettings() }
                )
                permissionRow(
                    granted: model.screenCaptureGranted,
                    title: "屏幕录制（截图）",
                    open: { model.openScreenCaptureSettings() }
                )
                Button("刷新状态") { model.refreshPermissions() }
            }
            Section("关于") {
                LabeledContent("版本", value: "1.0.0")
                LabeledContent("数据目录", value: "~/Library/Application Support/ClipIsland")
                Text("剪贴板监控、截图与编辑全部在本机完成，不联网。密码管理器标记的敏感内容会自动跳过。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func permissionRow(granted: Bool, title: String, open: @escaping () -> Void) -> some View {
        HStack {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(granted ? Color.green : Color.orange)
            Text(title)
            Spacer()
            if !granted {
                Button("去授权", action: open)
            }
        }
    }
}
