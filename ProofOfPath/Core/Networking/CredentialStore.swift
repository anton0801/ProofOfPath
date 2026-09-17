//
//  CredentialStore.swift
//  ProofOfPath
//
//  The anonymous device identity and the current API session, in the Keychain.
//

import Foundation
import Security

/// A random device id and a 256-bit secret, created once per install and kept
/// in the Keychain. Together they are the account's only credential: the
/// server stores a hash of the secret, so an id alone cannot sign in.
struct DeviceCredentials: Equatable, Sendable {
    let deviceID: UUID
    let secret: String
}

/// A bearer token issued by `POST /auth/device`.
struct APISession: Codable, Equatable, Sendable {
    let token: String
    let userID: String
    let expiresAt: Date
}

/// Generic-password Keychain items for one service.
///
/// Items use `kSecAttrAccessibleAfterFirstUnlock`: readable in the background
/// after the first unlock, and carried to a new phone by an encrypted backup,
/// so restoring a device keeps the same account and its data.
struct KeychainStore: Sendable {

    let service: String

    func data(for account: String) -> Data? {
        var query = baseQuery(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    @discardableResult
    func set(_ data: Data, for account: String) -> Bool {
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let status = SecItemUpdate(baseQuery(account) as CFDictionary, attributes as CFDictionary)
        if status == errSecSuccess { return true }
        guard status == errSecItemNotFound else { return false }
        var item = baseQuery(account)
        item.merge(attributes) { _, new in new }
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    func remove(_ account: String) {
        SecItemDelete(baseQuery(account) as CFDictionary)
    }

    private func baseQuery(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}

/// Reads and writes the device credentials and the session.
///
/// Access is serialised by a lock: the API client (an actor) and the store on
/// the main actor both read the current user id.
final class CredentialStore: @unchecked Sendable {

    private enum Key {
        static let deviceID = "device-id"
        static let deviceSecret = "device-secret"
        static let session = "session"
        static let lastUserID = "last-user-id"
    }

    private let keychain: KeychainStore
    private let lock = NSLock()

    init(keychain: KeychainStore = KeychainStore(service: "com.proofofpath.api")) {
        self.keychain = keychain
    }

    /// The install's credentials, created on first use.
    func deviceCredentials() throws -> DeviceCredentials {
        lock.lock()
        defer { lock.unlock() }

        if let idData = keychain.data(for: Key.deviceID),
           let idText = String(data: idData, encoding: .utf8),
           let deviceID = UUID(uuidString: idText),
           let secretData = keychain.data(for: Key.deviceSecret),
           let secret = String(data: secretData, encoding: .utf8),
           secret.count == 64 {
            return DeviceCredentials(deviceID: deviceID, secret: secret)
        }

        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw APIError.credentialsUnavailable
        }
        let credentials = DeviceCredentials(
            deviceID: UUID(),
            secret: bytes.map { String(format: "%02x", $0) }.joined()
        )
        guard keychain.set(Data(credentials.deviceID.uuidString.utf8), for: Key.deviceID),
              keychain.set(Data(credentials.secret.utf8), for: Key.deviceSecret)
        else {
            throw APIError.credentialsUnavailable
        }
        return credentials
    }

    var session: APISession? {
        lock.lock()
        defer { lock.unlock() }
        guard let data = keychain.data(for: Key.session) else { return nil }
        return try? POPJSON.makeDecoder().decode(APISession.self, from: data)
    }

    func store(_ session: APISession) {
        lock.lock()
        defer { lock.unlock() }
        if let data = try? POPJSON.makeEncoder().encode(session) {
            keychain.set(data, for: Key.session)
        }
        keychain.set(Data(session.userID.utf8), for: Key.lastUserID)
    }

    func clearSession() {
        lock.lock()
        defer { lock.unlock() }
        keychain.remove(Key.session)
    }

    /// The account the offline cache belongs to. Survives an expired token.
    var lastUserID: String? {
        lock.lock()
        defer { lock.unlock() }
        return keychain.data(for: Key.lastUserID).flatMap { String(data: $0, encoding: .utf8) }
    }

    /// Forgets the session and the account link, keeping the device identity.
    func forgetAccount() {
        lock.lock()
        defer { lock.unlock() }
        keychain.remove(Key.session)
        keychain.remove(Key.lastUserID)
    }

    /// Forgets everything, so the next launch signs in as a brand-new device.
    func resetDevice() {
        lock.lock()
        defer { lock.unlock() }
        for key in [Key.deviceID, Key.deviceSecret, Key.session, Key.lastUserID] {
            keychain.remove(key)
        }
    }
}
