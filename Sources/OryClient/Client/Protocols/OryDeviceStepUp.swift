import Foundation

/// Stepping the current session up to AAL2 with this device's key.
///
/// `OryClient` rejects overlapping device operations sharing a key-store scope with
/// ``OryClientError/deviceAuthenticationOperationInProgress``. Offer a retry after the
/// active operation finishes; the rejected call has no side effects.
public protocol OryDeviceStepUp: Sendable {

    /// Steps the current session up to AAL2 using the key enrolled on this device.
    ///
    /// Call this when an action requires a second factor — for example whenever
    /// ``OrySessionManagement/currentSession()`` reports ``OryClientError/secondFactorRequired``.
    /// The client signs a server challenge with the Secure Enclave key, without a password or
    /// one-time code, and stores the upgraded session token for you, so later calls reflect
    /// AAL2. If the session is already AAL2 this returns it unchanged.
    ///
    /// The enrolled key decides how the user is verified:
    ///
    /// - A key enrolled with ``OryDeviceProtection/none`` signs silently.
    /// - A PIN key needs `pin`: it cannot step up on the signature alone.
    /// - A biometric key prompts for Face ID, Touch ID, or Optic ID. Biometric step-up does
    ///   **not** require the `ios_biometric_first_factor` project setting.
    ///
    /// `pin` is ignored for a key that is not PIN-protected. Read
    /// ``OryDeviceEnrollment/deviceEnrollment()`` to decide whether to ask for the PIN.
    ///
    /// ```swift
    /// do {
    ///     let authenticated: OryAuthenticatedSession
    ///     if try await client.deviceEnrollment() == .enrolled(.pin) {
    ///         authenticated = try await client.authenticateWithDevice(pin: enteredPIN)
    ///     } else {
    ///         authenticated = try await client.authenticateWithDevice()
    ///     }
    ///     // authenticated.session.authenticatorAssuranceLevel == .aal2
    /// } catch OryClientError.deviceAuthenticationNotEnrolled {
    ///     // This device has no enrolled key — offer enrollment instead.
    /// } catch OryClientError.deviceAuthenticationInvalidPIN {
    ///     // Wrong PIN — let the user try again.
    /// }
    /// ```
    ///
    /// - Parameter pin: The PIN set at enrollment or with
    ///   ``OryDeviceManagement/resetDevicePIN(newPin:)``. Required for a PIN key that is not yet
    ///   at AAL2, ignored otherwise.
    /// - Returns: The ``OryAuthenticatedSession`` at AAL2.
    /// - Throws: ``OryClientError/deviceAuthenticationNotEnrolled`` if this device has no
    ///   enrolled key; ``OryClientError/deviceAuthenticationPINRequired`` if the key is
    ///   PIN-protected, the session is below AAL2, and `pin` is `nil`;
    ///   ``OryClientError/deviceAuthenticationInvalidPIN`` when the server rejects the PIN —
    ///   every wrong attempt counts toward `pin_max_attempts` and the key locks at the limit;
    ///   ``OryClientError/deviceAuthenticationCancelled`` if the user declines the biometric
    ///   prompt; ``OryClientError/deviceAuthenticationBiometricsUnavailable`` when a biometric
    ///   key cannot prompt; ``OryClientError/deviceAuthenticationUnavailable`` on the Simulator
    ///   or an unsupported device; ``OryClientError/notAuthenticated`` if no user is signed in;
    ///   or another ``OryClientError`` on signing, network, or server failure.
    func authenticateWithDevice(pin: String?) async throws -> OryAuthenticatedSession
}

extension OryDeviceStepUp {

    /// Steps the current session up to AAL2 with a key that needs no PIN.
    ///
    /// See ``authenticateWithDevice(pin:)``.
    public func authenticateWithDevice() async throws -> OryAuthenticatedSession {
        try await authenticateWithDevice(pin: nil)
    }
}
