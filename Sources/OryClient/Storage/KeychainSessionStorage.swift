import Foundation
import Security

/// The default ``OrySessionStorage``, backed by the system Keychain.
///
/// The session token is stored as a generic password item scoped to a service
/// identifier. It is protected with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`,
/// so it is readable after the device has been unlocked once following a reboot —
/// including from the background — but never leaves this device: it is excluded from
/// backups, so restoring a backup onto another device does not carry the session with it.
///
/// The token is also cleared on a fresh install, so deleting the app ends the session
/// rather than leaving the user signed in after a reinstall.
///
/// ```swift
/// let storage = OryKeychainSessionStorage()                       // default service
/// let shared = OryKeychainSessionStorage(service: "com.acme.app") // custom service
/// ```
///
/// To share a token between your app and its extensions, pass the `accessGroup`
/// that matches your Keychain Sharing entitlement.
public struct OryKeychainSessionStorage: OrySessionStorage {

    private let service: String
    private let account: String
    private let accessGroup: String?

    /// Creates a Keychain-backed storage.
    ///
    /// - Parameters:
    ///   - service: The Keychain service the token is scoped to. Defaults to
    ///     `"com.ory.client"`. Use a value unique to your app to avoid collisions.
    ///   - accessGroup: An optional Keychain access group for sharing the token with
    ///     app extensions. Defaults to `nil` (the app's private group). Passing one also
    ///     turns off the fresh-install clearing, because a token shared with another
    ///     process cannot be attributed to a single install.
    public init(service: String = "com.ory.client", accessGroup: String? = nil) {
        self.service = service
        self.account = "session_token"
        self.accessGroup = accessGroup
        clearStaleTokenOnFreshInstall()
    }

    /// Keychain items survive app deletion, so without this a reinstall would start signed in
    /// with a token the user never re-entered a credential for — while the device key enrolled
    /// alongside it is gone, because its Secure Enclave key died with the app.
    private func clearStaleTokenOnFreshInstall() {
        KeychainInstallMarker.clearStaleStateOnFreshInstall(
            markerKey: "\(service).\(account).install-marker",
            accessGroup: accessGroup
        ) {
            SecItemDelete(baseQuery() as CFDictionary)
        }
    }

    public func sessionToken() async throws -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        switch status {
        case errSecSuccess:
            guard let data = item as? Data, let token = String(data: data, encoding: .utf8) else {
                throw OryKeychainError.unexpectedData
            }
            return token
        case errSecItemNotFound:
            return nil
        default:
            throw OryKeychainError.unhandled(status: status)
        }
    }

    public func store(sessionToken: String) async throws {
        let data = Data(sessionToken.utf8)

        // Try to update an existing item before inserting, so we never duplicate.
        if try update(data) { return }

        var attributes = baseQuery()
        attributes[kSecValueData as String] = data
        // AfterFirstUnlock (rather than WhenUnlocked) so background work can refresh a session
        // after a reboot; ThisDeviceOnly so a backup restored onto another device cannot replay
        // it. Device keys and PIN material use WhenUnlockedThisDeviceOnly.
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let addStatus = SecItemAdd(attributes as CFDictionary, nil)
        switch addStatus {
        case errSecSuccess:
            return
        case errSecDuplicateItem:
            // Another writer inserted the item between the update and the add — two sign-ins
            // racing, for example. Updating now succeeds.
            guard try update(data) else {
                throw OryKeychainError.unhandled(status: addStatus)
            }
        default:
            throw OryKeychainError.unhandled(status: addStatus)
        }
    }

    /// Returns `true` when an existing item was updated, `false` when there was none.
    private func update(_ data: Data) throws -> Bool {
        let status = SecItemUpdate(
            baseQuery() as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        switch status {
        case errSecSuccess: return true
        case errSecItemNotFound: return false
        default: throw OryKeychainError.unhandled(status: status)
        }
    }

    public func clear() async throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw OryKeychainError.unhandled(status: status)
        }
    }

    private func baseQuery() -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            // Selects the data-protection Keychain. No-op on iOS; on macOS it is what makes
            // `kSecAttrAccessible` mean anything at all.
            kSecUseDataProtectionKeychain as String: true,
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }
}

/// A failure raised by ``OryKeychainSessionStorage`` while accessing the Keychain.
///
/// ``OryClient`` wraps these in ``OryClientError/storage(underlying:)``.
public enum OryKeychainError: Error, Sendable, Equatable {

    /// A Keychain item was found but its data could not be decoded as a token.
    case unexpectedData

    /// The Keychain returned an unexpected `OSStatus`. Inspect `status` for the
    /// platform-specific code (see `SecCopyErrorMessageString`).
    case unhandled(status: OSStatus)
}
