import Foundation

/// A newly created device key and the attestation that proves it was created on genuine
/// hardware. Sent to Ory to register the key as a `deviceauthn` credential.
public struct OryDeviceKeyAttestation: Sendable {

    /// The local signing-key handle, persisted for later assertions. It is separate from
    /// Ory's server-side key identifier, which the client derives from the attested key.
    public let keyID: String

    /// The App Attest CBOR blob for the server to validate. Its `attStmt.x5c` array must
    /// start with the DER certificate of the P-256 signing key. The client extracts this
    /// key before submitting enrollment and confirms its fingerprint in the response.
    public let attestation: Data

    /// Creates an attestation result.
    ///
    /// - Parameters:
    ///   - keyID: The local handle accepted by your authenticator's `generateAssertion`.
    ///   - attestation: The complete, definite-length App Attest CBOR attestation. Custom
    ///     authenticators must return the same certificate shape as App Attest; a key
    ///     identifier or arbitrary placeholder bytes cannot substitute for attestation.
    public init(keyID: String, attestation: Data) {
        self.keyID = keyID
        self.attestation = attestation
    }
}

/// The seam over the Secure Enclave / App Attest, so device authentication can be unit
/// tested without real hardware and gracefully degraded on the Simulator.
///
/// The production implementation is ``OryAppAttestKeyAuthenticator``, used by default. You
/// only conform your own type for advanced scenarios — most notably to run device
/// authentication on the Simulator, where App Attest is unavailable: inject a relaxed
/// implementation (see the `OryClientSimulator` product) via
/// ``OryClientConfiguration/deviceKeyAuthenticator``, guarded by
/// `#if targetEnvironment(simulator)` so it never ships in a device build.
public protocol OryDeviceKeyAuthenticator: Sendable {

    /// Whether this device can perform device authentication.
    ///
    /// `false` on the Simulator, on unsupported devices, and when the App Attest
    /// capability is missing.
    var isAvailable: Bool { get }

    /// Generates a fresh Secure Enclave key and attests it against a server challenge.
    ///
    /// - Parameter challenge: The raw server nonce. Passed to App Attest unchanged — the
    ///   backend performs the composite hash itself.
    /// - Throws: ``OryClientError/deviceAuthenticationUnavailable`` when the device cannot
    ///   attest, or ``OryClientError/deviceAuthenticationFailed(underlying:)`` when the
    ///   operation fails.
    func attestNewKey(challenge: Data) async throws -> OryDeviceKeyAttestation

    /// Signs a server challenge with a previously attested key, to step up to AAL2.
    ///
    /// - Parameters:
    ///   - keyID: The identifier of a key created by ``attestNewKey(challenge:)``.
    ///   - challenge: The raw server nonce. Passed to App Attest unchanged.
    /// - Returns: The assertion (signature) for the server to verify.
    /// - Throws: ``OryClientError/deviceAuthenticationUnavailable`` when the device cannot
    ///   sign, or ``OryClientError/deviceAuthenticationFailed(underlying:)`` when the
    ///   operation fails (for example the key no longer exists).
    func generateAssertion(keyID: String, challenge: Data) async throws -> Data
}
