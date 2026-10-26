import SwiftUI

// MARK: - Root

struct NotchRootView: View {
    let model: NotchModel
    let info: NotchDisplayInfo

    var body: some View {
        ZStack {
            if model.phase == .collapsed {
                CollapsedStrip(model: model, info: info)
                    .transition(.opacity)
            } else {
                ExpandedPanel(model: model, info: info)
                    .transition(.opacity)
            }
        }
        .onHover { model.setHover(inside: $0) }
        .animation(.spring(response: 0.38, dampingFraction: 0.82), value: model.phase)
    }
}

// MARK: - Collapsed strip

struct CollapsedStrip: View {
    let model: NotchModel
    let info: NotchDisplayInfo

    var body: some View {
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
            .background(StripShape(hasRealNotch: info.hasRealNotch).fill(Color.black))
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
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: model.hangingImage != nil)
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
        f.setLocalizedDateFormatFromTemplate("Mdw")
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
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
        .lineLimit(1)
    }
}

/// Capsule on non-notch Macs; on real-notch Macs the window already matches
/// the notch shape, so a plain rectangle with slightly rounded corners blends in.
struct StripShape: Shape {
    let hasRealNotch: Bool

    func path(in rect: CGRect) -> Path {
        if hasRealNotch {
            UnevenRoundedRectangle(
                topLeadingRadius: 10, bottomLeadingRadius: 12,
                bottomTrailingRadius: 12, topTrailingRadius: 10
            )
            .path(in: rect)
        } else {
            Capsule().path(in: rect)
        }
    }
}

// MARK: - Expanded panel

struct ExpandedPanel: View {
    let model: NotchModel
    let info: NotchDisplayInfo

    var body: some View {
        VStack(spacing: 0) {
            Color.black.frame(height: info.headerHeight)
            PanelContent(model: model)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            ZStack {
                VisualEffectView(material: .hudWindow)
                UnevenRoundedRectangle(
                    topLeadingRadius: 18, bottomLeadingRadius: 22,
                    bottomTrailingRadius: 22, topTrailingRadius: 18
                )
                .stroke(.white.opacity(0.10), lineWidth: 1)
            }
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: 18, bottomLeadingRadius: 22,
                    bottomTrailingRadius: 22, topTrailingRadius: 18
                )
            )
        )
        .shadow(color: .black.opacity(0.4), radius: 28, y: 14)
    }
}

private struct PanelContent: View {
    let model: NotchModel

    var body: some View {
        VStack(spacing: 10) {
            SearchFieldView(model: model)
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
        .padding(14)
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
        super.keyDown(with: event)
    }
}

struct SearchFieldView: NSViewRepresentable {
    let model: NotchModel

    func makeNSView(context: Context) -> PanelSearchField {
        let field = PanelSearchField()
        field.placeholderString = "搜索剪贴板…"
        field.font = .systemFont(ofSize: 13)
        field.focusRingType = .none
        field.bezelStyle = .roundedBezel
        field.isBordered = false
        field.drawsBackground = false
        field.textColor = .labelColor
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
                        ? Color.accentColor.opacity(0.9)
                        : Color.primary.opacity(0.08)
                )
            )
            .foregroundStyle(selected ? Color.white : Color.secondary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: Results list

private struct ResultList: View {
    let model: NotchModel

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
                        .id(item.id)
                        .onTapGesture { model.onSelectItem?(item) }
                    }
                }
                .padding(.vertical, 2)
            }
            .overlay(alignment: .trailing) {
                ScrollViewIndicator(model: model)
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
/// observing the cache re-render when a load completes. (No @State: the CLT
/// toolchain cannot expand SwiftUI macros.)
@Observable
final class ThumbnailCache {
    static let shared = ThumbnailCache()

    private let store = NSCache<NSString, NSImage>()
    private var inflight: Set<String> = []
    private(set) var version = 0

    func thumbnail(for item: ClipItem) -> NSImage? {
        guard let path = item.imagePath else { return nil }
        if let hit = store.object(forKey: path as NSString) { return hit }
        guard !inflight.contains(path) else { return nil }
        inflight.insert(path)
        DispatchQueue.global(qos: .userInitiated).async {
            let image = item.loadImage()
            DispatchQueue.main.async {
                if let image {
                    self.store.setObject(image, forKey: path as NSString)
                }
                self.inflight.remove(path)
                self.version += 1
            }
        }
        return nil
    }
}

private struct ScrollViewIndicator: View {
    let model: NotchModel

    var body: some View {
        VStack {
            ForEach(0..<max(model.results.count, 1), id: \.self) { i in
                Capsule()
                    .fill(i == model.selectedIndex ? Color.accentColor : Color.secondary.opacity(0.2))
                    .frame(width: 3, height: 5)
            }
        }
        .padding(.trailing, 4)
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
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(width: 16, height: 16)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.08)))
            } else {
                Color.clear.frame(width: 16, height: 16)
            }

            Image(systemName: item.kind.symbolName)
                .font(.system(size: 12))
                .foregroundStyle(Color.secondary)
                .frame(width: 16)

            if item.kind == .image {
                ThumbnailView(item: item, cache: thumbnails)
                    .frame(width: 34, height: 34)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            }

            Text(item.displayText)
                .font(.system(size: 12))
                .lineLimit(2)
                .truncationMode(.tail)
                .foregroundStyle(Color.primary.opacity(0.9))

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
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
                if let app = item.sourceName {
                    Text(app)
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            .frame(width: 64, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(selected ? Color.accentColor.opacity(0.16) : (hovered ? Color.primary.opacity(0.05) : .clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(selected ? Color.accentColor.opacity(0.35) : .clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onHover { onHover($0) }
    }

    private func rowButton(symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .frame(width: 18, height: 18)
                .background(Circle().fill(Color.primary.opacity(0.08)))
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
                .foregroundStyle(.tertiary)
            Text(query.isEmpty ? "剪贴板历史为空\n复制点什么吧" : "没有匹配的结果")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
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
            hint("Esc", "收起")
            Spacer()
            Text(model.paused ? "监控已暂停" : "监控中 · \(model.clipCount) 条")
                .font(.system(size: 10))
                .foregroundStyle(model.paused ? Color.orange : Color.secondary)
        }
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.system(size: 9, weight: .medium))
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.08)))
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
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
