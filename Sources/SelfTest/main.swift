import AppKit
import Carbon.HIToolbox
import ClipIslandCore
import Foundation

// Plain-assertion test runner: `swift run SelfTest`. Exists because the CLT
// toolchain's SwiftBuild intermittently fails to load the swift-testing macro
// plugin; a self-contained runner has no such dependency.

var failures = 0
var total = 0

func expect(_ condition: Bool, _ label: String) {
    total += 1
    if condition {
        print("  ✔ \(label)")
    } else {
        failures += 1
        print("  ✘ FAIL: \(label)")
    }
}

func expectEqual<T: Equatable>(_ a: T, _ b: T, _ label: String) {
    expect(a == b, "\(label) (\(a) == \(b))")
}

// MARK: - Utilities

do {
    print("TimeFormat + previewLine")
    var cal = Calendar(identifier: .gregorian)
    cal.locale = Locale(identifier: "zh_CN")
    let now = cal.date(from: DateComponents(year: 2026, month: 10, day: 26, hour: 12))!
    expectEqual(TimeFormat.relative(now.addingTimeInterval(-10), now: now), "刚刚", "relative 10s")
    expectEqual(TimeFormat.relative(now.addingTimeInterval(-300), now: now), "5 分钟前", "relative 5min")
    expectEqual(TimeFormat.relative(now.addingTimeInterval(-3_600), now: now), "1 小时前", "relative 1h")
    let long = String(repeating: "a", count: 300)
    expect(long.previewLine(limit: 160).count == 161, "preview truncates")
    expectEqual("hello\nworld".previewLine(), "hello world", "preview joins lines")
}

// MARK: - ClipStore

func makeTempStore(capacity: Int = 500) throws -> ClipStore {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("clipisland-selftest-\(UUID().uuidString)")
    let store = try ClipStore(directory: dir)
    store.capacity = capacity
    return store
}

func pngData(_ color: NSColor = .red) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.setColor(color, atX: 0, y: 0)
    return rep.representation(using: .png, properties: [:])!
}

do {
    print("ClipStore: dedup")
    let store = try makeTempStore()
    store.add(NewClip(kind: .text, text: "alpha"), now: Date(timeIntervalSince1970: 100))
    store.add(NewClip(kind: .text, text: "beta"), now: Date(timeIntervalSince1970: 200))
    store.add(NewClip(kind: .text, text: "alpha"), now: Date(timeIntervalSince1970: 300))
    expectEqual(store.count, 2, "dedup keeps 2")
    expectEqual(store.all.first?.text ?? "", "alpha", "bumped item on top")
    expectEqual(store.all.first?.createdAt, Date(timeIntervalSince1970: 300), "bumped timestamp")
}

do {
    print("ClipStore: image file")
    let store = try makeTempStore()
    store.add(NewClip(kind: .image, imageData: pngData(.blue)))
    let item = store.all[0]
    expectEqual(item.kind, .image, "kind is image")
    expectEqual(item.imageSize ?? .zero, CGSize(width: 2, height: 2), "pixel size")
    expect(FileManager.default.fileExists(atPath: item.imagePath ?? ""), "png written")
}

do {
    print("ClipStore: LRU keeps pinned")
    let store = try makeTempStore(capacity: 3)
    store.add(NewClip(kind: .text, text: "1"), now: Date(timeIntervalSince1970: 1))
    store.add(NewClip(kind: .text, text: "2"), now: Date(timeIntervalSince1970: 2))
    store.add(NewClip(kind: .text, text: "3"), now: Date(timeIntervalSince1970: 3))
    // "1" is oldest and now at index 2 (unpinned list bottom)
    if let oldest = store.all.last {
        store.setPinned(true, id: oldest.id)
    }
    store.add(NewClip(kind: .text, text: "4"), now: Date(timeIntervalSince1970: 4))
    store.add(NewClip(kind: .text, text: "5"), now: Date(timeIntervalSince1970: 5))
    let texts = store.all.compactMap(\.text)
    expectEqual(store.count, 3, "capacity enforced")
    expect(texts.contains("1"), "pinned survives LRU")
    expect(!texts.contains("2"), "oldest unpinned evicted")
}

do {
    print("ClipStore: search")
    let store = try makeTempStore()
    store.add(NewClip(kind: .text, text: "hello world"))
    store.add(NewClip(kind: .link, text: "https://example.com/clipisland"))
    store.add(NewClip(kind: .image, imageData: pngData()))
    expectEqual(store.search(query: "hello").count, 1, "query match")
    expectEqual(store.search(query: "CLIPISLAND").count, 1, "case-insensitive")
    expectEqual(store.search(query: "", kind: .image).count, 1, "kind filter")
    expect(store.search(query: "e").count >= 2, "broad match")
}

do {
    print("ClipStore: persistence")
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("clipisland-selftest-\(UUID().uuidString)")
    let first = try ClipStore(directory: dir)
    first.add(NewClip(kind: .text, text: "keep me"))
    let pinned = first.add(NewClip(kind: .text, text: "pin me"))!
    first.setPinned(true, id: pinned.id)
    first.add(NewClip(kind: .text, text: "keep me")) // dedup bump

    let second = try ClipStore(directory: dir)
    expectEqual(second.count, 2, "reloads 2 items")
    expectEqual(second.all.first?.text ?? "", "pin me", "pinned group on top after reload")
    let texts = second.all.compactMap(\.text)
    expect(texts.contains("keep me"), "unpinned survived reload")
}

do {
    print("ClipStore: clear removes files")
    let store = try makeTempStore()
    store.add(NewClip(kind: .image, imageData: pngData()))
    let path = store.all[0].imagePath!
    expect(FileManager.default.fileExists(atPath: path), "file exists before clear")
    store.clear()
    expectEqual(store.count, 0, "cleared")
    expect(!FileManager.default.fileExists(atPath: path), "file removed on clear")
}

// MARK: - ClipboardMonitor

func freshPasteboard() -> NSPasteboard {
    NSPasteboard(name: NSPasteboard.Name("selftest-\(UUID().uuidString)"))
}

do {
    print("ClipboardMonitor: capture")
    let pb = freshPasteboard()
    pb.clearContents()
    pb.setString("你好 clipboard", forType: .string)
    expectEqual(ClipboardMonitor.capture(from: pb)?.kind ?? .text, .text, "plain text")
    expectEqual(ClipboardMonitor.capture(from: pb)?.text ?? "", "你好 clipboard", "text payload")

    let pb2 = freshPasteboard()
    pb2.clearContents()
    pb2.setString("https://github.com/clipisland", forType: .string)
    expectEqual(ClipboardMonitor.capture(from: pb2)?.kind ?? .text, .link, "link kind")

    let pb3 = freshPasteboard()
    pb3.clearContents()
    pb3.setString("super-secret", forType: .string)
    pb3.setData(Data("1".utf8), forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
    expect(ClipboardMonitor.capture(from: pb3) == nil, "concealed skipped")

    let pb4 = freshPasteboard()
    pb4.clearContents()
    pb4.setString("   \n ", forType: .string)
    expect(ClipboardMonitor.capture(from: pb4) == nil, "whitespace skipped")

    let pb5 = freshPasteboard()
    pb5.clearContents()
    pb5.writeObjects([URL(fileURLWithPath: "/tmp/a.txt")] as [NSURL])
    expectEqual(ClipboardMonitor.capture(from: pb5)?.kind ?? .text, .file, "file kind")
    expectEqual(ClipboardMonitor.capture(from: pb5)?.text ?? "", "/tmp/a.txt", "file path")
}

do {
    print("ClipboardMonitor: isLink")
    expect(ClipboardMonitor.isLink("https://example.com"), "http url")
    expect(ClipboardMonitor.isLink("http://example.com/path?q=1"), "http w/ path")
    expect(!ClipboardMonitor.isLink("example.com"), "bare domain")
    expect(!ClipboardMonitor.isLink("see https:// inside text"), "embedded url")
    expect(!ClipboardMonitor.isLink("mailto:a@b.com"), "mailto")
}

// MARK: - NotchModel

do {
    print("NotchModel: phases")
    let model = NotchModel()
    var observed: [NotchModel.Phase] = []
    model.onPhaseChange = { phase, _ in observed.append(phase) }
    model.expand()
    expectEqual(model.phase, .expanded, "expand")
    model.collapse()
    expectEqual(model.phase, .collapsed, "collapse")
    expectEqual(observed, [.expanded, .collapsed], "change callback fired")
}

// MARK: - CaptureService math (no permission needed)

do {
    print("CaptureService: crop & pixel sampling")
    // Build a 100x50 image: left half red, right half blue.
    let width = 100, height = 50
    let ctx = CGContext(
        data: nil, width: width, height: height,
        bitsPerComponent: 8, bytesPerRow: width * 4,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
    ctx.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: 50, height: 50))
    ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1))
    ctx.fill(CGRect(x: 50, y: 0, width: 50, height: 50))
    let image = ctx.makeImage()!

    let screenFrame = CGRect(x: 0, y: 0, width: 200, height: 100) // 2x display
    guard let buffer = PixelBuffer(image: image) else {
        print("  ✘ FAIL: pixel buffer init")
        exit(1)
    }
    let frozen = [CaptureService.FrozenScreen(
        screen: NSScreen(), image: image, pixels: buffer, frameInScreen: screenFrame
    )]
    let service = CaptureService.shared

    // Sample: global point (25,25) → image (12,25-ish) red; (175, 25) → blue.
    let left = service.color(at: NSPoint(x: 25, y: 25), in: frozen)
    let right = service.color(at: NSPoint(x: 175, y: 25), in: frozen)
    expect(left?.hexString == "#FF0000", "left sample red (\(left?.hexString ?? "nil"))")
    expect(right?.hexString == "#0000FF", "right sample blue (\(right?.hexString ?? "nil"))")

    // Crop the top-left quarter in screen coords: x 0-100, y 50-100.
    // Display is 2x the image, so a 100x50 selection crops to 50x25 pixels.
    let cropped = service.crop(selection: CGRect(x: 0, y: 50, width: 100, height: 50), from: frozen)
    expect(cropped?.width == 50, "crop width (got \(cropped?.width ?? -1))")
    expect(cropped?.height == 25, "crop height (got \(cropped?.height ?? -1))")
    // Cropped image is all red (left half).
    if let cropped,
       let croppedBuffer = PixelBuffer(image: cropped),
       let sample = croppedBuffer.color(x: 45, y: 12) {
        expect(sample.hexString == "#FF0000", "crop content is red half (\(sample.hexString))")
    } else {
        expect(false, "crop buffer failed")
    }

    // Tiny selection is rejected.
    expect(service.crop(selection: CGRect(x: 0, y: 0, width: 3, height: 3), from: frozen) == nil, "tiny crop rejected")

    // savePNG round-trip
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("clipisland-selftest-\(UUID().uuidString)")
    let saved = service.savePNG(image, to: dir)
    expect(saved != nil && FileManager.default.fileExists(atPath: saved?.path ?? ""), "png saved")
}

do {
    print("HotkeyManager: parse")
    let combo = HotkeyManager.parse("cmd+shift+v")
    expect(combo != nil, "cmd+shift+v parses")
    expectEqual(combo!.keyCode, 9, "v keycode = 9")
    expectEqual(combo!.carbonFlags, UInt32(cmdKey | shiftKey), "flags cmd|shift")

    expectEqual(HotkeyManager.parse("cmd+shift+6")?.keyCode, 22, "6 keycode = 22")
    expect(HotkeyManager.parse("option+space") != nil, "opt+space parses")
    expect(HotkeyManager.parse("ctrl+a") != nil, "ctrl+a parses")
    expect(HotkeyManager.parse("v") == nil, "missing modifier rejected")
    expect(HotkeyManager.parse("cmd+xx") == nil, "unknown key rejected")
    expect(HotkeyManager.parse("cmd+shift") == nil, "missing key rejected")
}


// MARK: - EditorModel

do {
    print("EditorModel: annotations & undo")
    let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(
        data: nil, width: 100, height: 50,
        bitsPerComponent: 8, bytesPerRow: 100 * 4,
        space: srgb,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    ctx.setFillColor(CGColor(srgbRed: 0.5, green: 0.5, blue: 0.5, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: 100, height: 50))
    let image = ctx.makeImage()!

    let model = EditorModel(image: image)
    expect(model.canUndo == false, "starts clean")

    // Add a rectangle via the draft lifecycle.
    model.tool = .rectangle
    model.beginDraft(at: CGPoint(x: 10, y: 10))
    model.updateDraft(to: CGPoint(x: 60, y: 40))
    model.endDraft()
    expect(model.annotations.count == 1, "annotation committed")
    expect(model.canUndo, "can undo after commit")

    model.undo()
    expect(model.annotations.isEmpty && model.canRedo, "undo clears")
    model.redo()
    expect(model.annotations.count == 1, "redo restores")

    // Move + delete selected.
    model.selectedAnnotationID = model.annotations[0].id
    let before = model.annotations[0].rect
    model.moveSelected(by: CGSize(width: 5, height: 5))
    expect(model.annotations[0].rect.origin.x == before.origin.x + 5, "move shifts rect")
    model.deleteSelected()
    expect(model.annotations.isEmpty, "delete selected")

    // Crop applies to base and shifts annotations.
    model.tool = .rectangle
    model.beginDraft(at: CGPoint(x: 5, y: 5))
    model.updateDraft(to: CGPoint(x: 45, y: 45))
    model.endDraft()
    model.tool = .crop
    model.beginDraft(at: CGPoint(x: 0, y: 0))
    model.updateDraft(to: CGPoint(x: 50, y: 50))
    model.applyCrop()
    expect(model.baseImage.width == 50, "crop halves width (got \(model.baseImage.width))")
    expect(model.annotations[0].rect.origin.x == 5, "annotation coords kept in crop space")

    // Text: empty commit drops annotation; text commit keeps it.
    model.tool = .text
    model.placeText(at: CGPoint(x: 5, y: 5))
    expect(model.editingTextID != nil, "text editing begins")
    model.commitTextEditingIfNeeded()
    expect(!model.annotations.contains { $0.kind == .text }, "empty text dropped")

    // Mosaic tile generation.
    let mosaicTile = EditorModel.pixelate(
        image: model.baseImage, region: CGRect(x: 0, y: 0, width: 40, height: 40), blockSize: 10
    )
    expect(mosaicTile != nil, "mosaic tile generated")

    // Composite renders without crashing and keeps dimensions.
    let composite = model.composite()
    expect(composite != nil && composite!.width == model.baseImage.width, "composite ok")
}

print("")
if failures == 0 {
    print("ALL \(total) checks passed")
    exit(0)
} else {
    print("\(failures)/\(total) checks FAILED")
    exit(1)
}
