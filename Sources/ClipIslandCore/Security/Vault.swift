import CryptoKit
import CommonCrypto
import Foundation
import LocalAuthentication
import Security

public enum VaultError: Error, Equatable {
    case wrongPassword
    case notSetup
    case alreadySetup
    case locked
    case keychainUnavailable(OSStatus)
    case biometryUnavailable
    case biometryFailed(String)
}

/// persisted vault parameters; the wrapped data key never appears in plaintext.
public struct VaultMetadata: Codable, Equatable {
    public var salt: Data
    public var wrappedDataKey: Data
    public var iterations: Int
    public var touchIDEnabled: Bool
    public var autoLockMinutes: Int
}

/// At-rest encryption for clipboard history. AES-256-GCM under a random data
/// key; the key is wrapped with PBKDF2-HMAC-SHA256 (600k iterations) from the
/// master password. Optional Touch ID stores the raw data key in the user
/// keychain behind a biometric gate (same split design copyx ships — note:
/// adhoc-signed builds cannot use keychain ACLs, so the gate is advisory).
public final class Vault {
    public static let shared = Vault()

    public enum State: Equatable { case plaintext, locked, unlocked }
    public private(set) var state: State = .plaintext
    private var dataKey: SymmetricKey?

    /// Fired on every state change (setup/unlock/lock/remove).
    public var onChange: (() -> Void)?
    public var onAutoLock: (() -> Void)?

    public static let iterations: Int = 600_000
    private static let keychainService = "com.clipisland.app"
    private static let keychainAccount = "vault.datakey"
    private static let defaultsKey = "vault.metadata.v1"

    private let defaults: UserDefaults
    private var autoLockTask: DispatchWorkItem?

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        restoreState()
    }

    private func restoreState() {
        guard loadMetadata() != nil else {
            state = .plaintext
            return
        }
        state = .locked
    }

    // MARK: - State queries

    public var isEnabled: Bool { state != .plaintext }
    public var isUnlocked: Bool { state == .unlocked }

    public var metadata: VaultMetadata? { loadMetadata() }

    public static var isTouchIDAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    }

    // MARK: - Setup / unlock / lock

    /// Enables encryption and re-encrypts nothing yet — the store migrates
    /// its items afterwards via `migrateAll(enabled:)` while unlocked.
    public func setup(password: String) throws {
        guard state == .plaintext else { throw VaultError.alreadySetup }
        guard password.count >= 4 else { throw VaultError.wrongPassword }
        let dataKey = SymmetricKey(size: .bits256)
        var salt = Data(count: 16)
        _ = salt.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
        let wrapKey = Self.pbkdf2(password: password, salt: salt, iterations: Self.iterations)
        let sealed = try AES.GCM.seal(dataKey.withUnsafeBytes { Data($0) }, using: wrapKey).combined!
        let meta = VaultMetadata(
            salt: salt, wrappedDataKey: sealed,
            iterations: Self.iterations, touchIDEnabled: false, autoLockMinutes: 15
        )
        try persist(meta)
        self.dataKey = dataKey
        state = .unlocked
        onChange?()
        log("vault enabled")
    }

    public func unlock(password: String) throws {
        guard let meta = loadMetadata() else { throw VaultError.notSetup }
        let wrapKey = Self.pbkdf2(password: password, salt: meta.salt, iterations: meta.iterations)
        let box = try AES.GCM.SealedBox(combined: meta.wrappedDataKey)
        let raw: Data
        do {
            raw = try AES.GCM.open(box, using: wrapKey)
        } catch {
            throw VaultError.wrongPassword
        }
        dataKey = SymmetricKey(data: raw)
        state = .unlocked
        onChange?()
        scheduleAutoLock()
    }

    /// Touch ID gate, then the raw data key from the keychain.
    public func unlockTouchID() throws {
        guard let meta = loadMetadata(), meta.touchIDEnabled else { throw VaultError.notSetup }
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            throw VaultError.biometryUnavailable
        }
        var authError: NSError?
        let semaphore = DispatchSemaphore(value: 0)
        var success = false
        context.evaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            localizedReason: "解锁 ClipIsland 剪贴板历史"
        ) { ok, err in
            success = ok
            authError = err as NSError?
            semaphore.signal()
        }
        semaphore.wait()
        guard success else {
            throw VaultError.biometryFailed(authError?.localizedDescription ?? "认证失败")
        }
        guard let raw = keychainLoad() else { throw VaultError.keychainUnavailable(errSecItemNotFound) }
        dataKey = SymmetricKey(data: raw)
        state = .unlocked
        onChange?()
        scheduleAutoLock()
    }

    public func lock() {
        guard state == .unlocked else { return }
        dataKey = nil
        autoLockTask?.cancel()
        state = .locked
        onChange?()
        log("vault locked")
    }

    // MARK: - Password lifecycle

    public func changePassword(current: String, new: String) throws {
        try unlock(password: current)
        guard let key = dataKey, let meta = loadMetadata() else { throw VaultError.locked }
        guard new.count >= 4 else { throw VaultError.wrongPassword }
        var salt = Data(count: 16)
        _ = salt.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
        let wrapKey = Self.pbkdf2(password: new, salt: salt, iterations: Self.iterations)
        let sealed = try AES.GCM.seal(key.withUnsafeBytes { Data($0) }, using: wrapKey).combined!
        var updated = meta
        updated.salt = salt
        updated.wrappedDataKey = sealed
        try persist(updated)
        if updated.touchIDEnabled { _ = keychainSave(key.withUnsafeBytes { Data($0) }) }
        log("vault password changed")
    }

    /// Disables encryption entirely; the store migrates items back to
    /// plaintext first (via onChangeVaultEnabled while the key is alive).
    public func removePassword(current: String) throws {
        try unlock(password: current)
        wipeMetadata()
    }

    /// Removes vault metadata and returns to plaintext mode. Call only after
    /// the store has decrypted everything.
    public func wipeMetadata() {
        defaults.removeObject(forKey: Self.defaultsKey)
        keychainDelete()
        dataKey = nil
        state = .plaintext
        onChange?()
        log("vault removed")
    }

    // MARK: - Touch ID

    public func enableTouchID() throws {
        guard let key = dataKey else { throw VaultError.locked }
        let status = keychainSave(key.withUnsafeBytes { Data($0) })
        guard status == errSecSuccess else { throw VaultError.keychainUnavailable(status) }
        if var meta = loadMetadata() {
            meta.touchIDEnabled = true
            try persist(meta)
        }
        log("touch id unlock enabled")
    }

    public func disableTouchID() throws {
        keychainDelete()
        if var meta = loadMetadata() {
            meta.touchIDEnabled = false
            try persist(meta)
        }
    }

    // MARK: - Crypto surface (requires unlocked)

    public func seal(_ data: Data) throws -> Data {
        guard let key = dataKey else { throw VaultError.locked }
        return try AES.GCM.seal(data, using: key).combined!
    }

    public func open(_ data: Data) throws -> Data {
        guard let key = dataKey else { throw VaultError.locked }
        return try AES.GCM.open(try AES.GCM.SealedBox(combined: data), using: key)
    }

    /// Keyed content hash for dedup: deterministic under the data key, leaks
    /// nothing (plain SHA256 would leak duplicate-equality at rest).
    public func keyedHash(_ data: Data) -> String? {
        guard let key = dataKey else { return nil }
        let mac = HMAC<SHA256>.authenticationCode(for: data, using: key)
        return mac.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Auto lock

    public func scheduleAutoLock() {
        autoLockTask?.cancel()
        guard let meta = loadMetadata(), meta.autoLockMinutes > 0, state == .unlocked else { return }
        let task = DispatchWorkItem { [weak self] in
            self?.lock()
            self?.onAutoLock?()
        }
        autoLockTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + TimeInterval(meta.autoLockMinutes * 60), execute: task)
    }

    public func setAutoLock(minutes: Int) throws {
        guard var meta = loadMetadata() else { throw VaultError.notSetup }
        meta.autoLockMinutes = minutes
        try persist(meta)
        scheduleAutoLock()
    }

    /// Activity from the UI (panel open/close, item actions) resets the timer.
    public func noteActivity() {
        if state == .unlocked { scheduleAutoLock() }
    }

    // MARK: - Persistence

    private func loadMetadata() -> VaultMetadata? {
        guard let data = defaults.data(forKey: Self.defaultsKey) else { return nil }
        return try? JSONDecoder().decode(VaultMetadata.self, from: data)
    }

    private func persist(_ meta: VaultMetadata) throws {
        defaults.set(try JSONEncoder().encode(meta), forKey: Self.defaultsKey)
    }

    // MARK: - Keychain (raw data key behind the Touch ID gate)

    private func keychainSave(_ data: Data) -> OSStatus {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: Self.keychainAccount,
        ]
        SecItemDelete(query as CFDictionary)
        var attrs = query
        attrs[kSecValueData as String] = data
        attrs[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(attrs as CFDictionary, nil)
    }

    private func keychainLoad() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: Self.keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    private func keychainDelete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: Self.keychainAccount,
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - KDF

    /// PBKDF2-HMAC-SHA256 via CommonCrypto. Verified against RFC test vectors
    /// in SelfTest.
    public static func pbkdf2(password: String, salt: Data, iterations: Int, keyLength: Int = 32) -> SymmetricKey {
        let passwordData = Data(password.utf8)
        var derived = Data(repeating: 0, count: keyLength)
        let status = derived.withUnsafeMutableBytes { (derivedPtr: UnsafeMutableRawBufferPointer) -> Int32 in
            salt.withUnsafeBytes { (saltPtr: UnsafeRawBufferPointer) -> Int32 in
                passwordData.withUnsafeBytes { (pwdPtr: UnsafeRawBufferPointer) -> Int32 in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        pwdPtr.bindMemory(to: Int8.self).baseAddress,
                        passwordData.count,
                        saltPtr.bindMemory(to: UInt8.self).baseAddress,
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        UInt32(iterations),
                        derivedPtr.bindMemory(to: UInt8.self).baseAddress,
                        keyLength
                    )
                }
            }
        }
        precondition(status == kCCSuccess, "PBKDF2 failed: \(status)")
        return SymmetricKey(data: derived)
    }
}

// MARK: - At-rest formats

public enum VaultCoding {
    /// Prefix marking an encrypted-at-rest text payload in the database.
    public static let textPrefix = "enc:v1:"

    public static func encodeText(_ text: String, vault: Vault) -> String? {
        guard vault.isEnabled, vault.isUnlocked else { return nil }
        guard let sealed = try? vault.seal(Data(text.utf8)) else { return nil }
        return textPrefix + sealed.base64EncodedString()
    }

    public static func decodeText(_ stored: String, vault: Vault) -> String? {
        guard stored.hasPrefix(textPrefix) else { return stored }
        guard vault.isUnlocked,
              let sealed = Data(base64Encoded: String(stored.dropFirst(textPrefix.count))),
              let opened = try? vault.open(sealed) else { return nil }
        return String(data: opened, encoding: .utf8)
    }
}
