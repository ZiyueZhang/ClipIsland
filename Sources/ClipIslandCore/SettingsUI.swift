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
    /// Fired after vault setup with the key alive: the coordinator runs the
    /// store migration, then (for removals) the model wipes vault metadata.
    public var onChangeVaultEnabled: ((Bool) -> Void)?
    public var onChangeVaultUnlocked: (() -> Void)?

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
    let vault = Vault.shared

    var accessibilityGranted = AutoPaster.isAccessibilityTrusted
    var screenCaptureGranted = CaptureService.hasScreenCapturePermission
    var loginItemStatus: SMAppService.Status = SMAppService.mainApp.status
    var loginItemError: String?

    // Vault form state
    var vaultEnabled = Vault.shared.isEnabled
    var vaultLocked = Vault.shared.state == .locked
    var newPassword = ""
    var confirmPassword = ""
    var currentPassword = ""
    var unlockPassword = ""
    var removePassword = ""
    var vaultError: String?
    var touchIDUsable = Vault.isTouchIDAvailable
    var touchIDOn = Vault.shared.metadata?.touchIDEnabled ?? false
    var autoLockMinutes = Vault.shared.metadata?.autoLockMinutes ?? 15

    init(settings: SettingsStore) {
        self.settings = settings
    }

    func refreshPermissions() {
        accessibilityGranted = AutoPaster.isAccessibilityTrusted
        screenCaptureGranted = CaptureService.hasScreenCapturePermission
        loginItemStatus = SMAppService.mainApp.status
        refreshVault()
    }

    func refreshVault() {
        vaultEnabled = vault.isEnabled
        vaultLocked = vault.state == .locked
        touchIDUsable = Vault.isTouchIDAvailable
        touchIDOn = vault.metadata?.touchIDEnabled ?? false
        autoLockMinutes = vault.metadata?.autoLockMinutes ?? 15
    }

    func enableVault() {
        do {
            try vault.setup(password: newPassword)
            vaultError = nil
            newPassword = ""
            confirmPassword = ""
            refreshVault()
            controller?.onChangeVaultEnabled?(true)
        } catch {
            vaultError = "启用失败：\(error)"
        }
    }

    func unlockVault() {
        do {
            try vault.unlock(password: unlockPassword)
            vaultError = nil
            unlockPassword = ""
            refreshVault()
            controller?.onChangeVaultUnlocked?()
        } catch {
            vaultError = "密码错误"
        }
    }

    func unlockVaultTouchID() {
        do {
            try vault.unlockTouchID()
            vaultError = nil
            refreshVault()
            controller?.onChangeVaultUnlocked?()
        } catch {
            vaultError = "触控 ID 失败：\(error)"
        }
    }

    func lockNow() {
        vault.lock()
        refreshVault()
    }

    func toggleTouchID(_ on: Bool) {
        do {
            on ? try vault.enableTouchID() : try vault.disableTouchID()
            vaultError = nil
        } catch {
            vaultError = "\(error)"
        }
        refreshVault()
    }

    func setAutoLock(_ minutes: Int) {
        do { try vault.setAutoLock(minutes: minutes) } catch { vaultError = "\(error)" }
        refreshVault()
    }

    func changePassword() {
        do {
            try vault.changePassword(current: currentPassword, new: newPassword)
            vaultError = nil
            currentPassword = ""
            newPassword = ""
            confirmPassword = ""
        } catch {
            vaultError = "更改失败：\(error)"
        }
    }

    func disableVault() {
        do {
            try vault.unlock(password: removePassword) // key alive for migration
            controller?.onChangeVaultEnabled?(false)   // store decrypts everything
            vault.wipeMetadata()                        // then the vault is removed
            vaultError = nil
            removePassword = ""
            refreshVault()
        } catch {
            vaultError = "移除失败：\(error)"
        }
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
            SecurityTab(model: model)
                .tabItem { Label("安全", systemImage: "lock.encrypted") }
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
                    title: "鼠标悬停刘海下方展开面板",
                    isOn: Binding(
                        get: { settings.expandOnHover },
                        set: { settings.expandOnHover = $0 }
                    )
                )
                Picker("动画风格", selection: Binding(
                    get: { settings.animationProfile },
                    set: { settings.animationProfile = $0 }
                )) {
                    Text("利落").tag("snappy")
                    Text("灵动").tag("bouncy")
                    Text("沉稳").tag("calm")
                }
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

private struct SecurityTab: View {
    let model: SettingsUIModel
    // Plain fields on a plain holder — the CLT toolchain cannot expand
    // SwiftUI @State/@Field macros; values live in the observable model.
    var body: some View {
        Form {
            if !model.vaultEnabled {
                Section("启用加密") {
                    SecureField("主密码（至少 4 位）", text: Binding(
                        get: { model.newPassword }, set: { model.newPassword = $0 }
                    ))
                    SecureField("确认密码", text: Binding(
                        get: { model.confirmPassword }, set: { model.confirmPassword = $0 }
                    ))
                    Button("启用加密保护") { model.enableVault() }
                        .disabled(model.newPassword.count < 4 || model.newPassword != model.confirmPassword)
                    Text("启用后历史内容（文本与图片）将以 AES-256-GCM 加密落盘，主密码经 PBKDF2（600,000 次迭代）派生密钥。已有条目会自动迁移。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Section("加密已启用") {
                    if model.vaultLocked {
                        Text("🔒 当前已锁定")
                            .foregroundStyle(.orange)
                        SecureField("主密码解锁", text: Binding(
                            get: { model.unlockPassword }, set: { model.unlockPassword = $0 }
                        ))
                        Button("解锁") { model.unlockVault() }
                        if model.touchIDUsable {
                            Button("用触控 ID 解锁") { model.unlockVaultTouchID() }
                        }
                    } else {
                        Text("✅ 已解锁（密钥在内存中）")
                            .foregroundStyle(.green)
                        Button("立即锁定") { model.lockNow() }
                        Toggle("用触控 ID 解锁", isOn: Binding(
                            get: { model.touchIDOn }, set: { model.toggleTouchID($0) }
                        ))
                        .disabled(!model.touchIDUsable)
                        Picker("自动锁定", selection: Binding(
                            get: { model.autoLockMinutes },
                            set: { model.setAutoLock($0) }
                        )) {
                            ForEach([1, 5, 15, 30, 60, 0], id: \.self) { n in
                                Text(n == 0 ? "从不" : "\(n) 分钟").tag(n)
                            }
                        }
                    }
                }
                Section("更改密码") {
                    SecureField("当前密码", text: Binding(
                        get: { model.currentPassword }, set: { model.currentPassword = $0 }
                    ))
                    SecureField("新密码", text: Binding(
                        get: { model.newPassword }, set: { model.newPassword = $0 }
                    ))
                    SecureField("确认新密码", text: Binding(
                        get: { model.confirmPassword }, set: { model.confirmPassword = $0 }
                    ))
                    Button("更改密码") { model.changePassword() }
                        .disabled(model.currentPassword.isEmpty || model.newPassword.count < 4 || model.newPassword != model.confirmPassword)
                }
                Section("移除加密") {
                    SecureField("当前密码", text: Binding(
                        get: { model.removePassword }, set: { model.removePassword = $0 }
                    ))
                    Button("移除加密并解密全部条目", role: .destructive) { model.disableVault() }
                        .disabled(model.removePassword.isEmpty)
                    Text("移除后所有条目解密回明文存储。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if let error = model.vaultError {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
    }
}

private struct HotkeyTab: View {
    let model: SettingsUIModel
    var settings: SettingsStore { model.settings }

    static let panelPresets = ["cmd+shift+v", "option+shift+v", "ctrl+shift+v", "cmd+shift+b"]
    static let shotPresets = ["cmd+shift+6", "cmd+shift+7", "option+shift+s", "ctrl+shift+6"]
    static let windowPresets = ["cmd+shift+7", "cmd+shift+8", "option+shift+w", "ctrl+shift+7"]

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
                Picker("窗口截图", selection: Binding(
                    get: { settings.windowCaptureHotkey },
                    set: {
                        settings.windowCaptureHotkey = $0
                        model.hotkeyChanged()
                    }
                )) {
                    ForEach(Self.windowPresets, id: \.self) { Text($0.replacingCombo).tag($0) }
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
