#if targetEnvironment(simulator)

import CryptoKit
import Foundation
import Security

/// Where ``RelaxedDeviceKeyAuthenticator`` keeps the mock leaf private keys it signs
/// with, keyed by their derived key id.
///
/// The default is ``SimulatorKeyStore`` (the Simulator's Keychain), which survives app
/// relaunches like the Secure Enclave key it stands in for. Inject
/// ``InMemorySimulatorKeyStore`` where the Keychain is unavailable — most notably in
/// test runners without a host application, where every Keychain call fails with
/// `errSecMissingEntitlement` (-34018).
public protocol SimulatorDeviceKeyStorage: Sendable {

    /// Stores `privateKey` under `keyID`, replacing any previous key with that id.
    func store(privateKey: P256.Signing.PrivateKey, keyID: String) async throws

    /// Returns the key stored under `keyID`, or `nil` when none is stored.
    func privateKey(keyID: String) async throws -> P256.Signing.PrivateKey?
}

/// Persists the mock leaf private key in the Simulator's Keychain across app launches.
///
/// On device the private key lives in the Secure Enclave; on the Simulator there is none,
/// so the relaxed authenticator keeps the generated key here to reproduce signatures for
/// later step-up. This is throwaway test-key material on a Simulator only — never a real
/// credential.
public struct SimulatorKeyStore: SimulatorDeviceKeyStorage {

    private let service = "com.ory.client.simulator.device-key"

    /// Creates the Keychain-backed store.
    public init() {}

    public func store(privateKey: P256.Signing.PrivateKey, keyID: String) async throws {
        let data = privateKey.rawRepresentation

        let updateStatus = SecItemUpdate(
            baseQuery(keyID: keyID) as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecSuccess {
            return
        }
        if updateStatus != errSecItemNotFound {
            throw SimulatorKeyStoreError.keychain(status: updateStatus)
        }

        var attributes = baseQuery(keyID: keyID)
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let addStatus = SecItemAdd(attributes as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw SimulatorKeyStoreError.keychain(status: addStatus)
        }
    }

    public func privateKey(keyID: String) async throws -> P256.Signing.PrivateKey? {
        var query = baseQuery(keyID: keyID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        switch status {
        case errSecSuccess:
            guard let data = item as? Data else {
                throw SimulatorKeyStoreError.unexpectedData
            }
            return try P256.Signing.PrivateKey(rawRepresentation: data)
        case errSecItemNotFound:
            return nil
        default:
            throw SimulatorKeyStoreError.keychain(status: status)
        }
    }

    private func baseQuery(keyID: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: keyID,
        ]
    }
}

/// A non-persistent ``SimulatorDeviceKeyStorage`` for environments without Keychain
/// access — for example `swift-testing`/XCTest runners without a host application,
/// where Keychain calls fail with `errSecMissingEntitlement` (-34018).
///
/// Keys live for the process's lifetime, which is exactly a test run. Share one
/// instance between every ``RelaxedDeviceKeyAuthenticator`` in the process (as the
/// Keychain would be shared), so clients that share enrollment state can reproduce
/// each other's signatures:
///
/// ```swift
/// let keys = InMemorySimulatorKeyStore()
/// let authenticator = RelaxedDeviceKeyAuthenticator(keyStore: keys)
/// ```
public actor InMemorySimulatorKeyStore: SimulatorDeviceKeyStorage {

    private var keys: [String: Data] = [:]

    /// Creates an empty store.
    public init() {}

    public func store(privateKey: P256.Signing.PrivateKey, keyID: String) async throws {
        keys[keyID] = privateKey.rawRepresentation
    }

    public func privateKey(keyID: String) async throws -> P256.Signing.PrivateKey? {
        try keys[keyID].map { try P256.Signing.PrivateKey(rawRepresentation: $0) }
    }
}

enum SimulatorKeyStoreError: Error, Sendable {
    case unexpectedData
    case keychain(status: OSStatus)
}

#endif
