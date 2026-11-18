import DeviceCheck
import Foundation

/// The production ``OryDeviceKeyAuthenticator``, backed by Apple's App Attest service.
///
/// The private key is generated in and never leaves the Secure Enclave. `DeviceCheck`
/// reports the hardware as unsupported on the Simulator and on devices without App Attest,
/// which is surfaced as ``isAvailable``. This is the default authenticator, so you rarely
/// construct it directly.
///
/// Signing is **silent**: App Attest proves the device without any user prompt, and there is
/// no biometric gate. The knowledge factor is the user's PIN (see
/// ``OryDeviceProtection/pin(_:)``), so people who cannot — or prefer not
/// to — use Face ID / Touch ID are fully supported.
public struct OryAppAttestKeyAuthenticator: OryDeviceKeyAuthenticator {

    private var service: DCAppAttestService { .shared }

    /// Creates the App Attest authenticator.
    public init() {}

    public var isAvailable: Bool { service.isSupported }

    public func attestNewKey(challenge: Data) async throws -> OryDeviceKeyAttestation {
        guard service.isSupported else {
            throw OryClientError.deviceAuthenticationUnavailable
        }

        do {
            let keyID = try await service.generateKey()
            // Pass the challenge as the clientDataHash unchanged: the caller already composed it
            // (the raw nonce, or SHA256(nonce ‖ transport_public_key) for PIN keys) and the
            // backend re-hashes it with authData.
            let attestation = try await service.attestKey(keyID, clientDataHash: challenge)
            return OryDeviceKeyAttestation(keyID: keyID, attestation: attestation)
        } catch {
            throw OryClientError.deviceAuthenticationFailed(underlying: UnderlyingError(error))
        }
    }

    public func generateAssertion(keyID: String, challenge: Data) async throws -> Data {
        guard service.isSupported else {
            throw OryClientError.deviceAuthenticationUnavailable
        }

        do {
            // Pass the challenge as the clientDataHash unchanged; the backend performs the
            // composite hash itself.
            return try await service.generateAssertion(keyID, clientDataHash: challenge)
        } catch {
            throw OryClientError.deviceAuthenticationFailed(underlying: UnderlyingError(error))
        }
    }
}
