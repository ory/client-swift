import Foundation

/// Enrolling this device as an authenticator, and querying what is enrolled.
///
/// `OryClient` rejects overlapping device operations sharing a key-store scope with
/// ``OryClientError/deviceAuthenticationOperationInProgress``. Offer a retry after the
/// active operation finishes; the rejected call has no side effects.
/// Enrollment queries remain read-only snapshots and can run during an active operation.
public protocol OryDeviceEnrollment: Sendable {

    /// Whether this device has an enrolled key, and how that key verifies its holder.
    ///
    /// Use it to render both the sign-in screen and a two-factor settings screen:
    ///
    /// ```swift
    /// switch try await client.deviceEnrollment() {
    /// case .notEnrolled:
    ///     // Offer "Set up this device".
    /// case .enrolled(.pin):
    ///     // Offer PIN sign-in: loginWithDevice(pin:).
    /// case .enrolled(.platform):
    ///     // Offer biometric sign-in: loginWithDevice().
    /// default:
    ///     // A second factor only: authenticateWithDevice() satisfies AAL2 prompts.
    /// }
    /// ```
    ///
    /// The state changes when ``enrollDevice(name:protection:)`` completes, and returns to
    /// ``OryDeviceEnrollmentState/notEnrolled`` after ``OryDeviceManagement/removeDevice()`` or
    /// ``OryDeviceManagement/forgetDevice()``.
    ///
    /// This reflects local state only. A key can go stale — for example after the app is
    /// reinstalled, the stored id may remain while the Secure Enclave key is gone; a later
    /// ``OryDeviceStepUp/authenticateWithDevice(pin:)`` then fails and the user should enroll
    /// again.
    ///
    /// - Returns: ``OryDeviceEnrollmentState/notEnrolled`` when no key is stored for this device,
    ///   otherwise ``OryDeviceEnrollmentState/enrolled(_:)`` with the key's verification.
    /// - Throws: ``OryClientError/storage(underlying:)`` if the store cannot be read.
    func deviceEnrollment() async throws -> OryDeviceEnrollmentState

    /// Whether this device has an enrolled key for the account of `session`.
    ///
    /// A device holds a key for one account at a time. Use this variant once the user is signed
    /// in — for example on a two-factor settings screen — so a key enrolled by another account on
    /// this device is not offered as theirs:
    ///
    /// ```swift
    /// let session = try await client.currentSession()
    /// switch try await client.deviceEnrollment(for: session) {
    /// case .enrolledForAnotherAccount:
    ///     // Offer "Use this device for your account", which calls forgetDevice() and enrolls.
    /// case .notEnrolled:
    ///     // Offer "Set up this device".
    /// default:
    ///     // Enrolled for this account.
    /// }
    /// ```
    ///
    /// Like ``deviceEnrollment()`` it reads local state only.
    ///
    /// - Parameter session: The signed-in session, from ``OrySessionManagement/currentSession()``.
    /// - Returns: ``OryDeviceEnrollmentState/enrolledForAnotherAccount`` when the key belongs to
    ///   another identity, otherwise the same value as ``deviceEnrollment()``.
    /// - Throws: ``OryClientError/storage(underlying:)`` if the store cannot be read.
    func deviceEnrollment(for session: OrySession) async throws -> OryDeviceEnrollmentState

    /// Enrolls this device as an authenticator, binding a new key to the Secure Enclave.
    ///
    /// Call this for a signed-in user (an AAL1 session is enough). The client generates a
    /// hardware-backed key, proves it was created on genuine hardware, and registers it with
    /// Ory as a `deviceauthn` credential. The key never leaves the Secure Enclave, and its
    /// identifier is stored for you. A device holds one key per install: enrolling again
    /// replaces the previous key locally.
    ///
    /// `protection` decides what the device can do afterwards:
    ///
    /// - ``OryDeviceProtection/none``: a second factor only. The user steps up to AAL2 with
    ///   ``OryDeviceStepUp/authenticateWithDevice(pin:)`` without a password or code.
    /// - ``OryDeviceProtection/pin(_:)``: also passwordless sign-in with the PIN through
    ///   ``OryDeviceLogin/loginWithDevice(pin:)``. The client protects a server-issued secret
    ///   with the PIN; the PIN itself is never sent.
    /// - ``OryDeviceProtection/biometrics``: also passwordless sign-in after Face ID, Touch ID,
    ///   or Optic ID through ``OryDeviceLogin/loginWithDevice(pin:)``. The user confirms
    ///   biometrics during enrollment. An App Attest key cannot itself be gated behind
    ///   biometrics, so `OryClient` enforces the gate: it prompts before every signature with
    ///   this key, and the iOS backend trusts that declaration.
    ///
    /// Guard the call with ``OryDeviceCapabilities/availableDeviceAuthenticationMethods``:
    /// it is empty where enrollment cannot succeed, such as the Simulator, and contains
    /// ``OryDeviceAuthenticationMethod/biometric`` only when biometrics can be used.
    ///
    /// ```swift
    /// let methods = client.availableDeviceAuthenticationMethods
    /// if methods.contains(.biometric) {
    ///     try await client.enrollDevice(name: UIDevice.current.name, protection: .biometrics)
    /// } else if methods.contains(.pin) {
    ///     try await client.enrollDevice(name: UIDevice.current.name, protection: .pin(chosenPIN))
    /// }
    /// ```
    ///
    /// - Important: Passwordless biometric sign-in as a **first factor on iOS** requires the
    ///   project's `ios_biometric_first_factor` setting, because App Attest cannot prove
    ///   biometric gating. Without it, a biometric key still works as a second factor, but
    ///   ``OryDeviceLogin/loginWithDevice(pin:)`` is rejected by the server.
    /// - Important: `OryClient` does **not** validate a PIN. See ``OryDeviceProtection/pin(_:)``.
    ///
    /// - Parameters:
    ///   - name: A human-readable device name shown to the user in account settings, for
    ///     example "My iPhone".
    ///   - protection: How the key verifies the person holding the device. Defaults to
    ///     ``OryDeviceProtection/none``.
    /// The key belongs to the signed-in account. When this device already holds a key for
    /// another account, enrollment fails with
    /// ``OryClientError/deviceAuthenticationEnrolledForAnotherAccount`` before anything changes;
    /// call ``OryDeviceManagement/forgetDevice()`` first to move device sign-in to this account.
    ///
    /// - Throws: ``OryClientError/deviceAuthenticationUnavailable`` on the Simulator or an
    ///   unsupported device, ``OryClientError/deviceAuthenticationBiometricsUnavailable`` when
    ///   `protection` is ``OryDeviceProtection/biometrics`` and biometrics cannot be used,
    ///   ``OryClientError/deviceAuthenticationCancelled`` if the user declines the biometric
    ///   prompt, ``OryClientError/notAuthenticated`` if no user is signed in,
    ///   ``OryClientError/deviceAuthenticationNotEnabled`` if the project does not offer device
    ///   authentication, or another ``OryClientError`` on attestation, network, or storage
    ///   failure.
    func enrollDevice(name: String, protection: OryDeviceProtection) async throws
}

extension OryDeviceEnrollment {

    /// The default ignores the session's account and returns ``deviceEnrollment()``.
    /// ``OryClient`` provides the real implementation.
    public func deviceEnrollment(for session: OrySession) async throws -> OryDeviceEnrollmentState {
        try await deviceEnrollment()
    }

    /// Enrolls this device as a second factor, with ``OryDeviceProtection/none``.
    ///
    /// See ``enrollDevice(name:protection:)``.
    public func enrollDevice(name: String) async throws {
        try await enrollDevice(name: name, protection: .none)
    }
}
