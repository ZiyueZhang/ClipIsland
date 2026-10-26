import SwiftUI

// MARK: - Root

struct EditorRootView: View {
    let model: EditorModel

    var body: some View {
        VStack(spacing: 0) {
            EditorToolbar(model: model)
            Divider()
            EditorCanvas(model: model)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            EditorStatusBar(model: model)
        }
        .frame(minWidth: 520, minHeight: 380)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - Toolbar

private struct EditorToolbar: View {
    let model: EditorModel

    static let colors: [NSColor] = [
        .systemRed, .systemOrange, .systemYellow, .systemGreen,
        .systemBlue, .systemPurple, .black, .white,
    ]

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 2) {
                ForEach(EditorModel.Tool.allCases) { tool in
                    toolButton(tool)
                }
            }
            Divider().frame(height: 18)
            HStack(spacing: 4) {
                ForEach(Self.colors, id: \.description) { color in
                    colorButton(color)
                }
            }
            if model.tool == .pen || model.tool == .rectangle || model.tool == .ellipse || model.tool == .arrow {
                Picker("", selection: Binding(
                    get: { model.strokeWidth },
                    set: { model.strokeWidth = $0; model.invalidate() }
                )) {
                    Text("细").tag(CGFloat(2))
                    Text("中").tag(CGFloat(4))
                    Text("粗").tag(CGFloat(8))
                }
                .pickerStyle(.segmented)
                .frame(width: 110)
            }
            if model.tool == .text {
                Picker("", selection: Binding(
                    get: { model.fontSize },
                    set: { model.fontSize = $0; model.invalidate() }
                )) {
                    Text("小").tag(CGFloat(16))
                    Text("中").tag(CGFloat(24))
                    Text("大").tag(CGFloat(36))
                }
                .pickerStyle(.segmented)
                .frame(width: 110)
            }
            Divider().frame(height: 18)
            if model.cropRect != nil {
                Button("应用裁剪") { model.applyCrop() }
                    .controlSize(.small)
            }
            Button {
                model.undo()
            } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .disabled(!model.canUndo)
            .help("撤销 ⌘Z")
            Button {
                model.redo()
            } label: {
                Image(systemName: "arrow.uturn.forward")
            }
            .disabled(!model.canRedo)
            .help("重做 ⇧⌘Z")
            if model.selectedAnnotationID != nil {
                Button {
                    model.deleteSelected()
                } label: {
                    Image(systemName: "trash")
                }
                .help("删除所选 (⌫)")
            }

            Button {
                model.ocrRequest?()
            } label: {
                Image(systemName: "text.viewfinder")
            }
            .help("识别文字 (OCR)")

            Spacer()
            Button("复制") { model.exportAction?(.copy) }
                .controlSize(.small)
            Button("保存") { model.exportAction?(.save) }
                .controlSize(.small)
            Button("完成") { model.exportAction?(.done) }
                .controlSize(.small)
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private func toolButton(_ tool: EditorModel.Tool) -> some View {
        let selected = model.tool == tool
        return Button {
            model.commitTextEditingIfNeeded()
            model.tool = tool
        } label: {
            VStack(spacing: 1) {
                Image(systemName: tool.symbolName)
                    .font(.system(size: 13))
                Text(tool.rawValue)
                    .font(.system(size: 8))
            }
            .frame(width: 38, height: 34)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(selected ? Color.accentColor.opacity(0.22) : .clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(selected ? Color.accentColor : .clear)
            )
        }
        .buttonStyle(.plain)
        .help(tool.rawValue)
    }

    private func colorButton(_ color: NSColor) -> some View {
        let selected = color.description == model.strokeColor.description
        return Button {
            model.strokeColor = color
            if let id = model.selectedAnnotationID,
               let idx = model.annotations.firstIndex(where: { $0.id == id }) {
                model.updateAnnotation(at: idx) { $0.color = color }
            }
        } label: {
            Circle()
                .fill(Color(nsColor: color))
                .frame(width: 14, height: 14)
                .overlay(Circle().stroke(.primary.opacity(0.25), lineWidth: 0.8))
                .overlay(
                    Circle().stroke(Color.blue, lineWidth: selected ? 2 : 0)
                        .padding(-2)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Canvas

private struct EditorCanvas: View {
    let model: EditorModel

    var body: some View {
        GeometryReader { geo in
            let fit = fitRect(in: geo.size)
            ZStack(alignment: .topLeading) {
                Color(nsColor: .underPageBackgroundColor)

                if let preview = model.renderPreview(maxDimension: max(geo.size.width, geo.size.height) * 2) {
                    Image(nsImage: preview)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .position(x: geo.size.width / 2, y: geo.size.height / 2)
                }

                // Selection outline for the selected annotation.
                if let id = model.selectedAnnotationID,
                   let a = model.annotations.first(where: { $0.id == id }) {
                    let r = toView(a.rect, fit: fit)
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(Color.accentColor.opacity(0.9), style: StrokeStyle(lineWidth: 1.2, dash: [4, 3]))
                        .frame(width: r.width, height: r.height)
                        .position(x: r.midX, y: r.midY)
                }

                // Crop overlay.
                if let crop = model.cropRect {
                    CropOverlay(
                        rect: toView(crop, fit: fit),
                        onApply: { model.applyCrop() },
                        onCancel: { model.cropRect = nil }
                    )
                }

                // Text input overlay.
                if let id = model.editingTextID,
                   let a = model.annotations.first(where: { $0.id == id }) {
                    let origin = toView(a.rect.origin, fit: fit)
                    EditTextOverlay(
                        model: model,
                        position: origin,
                        fontSize: a.fontSize * scaleFactor(fit: fit)
                    )
                }
            }
            .contentShape(Rectangle())
            .gesture(canvasGesture(fit: fit))
        }
    }

    private func canvasGesture(fit: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let start = toImage(value.startLocation, fit: fit)
                let current = toImage(value.location, fit: fit)
                if !model.dragState.began {
                    model.dragState.began = true
                    model.dragState.lastImagePoint = start
                    if model.tool == .select {
                        model.beginDraft(at: start)
                    } else {
                        model.beginDraft(at: start)
                    }
                }
                if model.tool == .select {
                    if let last = model.dragState.lastImagePoint {
                        model.moveSelected(
                            by: CGSize(width: current.x - last.x, height: current.y - last.y)
                        )
                    }
                    model.dragState.lastImagePoint = current
                } else {
                    model.updateDraft(to: current)
                }
            }
            .onEnded { _ in
                defer {
                    model.dragState.began = false
                    model.dragState.lastImagePoint = nil
                }
                if model.tool != .select {
                    model.endDraft()
                }
            }
    }

    // MARK: Geometry mapping

    private func fitRect(in size: CGSize) -> CGRect {
        let imageSize = model.imageSize
        guard imageSize.width > 0, imageSize.height > 0,
              size.width > 0, size.height > 0 else { return .zero }
        let scale = min(size.width / imageSize.width, size.height / imageSize.height)
        let w = imageSize.width * scale
        let h = imageSize.height * scale
        return CGRect(
            x: (size.width - w) / 2, y: (size.height - h) / 2,
            width: w, height: h
        )
    }

    private func scaleFactor(fit: CGRect) -> CGFloat {
        guard model.imageSize.width > 0 else { return 1 }
        return fit.width / model.imageSize.width
    }

    /// Image (top-left) → view coordinates.
    private func toView(_ rect: CGRect, fit: CGRect) -> CGRect {
        let s = scaleFactor(fit: fit)
        return CGRect(
            x: fit.minX + rect.minX * s,
            y: fit.minY + rect.minY * s,
            width: rect.width * s,
            height: rect.height * s
        )
    }

    private func toView(_ point: CGPoint, fit: CGRect) -> CGPoint {
        let s = scaleFactor(fit: fit)
        return CGPoint(x: fit.minX + point.x * s, y: fit.minY + point.y * s)
    }

    /// View → image coordinates (top-left origin).
    private func toImage(_ point: CGPoint, fit: CGRect) -> CGPoint {
        let s = scaleFactor(fit: fit)
        guard s > 0 else { return .zero }
        return CGPoint(x: (point.x - fit.minX) / s, y: (point.y - fit.minY) / s)
    }
}

// MARK: - Crop overlay

private struct CropOverlay: View {
    let rect: CGRect
    let onApply: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            Path { p in
                p.addRect(CGRect(origin: .zero, size: CGSize(width: 10_000, height: 10_000)))
                p.addRect(rect)
            }
            .fill(Color.black.opacity(0.35), style: FillStyle(eoFill: true))

            Rectangle()
                .stroke(.white, lineWidth: 1)
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)

            HStack(spacing: 8) {
                Button("应用裁剪 ⏎", action: onApply)
                Button("取消", action: onCancel)
            }
            .controlSize(.small)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(.black.opacity(0.7)))
            .position(
                x: rect.midX,
                y: min(rect.maxY + 24, rect.maxY)
            )
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Text overlay

private struct EditTextOverlay: NSViewRepresentable {
    let model: EditorModel
    let position: CGPoint
    let fontSize: CGFloat

    final class Field: NSTextField {
        var onEnter: (() -> Void)?
        var onEsc: (() -> Void)?

        override func keyDown(with event: NSEvent) {
            if event.keyCode == 36 { onEnter?(); return }
            if event.keyCode == 53 { onEsc?(); return }
            super.keyDown(with: event)
        }
    }

    func makeNSView(context: Context) -> Field {
        let field = Field()
        field.font = .boldSystemFont(ofSize: max(12, fontSize))
        field.textColor = model.strokeColor
        field.backgroundColor = .black.withAlphaComponent(0.35)
        field.drawsBackground = true
        field.isBordered = false
        field.focusRingType = .none
        field.placeholderString = "输入文字，回车确认"
        field.alignment = .center
        field.onEnter = { model.commitTextEditingIfNeeded() }
        field.onEsc = {
            model.editingDraftText = ""
            model.commitTextEditingIfNeeded()
        }
        field.delegate = context.coordinator
        DispatchQueue.main.async {
            windowFirstResponder(field)
        }
        return field
    }

    private func windowFirstResponder(_ field: Field) {
        field.window?.makeFirstResponder(field)
    }

    func updateNSView(_ field: Field, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        let model: EditorModel
        init(model: EditorModel) { self.model = model }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? Field else { return }
            model.editingDraftText = field.stringValue
            model.invalidate()
        }
    }
}

// MARK: - Status bar

private struct EditorStatusBar: View {
    let model: EditorModel

    var body: some View {
        HStack(spacing: 12) {
            Text("\(Int(model.imageSize.width)) × \(Int(model.imageSize.height))")
                .monospacedDigit()
            Divider().frame(height: 10)
            Text("\(model.annotations.count) 个标注")
            Spacer()
            Text(hint)
        }
        .font(.system(size: 10))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
    }

    private var hint: String {
        switch model.tool {
        case .select: return "拖动移动标注 · ⌫ 删除 · ⌘Z 撤销"
        case .text: return "点击图片放置文字"
        case .crop: return "拖出裁剪区域后点「应用裁剪」"
        default: return "拖动绘制 · Esc 关闭"
        }
    }
}
