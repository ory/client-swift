#if targetEnvironment(simulator)

import Foundation
import OryClient

/// A ``OryDeviceKeyAuthenticator`` for the Simulator, where App Attest is unavailable.
///
/// It produces a self-signed attestation chain and ECDSA signatures that the Ory backend
/// accepts **only** when "Allow relaxed attestation for testing" is enabled for the
/// project (a staging/development setting). It is not a security bypass: against a
/// production backend, where relaxed attestation is off, these are rejected.
///
/// The whole type is compiled only for the Simulator (`#if targetEnvironment(simulator)`),
/// so it can never ship in a device build. Inject it in your configuration behind the same
/// guard:
///
/// ```swift
/// let config: OryClientConfiguration = {
///     #if targetEnvironment(simulator)
///     return OryClientConfiguration(projectURL: url, deviceKeyAuthenticator: RelaxedDeviceKeyAuthenticator())
///     #else
///     return OryClientConfiguration(projectURL: url)
///     #endif
/// }()
/// ```
public struct RelaxedDeviceKeyAuthenticator: OryDeviceKeyAuthenticator {

    private let keyStore: any SimulatorDeviceKeyStorage
    private let appID: String?

    /// Creates a relaxed authenticator.
    ///
    /// - Parameters:
    ///   - keyStore: Where the mock private keys are kept. Defaults to the
    ///     Keychain-backed ``SimulatorKeyStore``. Pass an ``InMemorySimulatorKeyStore``
    ///     in test runners without a host application, where the Keychain is unavailable.
    ///   - appID: The Apple App ID (`"<TeamID>.<BundleID>"`) carried in the attestation
    ///     and assertion authenticator data. Required only when the project pins
    ///     `ios_app_ids`; without it the rpIdHash is zeros, which the server accepts
    ///     whenever pinning is off.
    public init(keyStore: any SimulatorDeviceKeyStorage = SimulatorKeyStore(), appID: String? = nil) {
        self.keyStore = keyStore
        self.appID = appID
    }

    public var isAvailable: Bool { true }

    public func attestNewKey(challenge: Data) async throws -> OryDeviceKeyAttestation {
        do {
            let attestation = try RelaxedAttestation.create(serverNonce: challenge, appID: appID)
            try await keyStore.store(privateKey: attestation.privateKey, keyID: attestation.keyID)
            return OryDeviceKeyAttestation(keyID: attestation.keyID, attestation: attestation.cbor)
        } catch {
            throw OryClientError.deviceAuthenticationFailed(underlying: RelaxedAuthenticatorError(error))
        }
    }

    public func generateAssertion(keyID: String, challenge: Data) async throws -> Data {
        do {
            guard let privateKey = try await keyStore.privateKey(keyID: keyID) else {
                throw OryClientError.deviceAuthenticationFailed(underlying: RelaxedAuthenticatorError.keyNotFound)
            }
            return try RelaxedAttestation.loginSignature(privateKey: privateKey, clientData: challenge, appID: appID)
        } catch let error as OryClientError {
            throw error
        } catch {
            throw OryClientError.deviceAuthenticationFailed(underlying: RelaxedAuthenticatorError(error))
        }
    }
}

/// A `Sendable` error carrying a relaxed-attestation failure into ``OryClientError``.
struct RelaxedAuthenticatorError: Error, Sendable, LocalizedError {
    let message: String

    static let keyNotFound = RelaxedAuthenticatorError(message: "No mock key is stored for this key id.")

    init(message: String) {
        self.message = message
    }

    init(_ error: any Error) {
        self.message = String(describing: error)
    }

    var errorDescription: String? { message }
}

#endif
