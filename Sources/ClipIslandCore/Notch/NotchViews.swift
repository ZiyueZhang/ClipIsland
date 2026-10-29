import SwiftUI

// MARK: - Root

/// macOS-style "materialize": incoming content condenses from a soft blur
/// slightly below its final position (Sapphire's blur cross-fade).
struct MaterializeModifier: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        content
            .blur(radius: active ? 8 : 0)
            .scaleEffect(active ? 0.985 : 1)
            .offset(y: active ? 10 : 0)
            .opacity(active ? 0 : 1)
    }
}

extension AnyTransition {
    static var materialize: AnyTransition {
        .modifier(
            active: MaterializeModifier(active: true),
            identity: MaterializeModifier(active: false)
        )
    }
}

/// A screenshot "clipping onto the line": drops in from slightly above with
/// a small counter-clockwise tilt; the spring overshoot settles the tilt.
struct HangClipModifier: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        content
            .scaleEffect(active ? 0.6 : 1)
            .rotationEffect(.degrees(active ? -3 : 0))
            .offset(y: active ? -8 : 0)
            .opacity(active ? 0 : 1)
    }
}

extension AnyTransition {
    static var hangClip: AnyTransition {
        .modifier(active: HangClipModifier(active: true), identity: HangClipModifier(active: false))
    }
}

struct NotchRootView: View {
    let model: NotchModel
    let info: NotchDisplayInfo

    var body: some View {
        ZStack {
            if model.phase == .collapsed {
                CollapsedStrip(model: model, info: info)
                    .transition(.materialize)
            } else {
                ExpandedPanel(model: model, info: info)
                    .transition(.materialize)
            }
        }
        .onHover { inside in
            model.hoverInside = inside
            model.setHover(inside: inside)
        }
        .animation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.8), value: model.phase)
    }
}

// MARK: - Collapsed strip

public struct CollapsedStrip: View {
    let model: NotchModel
    let info: NotchDisplayInfo

    public init(model: NotchModel, info: NotchDisplayInfo) {
        self.model = model
        self.info = info
    }

    public var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 0) {
                LeftIslandText()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 16)
                RightIslandText(model: model)
                    .padding(.trailing, 16)
            }
            .frame(height: info.headerHeight)
            .frame(maxWidth: .infinity)
            .background(StripShape(hasRealNotch: info.hasRealNotch, topRadius: model.cornerTop, bottomRadius: model.cornerBottom).fill(Color.black))
        .scaleEffect(model.hoverInside && model.phase == .collapsed ? 1.02 : 1)
            .contentShape(Rectangle())
            .onTapGesture { model.toggle() }

            if let image = model.hangingImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(.white.opacity(0.18), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.45), radius: 10, y: 5)
                    .transition(.hangClip)
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.75), value: model.hangingImage != nil)
    }
}

private struct LeftIslandText: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { timeline in
            let date = timeline.date
            HStack(spacing: 8) {
                Text(Self.clock.string(from: date))
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(Self.day.string(from: date))
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(.white.opacity(0.55))
            }
            .foregroundStyle(.white)
            .lineLimit(1)
        }
    }

    static let clock: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()
    static let day: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日 EEE"
        return f
    }()
}

private struct RightIslandText: View {
    let model: NotchModel

    var body: some View {
        HStack(spacing: 6) {
            if model.paused {
                Image(systemName: "pause.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.6))
            } else {
                Image(systemName: "doc.on.doc.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.75))
                Text("\(model.clipCount)")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(.white.opacity(0.9))
                    .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.8), value: model.clipCount)
            }
        }
        .lineLimit(1)
    }
}

/// Notch silhouette after boring.notch's NotchShape: the top edge stays
/// nearly square (it fuses with the screen top), the bottom carries the
/// larger radius that reads as "hardware". On non-notch Macs the same shape
/// reads as a floating pill.
public struct StripShape: Shape {
    let hasRealNotch: Bool
    let topRadius: CGFloat
    let bottomRadius: CGFloat

    public init(hasRealNotch: Bool, topRadius: CGFloat = 6, bottomRadius: CGFloat = 14) {
        self.hasRealNotch = hasRealNotch
        self.topRadius = topRadius
        self.bottomRadius = bottomRadius
    }

    public func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + topRadius, y: rect.minY + topRadius),
            control: CGPoint(x: rect.minX + topRadius, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.minX + topRadius, y: rect.maxY - bottomRadius))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + topRadius + bottomRadius, y: rect.maxY),
            control: CGPoint(x: rect.minX + topRadius, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - topRadius - bottomRadius, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - topRadius, y: rect.maxY - bottomRadius),
            control: CGPoint(x: rect.maxX - topRadius, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - topRadius, y: rect.minY + topRadius))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.maxX - topRadius, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        return path
    }
}

// MARK: - Expanded panel

public struct ExpandedPanel: View {
    let model: NotchModel
    let info: NotchDisplayInfo

    public init(model: NotchModel, info: NotchDisplayInfo) {
        self.model = model
        self.info = info
    }

    public var body: some View {
        VStack(spacing: 0) {
            Color.black.frame(height: info.headerHeight)
            if model.vaultLocked {
                LockScreenView(model: model)
            } else {
                PanelContent(model: model)
            }
        }
        .scaleEffect(model.phase == .expanded && !reduceMotion ? 1.0 : 0.97)
        .opacity(model.phase == .expanded || reduceMotion ? 1.0 : 0.6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Solid black monolith: the notch appears to grow downward
        // (boring.notch's aesthetic — and it fuses with the strip perfectly).
        .background(Color.black)
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: model.cornerTop, bottomLeadingRadius: model.cornerBottom,
                bottomTrailingRadius: model.cornerBottom, topTrailingRadius: model.cornerTop
            )
        )
        .overlay(
            UnevenRoundedRectangle(
                topLeadingRadius: model.cornerTop, bottomLeadingRadius: model.cornerBottom,
                bottomTrailingRadius: model.cornerBottom, topTrailingRadius: model.cornerTop
            )
            .stroke(.white.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.45), radius: 26, y: 12)
    }
}

private struct PanelContent: View {
    let model: NotchModel

    var body: some View {
        VStack(spacing: 10) {
            SearchFieldView(model: model)
                .padding(.leading, 28)
                .background(
                    RoundedRectangle(cornerRadius: 9)
                        .fill(Color.white.opacity(0.08))
                )
                .overlay(alignment: .leading) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                        .padding(.leading, 10)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(Color.white.opacity(0.10))
                )
            FilterChips(model: model)

            if model.showAccessibilityHint {
                AccessibilityHint(model: model)
            }

            if model.results.isEmpty {
                EmptyState(query: model.query)
            } else {
                ResultList(model: model)
            }

            FooterBar(model: model)
        }
        .padding(12)
        .padding(.bottom, 2)
        .onAppear { model.reloadResults() }
    }
}

// MARK: Search field

/// NSTextField subclass so IME (中文输入) works while arrows/enter/escape and
/// empty-query digits are routed to the model.
final class PanelSearchField: NSTextField {
    var onSpecialKey: ((NotchModel.SpecialKey) -> Void)?

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let plain = flags.isEmpty || flags == .shift
        if plain, event.keyCode == 53 {
            onSpecialKey?(.escape)
            return
        }
        switch event.specialKey {
        case .downArrow where plain:
            onSpecialKey?(.down)
            return
        case .upArrow where plain:
            onSpecialKey?(.up)
            return
        case .carriageReturn where plain:
            onSpecialKey?(.enter)
            return
        default:
            break
        }
        if plain, event.keyCode == 76 {
            onSpecialKey?(.enter)
            return
        }
        if plain, stringValue.isEmpty,
           let c = event.charactersIgnoringModifiers, c.count == 1,
           let d = Int(c), (1...9).contains(d) {
            onSpecialKey?(.digit(d))
            return
        }
        if plain, stringValue.isEmpty, event.keyCode == 49 {
            onSpecialKey?(.quickLook) // space previews the selection
            return
        }
        super.keyDown(with: event)
    }
}

struct SearchFieldView: NSViewRepresentable {
    let model: NotchModel

    func makeNSView(context: Context) -> PanelSearchField {
        let field = PanelSearchField()
        field.placeholderAttributedString = NSAttributedString(
            string: "搜索剪贴板…",
            attributes: [
                .foregroundColor: NSColor.white.withAlphaComponent(0.35),
                .font: NSFont.systemFont(ofSize: 13),
            ]
        )
        field.font = .systemFont(ofSize: 13)
        field.focusRingType = .none
        field.bezelStyle = .roundedBezel
        field.isBordered = false
        field.drawsBackground = false
        field.textColor = .white

        field.stringValue = model.query
        field.onSpecialKey = { [weak model] key in
            model?.handleSpecial(key)
        }
        field.delegate = context.coordinator
        context.coordinator.field = field
        return field
    }

    func updateNSView(_ field: PanelSearchField, context: Context) {
        if field.stringValue != model.query {
            field.stringValue = model.query
        }
        field.onSpecialKey = { [weak model] key in
            model?.handleSpecial(key)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        let model: NotchModel
        weak var field: PanelSearchField?

        init(model: NotchModel) {
            self.model = model
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field else { return }
            model.query = field.stringValue
            model.reloadResults()
        }
    }
}

// MARK: Filter chips

private struct FilterChips: View {
    let model: NotchModel

    var body: some View {
        HStack(spacing: 6) {
            chip(nil, label: "全部", symbol: "square.grid.2x2")
            ForEach(ClipKind.allCases, id: \.self) { kind in
                chip(kind, label: kind.label, symbol: kind.symbolName)
            }
            Spacer()
        }
    }

    private func chip(_ kind: ClipKind?, label: String, symbol: String) -> some View {
        let selected = model.kindFilter == kind
        return Button {
            model.kindFilter = kind
            model.selectedIndex = 0
            model.reloadResults()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 9))
                Text(label).font(.system(size: 11))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(
                    selected
                        ? Color.accentColor
                        : Color.white.opacity(0.08)
                )
            )
            .foregroundStyle(selected ? Color.white : Color.white.opacity(0.65))
        }
        .buttonStyle(.plain)
    }
}

// MARK: Results list

private struct ResultList: View {
    let model: NotchModel
    @Namespace private var selectionNS

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    let targets = model.digitTargets
                    ForEach(Array(model.results.enumerated()), id: \.element.id) { index, item in
                        ClipRow(
                            item: item,
                            digit: index < targets.count && targets[index].id == item.id ? index + 1 : nil,
                            selected: index == model.selectedIndex,
                            hovered: model.hoveredItemID == item.id,
                            thumbnails: .shared,
                            onSelect: { model.onSelectItem?(item) },
                            onTogglePin: { model.onTogglePin?(item) },
                            onDelete: { model.onDeleteItem?(item) },
                            onEdit: item.kind == .image ? { model.onEditItem?(item) } : nil,
                            onOCR: item.kind == .image ? { model.onOCRItem?(item) } : nil,
                            onHover: { inside in
                                model.hoveredItemID = inside ? item.id : nil
                            }
                        )
                        // The selection highlight is a single view that
                        // glides between rows (System Settings sidebar style).
                        .background {
                            if index == model.selectedIndex {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.accentColor.opacity(0.16))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color.accentColor.opacity(0.35), lineWidth: 1)
                                    )
                                    .matchedGeometryEffect(id: "selection", in: selectionNS)
                            }
                        }
                        .id(item.id)
                        .onTapGesture { model.onSelectItem?(item) }
                        .onDrag { model.dragProvider?(item) ?? ClipRow.dragProvider(for: item) }
                    }
                }
                .padding(.vertical, 2)
                .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.85), value: model.selectedIndex)
            }
            .onChange(of: model.selectedIndex) { _, newValue in
                guard model.results.indices.contains(newValue) else { return }
                withAnimation(.easeOut(duration: 0.12)) {
                    proxy.scrollTo(model.results[newValue].id, anchor: .center)
                }
            }
        }
    }
}

/// Async thumbnail loading with NSCache storage; `version` bumps so views
/// observing the cache re-render when a load completes. Thumbnails are
/// decoded at thumbnail size via ImageIO — a 3000×2000 screenshot costs
/// ~74KB of resident bitmap instead of ~24MB of full-resolution decode.
@Observable
public final class ThumbnailCache {
    static let shared = ThumbnailCache()

    /// List thumbs render at 34pt; 136px covers 34pt @4x with headroom.
    static let maxPixel: Int = 136

    private let store = NSCache<NSString, NSImage>()
    private var inflight: Set<String> = []
    private(set) var version = 0

    /// Set by the coordinator to route decodes through the vault
    /// (decrypt-to-thumbnail without materializing the full bitmap).
    public static var storeLoader: ((ClipItem) -> NSImage?)?

    func thumbnail(for item: ClipItem) -> NSImage? {
        guard let path = item.imagePath else { return nil }
        if let hit = store.object(forKey: path as NSString) { return hit }
        guard !inflight.contains(path) else { return nil }
        inflight.insert(path)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let image = Self.storeLoader?(item) ?? Self.downsampled(path: path, maxPixel: Self.maxPixel)
            DispatchQueue.main.async {
                if let image {
                    self?.store.setObject(image, forKey: path as NSString)
                }
                self?.inflight.remove(path)
                self?.version += 1
            }
        }
        return nil
    }

    /// Decodes a downscaled thumbnail straight off the decoder — never
    /// materializes the full-resolution bitmap.
    public static func downsampled(path: String, maxPixel: Int) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }
}

struct ClipRow: View {
    let item: ClipItem
    let digit: Int?
    let selected: Bool
    let hovered: Bool
    let thumbnails: ThumbnailCache
    let onSelect: () -> Void
    let onTogglePin: () -> Void
    let onDelete: () -> Void
    let onEdit: (() -> Void)?
    let onOCR: (() -> Void)?
    let onHover: (Bool) -> Void

    var body: some View {
        HStack(spacing: 10) {
            if let digit {
                Text("\(digit)")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(width: 18, height: 18)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.09)))
            } else {
                Color.clear.frame(width: 18, height: 18)
            }

            Image(systemName: item.kind.symbolName)
                .font(.system(size: 12))
                .foregroundStyle(Color.white.opacity(0.45))
                .frame(width: 16)

            if item.kind == .image {
                ThumbnailView(item: item, cache: thumbnails)
                    .frame(width: 34, height: 34)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            }

            Text(item.displayText)
                .font(.system(size: 12.5))
                .lineLimit(2)
                .truncationMode(.tail)
                .foregroundStyle(Color.white.opacity(0.92))

            Spacer(minLength: 4)

            if hovered {
                rowButton(symbol: item.pinned ? "pin.fill" : "pin", action: onTogglePin)
                    .help(item.pinned ? "取消置顶" : "置顶")
                if let onEdit {
                    rowButton(symbol: "wand.and.stars", action: onEdit)
                        .help("编辑")
                }
                if let onOCR {
                    rowButton(symbol: "text.viewfinder", action: onOCR)
                        .help("识别文字")
                }
                rowButton(symbol: "trash", action: onDelete)
                    .help("删除")
            } else if item.pinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(Color.orange.opacity(0.8))
            }

            VStack(alignment: .trailing, spacing: 2) {
                Text(TimeFormat.relative(item.createdAt))
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.4))
                    .monospacedDigit()
                if let app = item.sourceName {
                    Text(app)
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.3))
                        .lineLimit(1)
                }
            }
            .frame(width: 64, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(hovered ? Color.white.opacity(0.06) : .clear)
                .animation(.easeOut(duration: 0.12), value: hovered)
        )
        .contentShape(Rectangle())
        .onHover { onHover($0) }
    }

    /// Drag payload: images/files drag their file URL (vault-decrypted temp
    /// via the coordinator when sealed), text/link drag their string.
    static func dragProvider(for item: ClipItem) -> NSItemProvider {
        switch item.kind {
        case .image:
            if let path = item.imagePath, !item.redacted {
                return NSItemProvider(object: URL(fileURLWithPath: path) as NSURL)
            }
            return NSItemProvider()
        case .file:
            let first = (item.text ?? "").split(separator: "\n").first.map(String.init) ?? ""
            return NSItemProvider(object: URL(fileURLWithPath: first) as NSURL)
        case .text, .link:
            return NSItemProvider(object: (item.redacted ? "" : item.text ?? "") as NSString)
        }
    }

    private func rowButton(symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 18, height: 18)
                .background(Circle().fill(Color.white.opacity(0.10)))
        }
        .buttonStyle(.plain)
    }
}

private struct ThumbnailView: View {
    let item: ClipItem
    let cache: ThumbnailCache

    var body: some View {
        Group {
            if let image = cache.thumbnail(for: item) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Color.primary.opacity(0.06)
            }
        }
    }
}

// MARK: Empty state / footer / hints

private struct EmptyState: View {
    let query: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: query.isEmpty ? "clipboard" : "magnifyingglass")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.white.opacity(0.25))
            Text(query.isEmpty ? "剪贴板历史为空\n复制点什么吧" : "没有匹配的结果")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.45))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct FooterBar: View {
    let model: NotchModel

    var body: some View {
        HStack(spacing: 12) {
            hint("↑↓", "选择")
            hint("⏎", "粘贴")
            hint("1-9", "直选")
            hint("空格", "预览")
            hint("Esc", "收起")
            Spacer()
            Text(model.paused ? "监控已暂停" : "监控中 · \(model.clipCount) 条")
                .font(.system(size: 10))
                .foregroundStyle(model.paused ? Color.orange : Color.white.opacity(0.45))
        }
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 5) {
            Text(key)
                .font(.system(size: 9, weight: .semibold))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.10))
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.white.opacity(0.10)))
                )
                .foregroundStyle(.white.opacity(0.75))
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.45))
        }
    }
}

private struct AccessibilityHint: View {
    let model: NotchModel

    var body: some View {
        Button {
            model.onOpenAccessibilitySettings?()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
                Text("未授权辅助功能：已复制但不会自动粘贴，点击前往授权")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.08)))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.orange.opacity(0.2)))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Lock screen

private struct LockScreenView: View {
    let model: NotchModel

    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.secondary)
            Text("剪贴板历史已加密")
                .font(.system(size: 13, weight: .semibold))
            if model.vaultPendingCount > 0 {
                Text("锁定期间已缓冲 \(model.vaultPendingCount) 条新捕获，解锁后入列")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
            }
            HStack(spacing: 8) {
                SecureField(
                    "主密码",
                    text: Binding(
                        get: { model.vaultPasswordField },
                        set: { model.vaultPasswordField = $0 }
                    ),
                    onCommit: { submit() }
                )
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)
                Button("解锁") { submit() }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.vaultPasswordField.isEmpty)
            }
            if let error = model.vaultUnlockError {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
            }
            if model.vaultTouchIDEnabled && model.vaultTouchIDAvailable {
                Button {
                    model.onVaultUnlockTouchID?()
                } label: {
                    Label("用触控 ID 解锁", systemImage: "touchid")
                        .font(.system(size: 12))
                }
                .buttonStyle(.bordered)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(16)
    }

    private func submit() {
        guard !model.vaultPasswordField.isEmpty else { return }
        model.onVaultUnlockPassword?(model.vaultPasswordField)
        model.vaultPasswordField = ""
    }
}

// MARK: - Surface (Liquid Glass on macOS 26+, vibrancy fallback)

/// The expanded panel's material. On macOS 26+ this is the real system
/// Liquid Glass (NSGlassEffectView, Sapphire's choice); corner radius follows
/// the model so the glass morphs in lockstep with the window frame.
struct PanelSurface: NSViewRepresentable {
    let model: NotchModel

    /// Glass is always rendered with a dark appearance (Sapphire's approach):
    /// the panel content is light-on-dark, and glass would otherwise follow
    /// the wallpaper and wash the text out on bright backgrounds. Set
    /// CLIPISLAND_NO_GLASS=1 to force the vibrancy fallback (also used by the
    /// offscreen renderer, where glass has no backdrop to sample).
    func makeNSView(context: Context) -> NSView {
        if #available(macOS 26.0, *), ProcessInfo.processInfo.environment["CLIPISLAND_NO_GLASS"] != "1" {
            let glass = NSGlassEffectView()
            glass.style = .regular
            glass.tintColor = NSColor.black.withAlphaComponent(0.22)
            glass.cornerRadius = model.cornerBottom
            glass.appearance = NSAppearance(named: .darkAqua)
            if #available(macOS 27.0, *) {
                glass.effectIsInteractive = true
            }
            return glass
        }
        let v = NSVisualEffectView()
        v.material = .hudWindow
        v.blendingMode = .behindWindow
        v.state = .active
        v.appearance = NSAppearance(named: .darkAqua)
        return v
    }

    func updateNSView(_ view: NSView, context: Context) {
        if #available(macOS 26.0, *), let glass = view as? NSGlassEffectView {
            glass.cornerRadius = model.cornerBottom
        }
    }
}

// MARK: - Vibrancy wrapper

struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
    }
}
