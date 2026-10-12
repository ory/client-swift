import Foundation

/// The device-authn challenge for step-up: where to submit and the server nonce to sign.
struct DeviceLoginChallenge: Sendable {
    let submitURL: URL
    let nonce: Data
}

/// The device-authn enrollment challenge and its submission URL. The enrolled key's
/// identity is derived independently from its attested public key.
struct DeviceEnrollmentChallenge: Sendable {
    let submitURL: URL
    let nonce: Data
}

/// One device key as the server lists it in the settings flow, before the client decides
/// which entry is this device.
struct DeviceKeyRecord: Sendable, Equatable {
    let clientKeyID: String
    let deviceName: String
    let createdAt: Date
    let deviceType: String
    let state: String
    let userVerification: String
}

/// The identity's enrolled device keys plus the URL a removal is submitted to.
struct DeviceKeyListing: Sendable {
    let submitURL: URL
    let keys: [DeviceKeyRecord]
}

/// The outcome of a successful device-authn step-up, before token storage happens in the
/// client.
struct DeviceLoginOutcome: Sendable {
    let session: OrySession
    let token: String?
}

/// The HPKE-sealed `pin_secret` the server returns after a PIN enrollment.
struct SealedPINSecret: Sendable {
    let enc: Data
    let ciphertext: Data
}

/// The result of a PIN enrollment: device key ids for confirming the attested key's
/// presence, and the sealed `pin_secret`.
struct DevicePINEnrollmentResult: Sendable {
    let keyIDs: Set<String>
    let sealed: SealedPINSecret
}

/// The device-authn slice of the Frontend API boundary. Takes and returns domain types
/// and throws ``OryClientError`` only, so no SDK type reaches the orchestration layer.
protocol DeviceAuthnRepository: Sendable {

    /// Creates a native settings flow and returns its nonce and submit URL.
    ///
    /// - Throws: ``OryClientError/deviceAuthenticationNotEnabled`` when the flow carries
    ///   no device-authn challenge (the method is not enabled for the project).
    func createDeviceEnrollmentChallenge(sessionToken: String) async throws -> DeviceEnrollmentChallenge

    /// Submits an attested key to register it as a `deviceauthn` credential. The server
    /// derives the key id from the attestation, so none is sent. `userVerification` declares
    /// how the key's holder is verified (`.none` for a step-up-only key, `.platform` for a
    /// biometric-gated key). Returns the identity's device key ids after enrollment so the
    /// caller can confirm the attested public key's fingerprint is present.
    func submitDeviceEnrollment(
        url: URL,
        sessionToken: String,
        attestation: Data,
        deviceName: String,
        userVerification: OryDeviceUserVerification
    ) async throws -> Set<String>

    /// Creates an AAL2 native login flow and extracts its device-authn challenge.
    ///
    /// - Throws: ``OryClientError/deviceAuthenticationNotEnabled`` when the flow carries
    ///   no device-authn challenge (the identity has no device credential to step up with).
    func createDeviceLoginChallenge(sessionToken: String) async throws -> DeviceLoginChallenge

    /// Submits a signed challenge to step the session up to AAL2. A PIN key also submits its
    /// `pinProof`; a signature-only key passes `nil`.
    func submitDeviceLogin(
        url: URL,
        sessionToken: String,
        clientKeyID: String,
        signature: Data,
        pinProof: Data?
    ) async throws -> DeviceLoginOutcome

    /// Creates a native settings flow and returns its submit URL, for removing a key.
    func createDeviceRemovalFlow(sessionToken: String) async throws -> URL

    /// Lists the identity's enrolled device keys, with the URL to submit a removal to.
    ///
    /// The settings flow is the only place the server exposes this: each key is rendered as a
    /// removal node whose label context carries the key's metadata.
    func listDeviceKeys(sessionToken: String) async throws -> DeviceKeyListing

    /// Removes the `deviceauthn` credential for the given key.
    func submitDeviceRemoval(url: URL, sessionToken: String, clientKeyID: String) async throws

    /// Enrolls a PIN-protected key: submits the attestation plus the HPKE transport public
    /// key, and returns the device key ids afterwards together with the sealed `pin_secret`.
    func submitDevicePINEnrollment(
        url: URL,
        sessionToken: String,
        attestation: Data,
        deviceName: String,
        transportPublicKey: Data
    ) async throws -> DevicePINEnrollmentResult

    /// Creates a first-factor native login flow for passwordless device login (PIN or
    /// biometric) — no session token, since the user is not signed in yet.
    func createDeviceFirstFactorLoginChallenge() async throws -> DeviceLoginChallenge

    /// Submits a passwordless first-factor login with the device signature. A PIN key passes
    /// its `pinProof`; a biometric (`platform`) key passes `nil` — the server forbids a
    /// `pin_proof` on a signature-only key.
    func submitDeviceFirstFactorLogin(
        url: URL,
        clientKeyID: String,
        signature: Data,
        pinProof: Data?
    ) async throws -> DeviceLoginOutcome

    /// Rotates the `pin_secret` of an existing PIN key: submits the possession signature over
    /// `nonce ‖ transport_public_key` plus a fresh HPKE transport public key, and returns the
    /// newly sealed `pin_secret`. The device signing key is unchanged. The settings flow that
    /// produced `url` must be privileged (AAL2).
    func submitDevicePINRotation(
        url: URL,
        sessionToken: String,
        clientKeyID: String,
        signature: Data,
        transportPublicKey: Data
    ) async throws -> SealedPINSecret
}
