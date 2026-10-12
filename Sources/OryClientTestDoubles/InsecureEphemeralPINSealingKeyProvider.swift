import Foundation
import OryClient
import Security

/// A non-persistent ``OryPINSealingKeyProvider`` **for tests only**: software P-256 keys
/// held in memory instead of Secure Enclave keys in the Keychain.
///
/// > Important: This removes the hardware protection of the PIN secret at rest. A
/// > release build that uses it stores PIN material under a key that never touches the
/// > Secure Enclave, which defeats the point of the PIN recipe. Never reach for it
/// > outside a test target.
///
/// Use it where the Keychain is unavailable — most notably `swift-testing`/XCTest
/// runners without a host application, where creating a permanent key fails with
/// `errSecMissingEntitlement` (-34018). Keys live for the process's lifetime; share
/// one instance between clients that share a device key store, so PIN material
/// sealed by one client can be unsealed by another:
///
/// ```swift
/// let sealingKeys = InsecureEphemeralPINSealingKeyProvider()
/// let config = OryClientConfiguration(
///     projectURL: url,
///     pinSealingKeyProvider: sealingKeys
/// )
/// ```
public final class InsecureEphemeralPINSealingKeyProvider: OryPINSealingKeyProvider, @unchecked Sendable {

    private let lock = NSLock()
    private var keys: [String: SecKey] = [:]
    private var deleted: [String] = []

    /// Creates an empty provider.
    public init() {}

    public func createKey(tag: String) throws -> SecKey {
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

    public func key(tag: String) throws -> SecKey? {
        lock.lock()
        defer { lock.unlock() }
        return keys[tag]
    }

    public func deleteKey(tag: String) {
        lock.lock()
        defer { lock.unlock() }
        keys[tag] = nil
        deleted.append(tag)
    }

    /// Tags of keys currently held, for asserting creation and deletion hygiene.
    public var storedTags: Set<String> {
        lock.lock()
        defer { lock.unlock() }
        return Set(keys.keys)
    }

    /// Tags passed to ``deleteKey(tag:)``, in call order.
    public var deletedTags: [String] {
        lock.lock()
        defer { lock.unlock() }
        return deleted
    }
}
