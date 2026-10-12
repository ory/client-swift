import Foundation
import Security

/// Supplies the hardware-backed key pair that wraps the PIN-encrypted `pin_secret`
/// (the outer ECIES layer of ``OryProtectedPINSecret/sealed``). One key exists per seal:
/// ``DevicePINVault/protect(pinSecret:pin:)`` creates a fresh key under a unique tag,
/// and the tag travels with the artifacts.
///
/// Keeping the key behind a seam lets unit tests substitute an ephemeral software key:
/// Secure Enclave keys cannot be created from a plain `swift test` process.
public protocol OryPINSealingKeyProvider: Sendable {

    /// Creates and stores a fresh key under `tag`. Tags are unique per seal, so an
    /// existing key under the same tag is a programming error, not a case to handle.
    func createKey(tag: String) throws -> SecKey

    /// Returns the key stored under `tag`, or `nil` when no such key exists.
    func key(tag: String) throws -> SecKey?

    /// Removes the key stored under `tag`. Missing keys are ignored: deletion is
    /// best-effort hygiene when PIN material is replaced or forgotten.
    func deleteKey(tag: String)
}

/// The production ``OryPINSealingKeyProvider``: a permanent P-256 key in the Secure Enclave,
/// restricted to private-key usage and readable only while the device is unlocked
/// (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`). No biometry flag — the PIN itself is
/// the knowledge factor; this key only binds the blob to this device's hardware.
///
/// The Simulator has no Secure Enclave, so Simulator builds create the same key as a
/// software key with identical access control. Device builds always use the enclave;
/// there is no runtime fallback that could silently downgrade a real device.
public struct OrySecureEnclavePINSealingKeyProvider: OryPINSealingKeyProvider {

    /// Creates the production provider.
    public init() {}

    public func createKey(tag: String) throws -> SecKey {
        var accessError: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            [.privateKeyUsage],
            &accessError
        ) else {
            throw OryClientError.deviceAuthenticationFailed(
                underlying: UnderlyingError(accessError!.takeRetainedValue() as Error)
            )
        }

        var attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String: Data(tag.utf8),
                kSecAttrAccessControl as String: access,
            ] as [String: Any],
        ]
        #if !targetEnvironment(simulator)
        attributes[kSecAttrTokenID as String] = kSecAttrTokenIDSecureEnclave
        #endif

        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            throw OryClientError.deviceAuthenticationFailed(
                underlying: UnderlyingError(error!.takeRetainedValue() as Error)
            )
        }
        return key
    }

    public func key(tag: String) throws -> SecKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrApplicationTag as String: Data(tag.utf8),
            kSecReturnRef as String: true,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let item, CFGetTypeID(item) == SecKeyGetTypeID() else {
                throw OryClientError.deviceAuthenticationFailed(underlying: PINSealingKeyError.unexpectedItem)
            }
            return (item as! SecKey)
        case errSecItemNotFound:
            return nil
        default:
            throw OryClientError.deviceAuthenticationFailed(underlying: PINSealingKeyError.keychain(status: status))
        }
    }

    public func deleteKey(tag: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: Data(tag.utf8),
        ]
        SecItemDelete(query as CFDictionary)
    }
}

private enum PINSealingKeyError: Error, Sendable, LocalizedError {
    case unexpectedItem
    case keychain(status: OSStatus)

    var errorDescription: String? {
        switch self {
        case .unexpectedItem:
            return "The PIN sealing key stored in the Keychain has an unexpected type."
        case let .keychain(status):
            return "Reading the PIN sealing key failed (status \(status))."
        }
    }
}
