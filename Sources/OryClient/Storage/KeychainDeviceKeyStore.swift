import Foundation
import Security

/// The default ``OryDeviceKeyStore``, backed by the system Keychain.
///
/// The key is stored as a JSON generic-password item scoped to a service identifier,
/// protected with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`: device authentication
/// runs in the foreground only, and the record — including the PIN-sealed secret — must
/// never leave this device via an encrypted backup restore. It shares the storage model
/// of ``OryKeychainSessionStorage`` but a distinct account, so the two never collide.
public struct OryKeychainDeviceKeyStore: OryDeviceKeyStore {

    private let service: String
    private let account: String
    private let accessGroup: String?

    /// The shared operation scope for this Keychain service. Stores across access groups
    /// coordinate together because a query without an access group can match their items.
    public var deviceOperationScope: String {
        let encodedService = Data(service.utf8).base64EncodedString()
        return "ory.keychain-device-key:\(encodedService)"
    }

    /// Creates a Keychain-backed device key store.
    ///
    /// - Parameters:
    ///   - service: The Keychain service identifier the item is scoped to. Defaults to
    ///     `"com.ory.client"`.
    ///   - accessGroup: A Keychain access group for sharing the key with app extensions,
    ///     or `nil` for the app's default access. Passing one also turns off the
    ///     fresh-install cleanup described below, because shared state cannot be attributed
    ///     to a single install.
    public init(service: String = "com.ory.client", accessGroup: String? = nil) {
        self.service = service
        self.account = "device_key"
        self.accessGroup = accessGroup
        clearStaleKeyOnFreshInstall()
    }

    /// Keychain items survive app deletion, but the Secure Enclave key they reference does
    /// not — leaving a stored id that points at a key that no longer exists. Clearing the
    /// record on a fresh install turns that into a clean "not enrolled" state instead of a
    /// signature failure the first time the user tries to sign in.
    private func clearStaleKeyOnFreshInstall() {
        KeychainInstallMarker.clearStaleStateOnFreshInstall(
            markerKey: "\(service).\(account).install-marker",
            accessGroup: accessGroup
        ) {
            SecItemDelete(baseQuery() as CFDictionary)
        }
    }

    public func enrolledKey() async throws -> OryStoredDeviceKey? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        switch status {
        case errSecSuccess:
            // A record this build cannot read — written by a newer SDK, or corrupt — reads as
            // "not enrolled" rather than as a storage failure. The app then offers enrollment,
            // which overwrites it; reporting an error instead would leave every device-authn
            // entry point permanently broken with nothing the user could do about it.
            guard let data = item as? Data,
                  let key = try? JSONDecoder().decode(OryStoredDeviceKey.self, from: data),
                  key.schemaVersion == OryStoredDeviceKey.currentSchemaVersion
            else {
                return nil
            }
            return key
        case errSecItemNotFound:
            return nil
        default:
            throw OryKeychainError.unhandled(status: status)
        }
    }

    public func store(_ key: OryStoredDeviceKey) async throws {
        let data = try JSONEncoder().encode(key)

        if try update(data) { return }

        var attributes = baseQuery()
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

        let addStatus = SecItemAdd(attributes as CFDictionary, nil)
        switch addStatus {
        case errSecSuccess:
            return
        case errSecDuplicateItem:
            // Another writer inserted the item between the update and the add. Updating now
            // succeeds, so a concurrent first write does not surface as a storage failure.
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
            // `kSecAttrAccessible` mean anything at all — the legacy file-based Keychain
            // ignores it, silently dropping the "never leaves this device" guarantee.
            kSecUseDataProtectionKeychain as String: true,
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }
}
