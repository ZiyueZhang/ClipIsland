import AppKit
import Carbon.HIToolbox
import ClipIslandCore
import CryptoKit
import Foundation
import SQLite3

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
    // Anchor to the real current day so isDateInToday-based branches hold on any run date.
    let cal = Calendar.current
    let now = cal.date(byAdding: DateComponents(hour: 12), to: cal.startOfDay(for: Date()))!
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


// MARK: - FrameAnimator spring math

do {
    print("FrameAnimator: spring convergence")
    // Underdamped (0.82): must settle at target without NaN, slight overshoot ok.
    var (s, v) = (0.0, 0.0)
    var overshoot = 0.0
    let (k, c) = FrameAnimator.coefficients(response: 0.42, dampingFraction: 0.82)
    for _ in 0..<1200 {
        (s, v) = FrameAnimator.advance(s: s, v: v, k: k, c: c, dt: 1 / 120)
        overshoot = max(overshoot, s)
    }
    expect(s.isFinite && v.isFinite, "no NaN over 10s of steps")
    expect(abs(s - 1) < 0.005 && abs(v) < 0.005, "settles (s=\(s), v=\(v))")
    expect(overshoot < 1.15 && overshoot > 0.99, "plausible trajectory (peak=\(overshoot))")

    // Critically damped (1.0): no overshoot.
    var (sc, vc) = (0.0, 0.0)
    let (kc, cc) = FrameAnimator.coefficients(response: 0.32, dampingFraction: 1.0)
    var peak = 0.0
    for _ in 0..<1200 {
        (sc, vc) = FrameAnimator.advance(s: sc, v: vc, k: kc, c: cc, dt: 1 / 120)
        peak = max(peak, sc)
    }
    expect(abs(sc - 1) < 0.005, "critical settles (s=\(sc))")
    expect(peak <= 1.0001, "critical never overshoots (peak=\(peak))")

    // Large-dt stability (tab-throttle style 1/30 steps).
    var (st, vt) = (0.0, 0.0)
    for _ in 0..<600 { (st, vt) = FrameAnimator.advance(s: st, v: vt, k: k, c: c, dt: 1 / 30) }
    expect(abs(st - 1) < 0.01 && st.isFinite, "stable at 30Hz steps (s=\(st))")
}

// MARK: - Thumbnail downsampling

do {
    print("ThumbnailCache: ImageIO downsample")
    let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(
        data: nil, width: 3000, height: 2000,
        bitsPerComponent: 8, bytesPerRow: 3000 * 4,
        space: srgb,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    ctx.setFillColor(CGColor(srgbRed: 0.3, green: 0.7, blue: 0.2, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: 3000, height: 2000))
    let big = ctx.makeImage()!
    let dest = CGImageDestinationCreateWithURL(
        URL(fileURLWithPath: "/tmp/ci-selftest-big.png") as CFURL,
        "public.png" as CFString, 1, nil
    )!
    CGImageDestinationAddImage(dest, big, nil)
    CGImageDestinationFinalize(dest)

    if let thumb = ThumbnailCache.downsampled(path: "/tmp/ci-selftest-big.png", maxPixel: 136) {
        let pixels = max(thumb.size.width, thumb.size.height)
        expect(pixels <= 136 && pixels >= 120, "thumbnail bounded (\(thumb.size))")
    } else {
        expect(false, "thumbnail decoded")
    }
    try? FileManager.default.removeItem(atPath: "/tmp/ci-selftest-big.png")
}

// MARK: - Pasteboard image flavors

do {
    print("AutoPaster: PNG+TIFF flavors")
    let pb = NSPasteboard(name: NSPasteboard.Name("selftest-flavors-\(UUID().uuidString)"))
    pb.clearContents()
    AutoPaster.writeImageFlavors(pb, pngData: pngData(.systemGreen))
    expect(pb.data(forType: .png) != nil, "png flavor present")
    expect(pb.data(forType: .tiff) != nil, "tiff flavor present")
}


// MARK: - Vault crypto

do {
    print("Vault: PBKDF2 + AES-GCM")
    // RFC 7914-style vector for PBKDF2-HMAC-SHA256: 1 iteration.
    let key = Vault.pbkdf2(password: "password", salt: Data("salt".utf8), iterations: 1)
    let hex = key.withUnsafeBytes { Data($0).map { String(format: "%02x", $0) }.joined() }
    expect(hex == "120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b", "PBKDF2 vector (\(hex.prefix(16))…)")

    // Round trip.
    let vaultKey = SymmetricKey(size: .bits256)
    let secret = Data("绝密内容 classified 🤫".utf8)
    let sealed = try AES.GCM.seal(secret, using: vaultKey).combined!
    let opened = try AES.GCM.open(try AES.GCM.SealedBox(combined: sealed), using: vaultKey)
    expect(opened == secret, "seal/open round trip")

    // Wrong key must fail.
    let wrong = SymmetricKey(size: .bits256)
    expect((try? AES.GCM.open(try AES.GCM.SealedBox(combined: sealed), using: wrong)) == nil, "wrong key rejected")

    // Sealed payloads carry the CIV1 magic on disk.
    expect(!ClipStore.isSealedData(sealed), "raw gcm output is not a disk payload")
    let onDisk = ClipStore.sealMagic + sealed
    expect(ClipStore.isSealedData(onDisk), "magic-prefixed payload flagged")
    let pngMagic = Data([0x89, 0x50, 0x4E, 0x47]) + Data(repeating: 0, count: 16)
    expect(!ClipStore.isSealedData(pngMagic), "png not flagged")
}

do {
    print("Vault: lifecycle (isolated defaults)")
    let suite = UserDefaults(suiteName: "selftest-vault-\(UUID().uuidString)")!
    let vault = Vault(defaults: suite)

    expect(vault.state == .plaintext, "starts plaintext")
    expect(!vault.isEnabled, "not enabled")

    // Setup + at-rest formats.
    try vault.setup(password: "test1234")
    expect(vault.isUnlocked && vault.isEnabled, "setup unlocks")
    let sealedText = VaultCoding.encodeText("hello vault", vault: vault)
    expect(sealedText?.hasPrefix("enc:v1:") == true, "text encoded with prefix")
    expect(sealedText?.contains("hello vault") == false, "plaintext absent at rest")
    expect(VaultCoding.decodeText(sealedText!, vault: vault) == "hello vault", "decode round trip")

    // Lock / unlock / wrong password.
    vault.lock()
    expect(vault.state == .locked, "locked")
    expect(VaultCoding.decodeText(sealedText!, vault: vault) == nil, "decode unavailable while locked")
    expect((try? vault.seal(Data([1]))) == nil, "seal unavailable while locked")
    var wrongFailed = false
    do { try vault.unlock(password: "wrong") } catch VaultError.wrongPassword { wrongFailed = true } catch { wrongFailed = false }
    expect(wrongFailed, "wrong password rejected")
    try vault.unlock(password: "test1234")
    expect(vault.isUnlocked, "correct password unlocks")

    // Keyed dedup hash: deterministic, differs from plain SHA256.
    let material = Data("dedup-probe".utf8)
    let h1 = vault.keyedHash(material)
    let h2 = vault.keyedHash(material)
    expect(h1 == h2 && h1 != nil, "keyed hash deterministic")
    expect(h1 != SHA256.hash(data: material).map { String(format: "%02x", $0) }.joined(), "keyed hash differs from plain sha256")

    // Remove.
    try vault.removePassword(current: "test1234")
    expect(vault.state == .plaintext, "removed -> plaintext")
    expect(VaultCoding.encodeText("x", vault: vault) == nil, "encoding off after removal")
}

// MARK: - ClipStore + vault integration

do {
    print("ClipStore: encrypted at rest")
    let suite = UserDefaults(suiteName: "selftest-vault-store-\(UUID().uuidString)")!
    let vault = Vault(defaults: suite)
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("clipisland-vault-\(UUID().uuidString)")
    let store = try ClipStore(directory: dir, vault: vault)
    store.capacity = 50

    // Plaintext mode baseline.
    store.add(NewClip(kind: .text, text: "plain-mode text"))
    expect(store.all.first?.text == "plain-mode text", "plaintext mode readable")

    // Enable vault: migration seals existing rows.
    try vault.setup(password: "test1234")
    store.migrateAll(enabled: true)
    expect(store.all.first?.text == "plain-mode text", "still readable after migration (unlocked)")

    // DB raw check: ciphertext + no plaintext.
    guard let raw = try? SQLiteDatabase(path: dir.appendingPathComponent("clips.sqlite3").path) else {
        let probe = try? SQLiteDatabase(path: dir.appendingPathComponent("clips.sqlite3").path)
        expect(false, "raw db open failed: \(String(describing: probe))")
        failures += 1
        print("\(failures)/\(total) checks FAILED (abort)")
        exit(1)
    }
    let rawText = try raw.query("SELECT text FROM clips LIMIT 1", []) { String(cString: sqlite3_column_text($0, 0)) }
    expect(rawText.first?.hasPrefix("enc:v1:") == true, "DB text is sealed (\(rawText.first?.prefix(12) ?? "nil")…)")
    expect(rawText.first?.contains("plain-mode") == false, "plaintext absent in DB")

    // New adds are sealed too.
    store.add(NewClip(kind: .text, text: "second-secret-文本"))
    let raw2 = try raw.query("SELECT COUNT(*) FROM clips WHERE text LIKE '%second-secret%'", []) { sqlite3_column_int($0, 0) }
    expect(Int(raw2.first ?? 1) == 0, "new text not in DB plaintext")

    // Lock: content redacted, search blind.
    vault.lock()
    let reloaded = try ClipStore(directory: dir, vault: vault)
    expect(reloaded.all.first?.redacted == true, "locked reload redacts")
    expect(reloaded.all.first?.displayText.contains("🔒") == true, "redacted display text")
    expect(reloaded.search(query: "second-secret").isEmpty, "search blind while locked")

    // Capture while locked: buffered in RAM, never on disk.
    let dbBefore = try raw.query("SELECT COUNT(*) FROM clips", []) { Int(sqlite3_column_int($0, 0)) }.first ?? -1
    reloaded.add(NewClip(kind: .text, text: "locked-period capture"))
    expect(reloaded.pendingCaptureCount == 1, "pending buffer holds capture")
    let dbAfter = try raw.query("SELECT COUNT(*) FROM clips", []) { Int(sqlite3_column_int($0, 0)) }.first ?? -1
    expect(dbAfter == dbBefore, "nothing written to disk while locked")

    // Unlock: flush merges buffered capture, now sealed.
    try vault.unlock(password: "test1234")
    reloaded.flushPendingCaptures()
    expect(reloaded.pendingCaptureCount == 0, "pending flushed")
    expect(reloaded.all.contains { $0.text == "locked-period capture" }, "buffered capture stored")
    let rawSealed = try raw.query("SELECT COUNT(*) FROM clips WHERE text LIKE 'enc:%'", []) { Int(sqlite3_column_int($0, 0)) }
    expect((rawSealed.first ?? 0) >= 2, "buffered capture sealed at rest (\(rawSealed.first ?? -1))")
}


// MARK: - Hover dwell zone

do {
    print("MenuBarHoverMonitor: dwell zone")
    // Strip (notch 216 + ears) at the top of a 1800x1169 display.
    let strip = CGRect(x: 640, y: 1131, width: 480, height: 38)
    let zone = MenuBarHoverMonitor.dwellZone(stripFrame: strip)
    expect(zone.width == 480, "zone keeps strip width (\(zone.width))")
    expect(zone.minY == strip.minY - 18, "zone pads 18pt above (menu-bar row) (\(zone.minY))")
    expect(zone.maxY == strip.maxY + 18, "zone reaches 18pt below the strip (\(zone.maxY))")
    // Pointer just below the notch center is inside; a far menu-bar corner is not.
    expect(zone.contains(NSPoint(x: 880, y: 1120)), "directly below notch triggers")
    expect(!zone.contains(NSPoint(x: 200, y: 1140)), "far menu-bar corner does not trigger")
    // Custom padding honored.
    let tight = MenuBarHoverMonitor.dwellZone(stripFrame: strip, belowPadding: 0)
    expect(tight == strip, "zero padding = strip itself")
}


// MARK: - Rich content capture (HTML/RTF)

do {
    print("ClipboardMonitor: rich flavors")
    let pb = freshPasteboard()
    pb.clearContents()
    pb.setString("富文本标题", forType: .string)
    pb.setData(Data("<h1>富文本标题</h1>".utf8), forType: NSPasteboard.PasteboardType("public.html"))
    let clip = ClipboardMonitor.capture(from: pb)
    expect(clip?.htmlData != nil, "html flavor captured")
    expect(clip?.text == "富文本标题", "plain text alongside")
}

do {
    print("ClipStore: rich payload at rest + paste-back")
    let suite = UserDefaults(suiteName: "selftest-rich-\(UUID().uuidString)")!
    let vault = Vault(defaults: suite)
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("clipisland-rich-\(UUID().uuidString)")
    let store = try ClipStore(directory: dir, vault: vault)

    // Plaintext mode baseline.
    let html = Data("<b>bold 内容</b>".utf8)
    store.add(NewClip(kind: .text, text: "rich row", htmlData: html))
    var item = store.all[0]
    expect(item.htmlPath != nil, "html stored to file")
    var isDir: ObjCBool = false
    expect(FileManager.default.fileExists(atPath: item.htmlPath!, isDirectory: &isDir), "html file exists")
    expect(store.decryptedRich(for: item).html == html, "decrypt round trip (plain mode)")

    // Enable vault: migration seals the rich file.
    try vault.setup(password: "test1234")
    store.migrateAll(enabled: true)
    item = store.all[0]
    let sealedBytes = FileManager.default.contents(atPath: item.htmlPath!)
    expect(sealedBytes.map { ClipStore.isSealedData($0) } == true, "rich payload sealed under vault")
    expect(store.decryptedRich(for: item).html == html, "decrypt round trip (vault)")

    // Paste-back flavors through AutoPaster (it writes the general pasteboard).
    let paster = AutoPaster(monitor: ClipboardMonitor())
    paster.richLoader = { [weak store] it in store?.decryptedRich(for: it) ?? (nil, nil) }
    paster.writeToPasteboard(item)
    let gen = NSPasteboard.general
    expect(gen.string(forType: .string) == "rich row", "string flavor present")
    expect(gen.data(forType: NSPasteboard.PasteboardType("public.html")) == html, "html flavor pasted back")

    // Removal cleans the rich file.
    store.remove(id: item.id)
    expect(!FileManager.default.fileExists(atPath: item.htmlPath!), "rich file removed with the row")
}

print("")
if failures == 0 {
    print("ALL \(total) checks passed")
    exit(0)
} else {
    print("\(failures)/\(total) checks FAILED")
    exit(1)
}
