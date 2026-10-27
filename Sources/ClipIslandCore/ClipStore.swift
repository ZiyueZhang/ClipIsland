import AppKit
import CryptoKit
import Foundation
import SQLite3

/// sqlite3's SQLITE_TRANSIENT is a macro not exposed to Swift.
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

enum SQLiteError: Error {
    case open(String)
    case prepare(String, sql: String)
    case step(String, sql: String)
    case exec(String, sql: String)
}

/// Minimal wrapper over the sqlite3 C API: enough for the clips table.
public final class SQLiteDatabase {
    private var handle: OpaquePointer?

    public init(path: String) throws {
        var db: OpaquePointer?
        let rc = sqlite3_open_v2(path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil)
        guard rc == SQLITE_OK, let db else {
            if let db { sqlite3_close(db) }
            throw SQLiteError.open("sqlite3_open_v2 rc=\(rc)")
        }
        handle = db
    }

    deinit {
        if let handle { sqlite3_close(handle) }
    }

    public func exec(_ sql: String) throws {
        var err: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(handle, sql, nil, nil, &err)
        guard rc == SQLITE_OK else {
            let message = err.map { String(cString: $0) } ?? "rc=\(rc)"
            sqlite3_free(err)
            throw SQLiteError.exec(message, sql: sql)
        }
    }

    public func run(_ sql: String, _ params: [SQLiteValue] = []) throws {
        let stmt = try prepare(sql, params)
        defer { sqlite3_finalize(stmt) }
        let rc = sqlite3_step(stmt)
        guard rc == SQLITE_DONE || rc == SQLITE_ROW else {
            throw SQLiteError.step("rc=\(rc)", sql: sql)
        }
    }

    public func query<T>(_ sql: String, _ params: [SQLiteValue] = [], map: (OpaquePointer) -> T) throws -> [T] {
        let stmt = try prepare(sql, params)
        defer { sqlite3_finalize(stmt) }
        var rows: [T] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            rows.append(map(stmt))
        }
        return rows
    }

    private func prepare(_ sql: String, _ params: [SQLiteValue]) throws -> OpaquePointer {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw SQLiteError.prepare(String(cString: sqlite3_errmsg(handle)), sql: sql)
        }
        for (idx, param) in params.enumerated() {
            let i = Int32(idx + 1)
            switch param {
            case .null: sqlite3_bind_null(stmt, i)
            case .int(let v): sqlite3_bind_int64(stmt, i, Int64(v))
            case .double(let v): sqlite3_bind_double(stmt, i, v)
            case .text(let v): sqlite3_bind_text(stmt, i, v, -1, SQLITE_TRANSIENT)
            }
        }
        return stmt
    }

    public var lastInsertRowID: Int64 {
        sqlite3_last_insert_rowid(handle)
    }
}

public enum SQLiteValue {
    case null
    case int(Int)
    case double(Double)
    case text(String)
}

/// Clipboard history store: in-memory list of clips, persisted to SQLite;
/// images live as PNG files next to the database. When the vault is enabled,
/// text payloads and image files are sealed (AES-GCM) at rest, dedup hashes
/// become keyed HMACs, and captures made while locked are buffered in RAM
/// until unlock — nothing sensitive is written while the key is unavailable.
///
/// Main-thread only.
public final class ClipStore {
    public let directory: URL
    public var capacity: Int = SettingsStore.shared.capacity
    public var onDidChange: (() -> Void)?
    public let vault: Vault

    private var db: SQLiteDatabase
    private(set) var items: [ClipItem] = [] // pinned first, then newest first
    private var hashToIndex: [String: Int] = [:]
    /// Captures taken while the vault was locked; flushed on unlock.
    private var pendingLocked: [NewClip] = []

    public var pendingCaptureCount: Int { pendingLocked.count }

    public init(directory: URL, vault: Vault = .shared) throws {
        self.vault = vault
        self.directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let images = directory.appendingPathComponent("images", isDirectory: true)
        try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
        db = try SQLiteDatabase(path: directory.appendingPathComponent("clips.sqlite3").path)
        try db.exec("""
        CREATE TABLE IF NOT EXISTS clips(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            kind TEXT NOT NULL,
            text TEXT,
            image_path TEXT,
            image_w REAL,
            image_h REAL,
            source_bundle TEXT,
            source_name TEXT,
            created_at REAL NOT NULL,
            pinned INTEGER NOT NULL DEFAULT 0,
            content_hash TEXT NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_clips_hash ON clips(content_hash);
        """)
        reload()
    }

    public var count: Int { items.count }
    public var all: [ClipItem] { items }

    public func search(query: String, kind: ClipKind? = nil) -> [ClipItem] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return items.filter { item in
            guard kind == nil || item.kind == kind else { return false }
            guard !q.isEmpty else { return true }
            let haystacks: [String] = [
                item.redacted ? "" : (item.text ?? ""),
                item.sourceName ?? "",
                item.kind.label,
            ]
            return haystacks.contains { $0.localizedCaseInsensitiveContains(q) }
        }
    }

    /// Inserts a captured clip; identical content bumps the existing entry to
    /// the top instead of duplicating. Returns the stored item.
    @discardableResult
    public func add(_ clip: NewClip, now: Date = Date()) -> ClipItem? {
        // Vault locked: never touch disk with an unavailable key. Buffer in
        // RAM; flushed through this method again on unlock.
        if vault.isEnabled, vault.state == .locked {
            pendingLocked.append(clip)
            onDidChange?()
            return nil
        }
        let hash = Self.contentHash(clip, vault: vault)
        if let idx = hashToIndex[hash] {
            var item = items[idx]
            item.createdAt = now
            items[idx] = item
            try? db.run("UPDATE clips SET created_at = ? WHERE id = ?", [.double(now.timeIntervalSince1970), .int(Int(item.id))])
            reposition(idx)
            onDidChange?()
            return item
        }

        var imagePath: String?
        var imageSize: CGSize?
        if let data = clip.imageData, clip.kind == .image {
            let name = UUID().uuidString + ".png"
            let url = directory.appendingPathComponent("images").appendingPathComponent(name)
            do {
                let atRest = vault.isEnabled ? try vault.seal(data) : data
                try atRest.write(to: url, options: .atomic)
                imagePath = url.path
                if let rep = NSBitmapImageRep(data: data) {
                    imageSize = CGSize(width: rep.pixelsWide, height: rep.pixelsHigh)
                }
            } catch {
                log("image write failed: \(error.localizedDescription)")
                return nil
            }
        }

        let storedText: String?
        if vault.isEnabled, let text = clip.text {
            storedText = VaultCoding.encodeText(text, vault: vault)
        } else {
            storedText = clip.text
        }
        try? db.run(
            """
            INSERT INTO clips(kind, text, image_path, image_w, image_h, source_bundle, source_name, created_at, pinned, content_hash)
            VALUES(?,?,?,?,?,?,?,? ,0, ?)
            """,
            [
                .text(clip.kind.rawValue),
                storedText.map { .text($0) } ?? .null,
                imagePath.map { .text($0) } ?? .null,
                imageSize.map { .double($0.width) } ?? .null,
                imageSize.map { .double($0.height) } ?? .null,
                clip.sourceBundle.map { .text($0) } ?? .null,
                clip.sourceName.map { .text($0) } ?? .null,
                .double(now.timeIntervalSince1970),
                .text(hash),
            ]
        )
        let id = db.lastInsertRowID
        let item = ClipItem(
            id: id, kind: clip.kind, text: clip.text, imagePath: imagePath,
            imageSize: imageSize, sourceBundle: clip.sourceBundle,
            sourceName: clip.sourceName, createdAt: now, pinned: false,
            contentHash: hash
        )
        items.insert(item, at: insertionIndex(for: item))
        rebuildIndex()
        enforceCapacity()
        onDidChange?()
        return item
    }

    public func setPinned(_ pinned: Bool, id: Int64) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        items[idx].pinned = pinned
        try? db.run("UPDATE clips SET pinned = ? WHERE id = ?", [.int(pinned ? 1 : 0), .int(Int(id))])
        let item = items.remove(at: idx)
        items.insert(item, at: insertionIndex(for: item))
        rebuildIndex()
        onDidChange?()
    }

    public func remove(id: Int64) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        let item = items.remove(at: idx)
        if let path = item.imagePath {
            try? FileManager.default.removeItem(atPath: path)
        }
        try? db.run("DELETE FROM clips WHERE id = ?", [.int(Int(id))])
        rebuildIndex()
        onDidChange?()
    }

    /// Clears everything, including pinned items and image files.
    public func clear() {
        for item in items {
            if let path = item.imagePath {
                try? FileManager.default.removeItem(atPath: path)
            }
        }
        items.removeAll()
        hashToIndex.removeAll()
        try? db.run("DELETE FROM clips")
        onDidChange?()
    }

    // MARK: - Vault surface

    /// True when the file holds vault-sealed bytes (not a plain PNG).
    public func isSealedFile(_ path: String) -> Bool {
        guard let bytes = FileManager.default.contents(atPath: path) else { return false }
        return Self.isSealedData(bytes)
    }

    /// Pure byte-sniffing: vault output starts with the GCM nonce, never with
    /// the PNG magic. Unit tested.
    public static func isSealedData(_ bytes: Data) -> Bool {
        guard bytes.count > 8 else { return false }
        let pngMagic: [UInt8] = [0x89, 0x50, 0x4E, 0x47]
        return !Array(bytes.prefix(4)).elementsEqual(pngMagic)
    }

    /// Decrypted image bytes for a stored item (pasteboard, editor, Quick Look).
    public func decryptedImageData(for item: ClipItem) -> Data? {
        guard let path = item.imagePath, let raw = FileManager.default.contents(atPath: path) else {
            return nil
        }
        guard Self.isSealedData(raw) else { return raw }
        guard vault.isUnlocked, let opened = try? vault.open(raw) else { return nil }
        return opened
    }

    public func loadImage(for item: ClipItem) -> NSImage? {
        decryptedImageData(for: item).flatMap(NSImage.init(data:))
    }

    /// Bounded decode: decrypt then thumbnail straight off the data — the
    /// full bitmap never materializes.
    public func downsampledThumbnail(for item: ClipItem, maxPixel: Int) -> NSImage? {
        guard let data = decryptedImageData(for: item),
              let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
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

    /// After unlock: captures buffered in RAM while locked enter the store
    /// normally (they get sealed now that the key is available).
    public func flushPendingCaptures() {
        guard !pendingLocked.isEmpty else { return }
        let buffered = pendingLocked
        pendingLocked.removeAll()
        log("flushing \(buffered.count) locked-period captures")
        for clip in buffered {
            add(clip)
        }
    }

    /// Rewrites text and image bytes to match the vault state. Requires an
    /// unlocked vault when enabling; runs row-by-row at the DB level because
    /// in-memory items already hold decoded text.
    public func migrateAll(enabled: Bool) {
        guard enabled ? vault.isUnlocked : true else {
            log("migration aborted: vault locked")
            return
        }
        let rows = (try? db.query(
            "SELECT id, kind, text, image_path FROM clips", [],
            map: { stmt -> (Int64, String, String?, String?) in
                let id = sqlite3_column_int64(stmt, 0)
                let kind = String(cString: sqlite3_column_text(stmt, 1))
                let t = sqlite3_column_text(stmt, 2) != nil ? String(cString: sqlite3_column_text(stmt, 2)) : nil
                let p = sqlite3_column_text(stmt, 3) != nil ? String(cString: sqlite3_column_text(stmt, 3)) : nil
                return (id, kind, t, p)
            }
        )) ?? []
        var migrated = 0
        for (id, kind, storedText, imagePath) in rows {
            do {
                if enabled {
                    if let stored = storedText, !stored.hasPrefix(VaultCoding.textPrefix),
                       let sealed = VaultCoding.encodeText(stored, vault: vault) {
                        try db.run("UPDATE clips SET text = ? WHERE id = ?", [.text(sealed), .int(Int(id))])
                        migrated += 1
                    }
                    if kind == ClipKind.image.rawValue, let path = imagePath,
                       let bytes = FileManager.default.contents(atPath: path), !Self.isSealedData(bytes) {
                        try vault.seal(bytes).write(to: URL(fileURLWithPath: path), options: .atomic)
                        migrated += 1
                    }
                } else {
                    if let stored = storedText, stored.hasPrefix(VaultCoding.textPrefix) {
                        let plain = VaultCoding.decodeText(stored, vault: vault) ?? ""
                        let hash = "m:" + SHA256.hash(data: Data(kind.utf8) + Data(plain.utf8))
                            .map { String(format: "%02x", $0) }.joined()
                        try db.run("UPDATE clips SET text = ?, content_hash = ? WHERE id = ?",
                                   [.text(plain), .text(hash), .int(Int(id))])
                        migrated += 1
                    }
                    if kind == ClipKind.image.rawValue, let path = imagePath,
                       let bytes = FileManager.default.contents(atPath: path), Self.isSealedData(bytes) {
                        let plain = try vault.open(bytes)
                        try plain.write(to: URL(fileURLWithPath: path), options: .atomic)
                        migrated += 1
                    }
                }
            } catch {
                log("migration item \(id) failed: \(error)")
            }
        }
        reload()
        log("vault migration (enabled=\(enabled)): \(migrated) transforms")
    }

    // MARK: - Internals

    private func reload() {
        items = (try? db.query(
            "SELECT id, kind, text, image_path, image_w, image_h, source_bundle, source_name, created_at, pinned, content_hash FROM clips ORDER BY pinned DESC, created_at DESC",
            []
        ) { stmt in
            func text(_ i: Int32) -> String? {
                guard sqlite3_column_text(stmt, i) != nil else { return nil }
                return String(cString: sqlite3_column_text(stmt, i))
            }
            let w = sqlite3_column_type(stmt, 4) != SQLITE_NULL ? sqlite3_column_double(stmt, 4) : nil
            let h = sqlite3_column_type(stmt, 5) != SQLITE_NULL ? sqlite3_column_double(stmt, 5) : nil
            // Encrypted-at-rest text: decrypt when unlocked, redact when locked.
            var plain: String?
            var redacted = false
            if let stored = text(2) {
                if stored.hasPrefix(VaultCoding.textPrefix) {
                    if let opened = VaultCoding.decodeText(stored, vault: vault) {
                        plain = opened
                    } else {
                        redacted = true
                    }
                } else {
                    plain = stored
                }
            }
            if let kind = text(1), kind == ClipKind.image.rawValue,
               let path = text(3), isSealedFile(path) {
                redacted = true // image bytes unavailable while locked
            }
            return ClipItem(
                id: sqlite3_column_int64(stmt, 0),
                kind: ClipKind(rawValue: String(cString: sqlite3_column_text(stmt, 1))) ?? .text,
                text: plain,
                imagePath: text(3),
                imageSize: (w != nil && h != nil) ? CGSize(width: w!, height: h!) : nil,
                sourceBundle: text(6),
                sourceName: text(7),
                createdAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 8)),
                pinned: sqlite3_column_int(stmt, 9) != 0,
                contentHash: text(10) ?? "",
                redacted: redacted
            )
        }) ?? []
        rebuildIndex()
    }

    private func reposition(_ idx: Int) {
        let item = items.remove(at: idx)
        items.insert(item, at: insertionIndex(for: item))
        rebuildIndex()
    }

    /// Where an item goes when (re)inserted: top of the unpinned group, or the
    /// end of the pinned group — both are `firstUnpinned`.
    private func insertionIndex(for item: ClipItem) -> Int {
        items.firstIndex { !$0.pinned } ?? items.count
    }

    private func enforceCapacity() {
        guard capacity > 0 else { return }
        var overflow = items.count - capacity
        while overflow > 0 {
            // Oldest unpinned lives at the tail, but pinned entries may be last
            // in memory layout only if sorting differs; find by date instead.
            guard let idx = items.indices.reversed().first(where: { !items[$0].pinned }) else { break }
            remove(id: items[idx].id)
            overflow -= 1
        }
    }

    private func rebuildIndex() {
        hashToIndex.removeAll()
        for (i, item) in items.enumerated() where !item.contentHash.isEmpty {
            hashToIndex[item.contentHash] = i
        }
    }

    private static func contentHash(_ clip: NewClip, vault: Vault) -> String {
        var data = Data(clip.kind.rawValue.utf8)
        data.append(0)
        if let text = clip.text {
            data.append(Data(text.utf8))
        }
        if let image = clip.imageData {
            data.append(image)
        }
        // Keyed hash when the vault is on: duplicate-equality never leaks at rest.
        if vault.isEnabled, vault.isUnlocked, let keyed = vault.keyedHash(data) {
            return "h1:" + keyed
        }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
