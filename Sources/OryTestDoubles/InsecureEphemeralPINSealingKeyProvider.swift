import Foundation
import Ory
import Security

/// A non-persistent ``OryPINSealingKeyProvider``: software P-256 keys held in memory instead
/// of Secure Enclave keys in the Keychain. Integrators reach it through
/// `OryClientConfiguration.usingInsecurePINSealingForTests()`; the package's own tests may
/// create separate instances.
package final class InsecureEphemeralPINSealingKeyProvider: OryPINSealingKeyProvider, @unchecked Sendable {

    private let lock = NSLock()
    private var keys: [String: SecKey] = [:]
    private var deleted: [String] = []

    /// The provider `usingInsecurePINSealingForTests()` installs, shared like the Keychain.
    package static let shared = InsecureEphemeralPINSealingKeyProvider()

    /// Creates an empty provider.
    package init() {}

    package func createKey(tag: String) throws -> SecKey {
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
        ]
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            throw error!.takeRetainedValue() as Error
        }
        lock.lock()
        defer { lock.unlock() }
        keys[tag] = key
        return key
    }

    package func key(tag: String) throws -> SecKey? {
        lock.lock()
        defer { lock.unlock() }
        return keys[tag]
    }

    package func deleteKey(tag: String) {
        lock.lock()
        defer { lock.unlock() }
        keys[tag] = nil
        deleted.append(tag)
    }

    /// Tags of keys currently held, for asserting creation and deletion hygiene.
    package var storedTags: Set<String> {
        lock.lock()
        defer { lock.unlock() }
        return Set(keys.keys)
    }

    /// Tags passed to ``deleteKey(tag:)``, in call order.
    package var deletedTags: [String] {
        lock.lock()
        defer { lock.unlock() }
        return deleted
    }
}
