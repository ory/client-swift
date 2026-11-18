import Foundation

/// Passwordless first-factor sign-in with this device (PIN or biometrics).
///
/// `OryClient` rejects overlapping device operations sharing a key-store scope with
/// ``OryClientError/deviceAuthenticationOperationInProgress``. Offer a retry after the
/// active operation finishes; the rejected call has no side effects.
public protocol OryDeviceLogin: Sendable {

    /// Signs in passwordlessly with this device (first factor).
    ///
    /// Use this on the sign-in screen when the device was enrolled with
    /// ``OryDeviceProtection/pin(_:)`` or ``OryDeviceProtection/biometrics``. The enrolled key
    /// decides how the user is verified:
    ///
    /// - A PIN key needs `pin`. The device signs the server challenge and proves the PIN.
    /// - A biometric key prompts for Face ID, Touch ID, or Optic ID; `pin` is ignored.
    ///
    /// Read ``OryDeviceEnrollment/deviceEnrollment()`` first to show a PIN pad or a biometric
    /// button. No prior session is needed; on success the session token is stored for you.
    ///
    /// ```swift
    /// do {
    ///     let session: OryAuthenticatedSession
    ///     switch try await client.deviceEnrollment() {
    ///     case .enrolled(.pin):
    ///         session = try await client.loginWithDevice(pin: enteredPIN)
    ///     case .enrolled(.platform):
    ///         session = try await client.loginWithDevice()
    ///     default:
    ///         return // Fall back to password sign-in.
    ///     }
    /// } catch OryClientError.deviceAuthenticationInvalidPIN {
    ///     // Wrong PIN — let the user try again.
    /// } catch OryClientError.deviceAuthenticationCancelled {
    ///     // The user declined the biometric prompt.
    /// }
    /// ```
    ///
    /// - Important: Biometric sign-in requires the project's `ios_biometric_first_factor`
    ///   setting; otherwise the server rejects it. A biometric key still steps up with
    ///   ``OryDeviceStepUp/authenticateWithDevice(pin:)``.
    ///
    /// - Parameter pin: The PIN set at enrollment or with
    ///   ``OryDeviceManagement/resetDevicePIN(newPin:)``. Required for a PIN key, ignored for a
    ///   biometric key.
    /// - Returns: The signed-in ``OryAuthenticatedSession``.
    /// - Throws: ``OryClientError/deviceAuthenticationPINRequired`` if the key is
    ///   PIN-protected and `pin` is `nil`; ``OryClientError/deviceAuthenticationInvalidPIN``
    ///   when the server rejects the PIN — every wrong attempt counts toward
    ///   `pin_max_attempts` and the key locks at the limit (recover with
    ///   ``OryDeviceManagement/resetDevicePIN(newPin:)``);
    ///   ``OryClientError/deviceAuthenticationCancelled`` if the user declines the biometric
    ///   prompt; ``OryClientError/deviceAuthenticationBiometricsUnavailable`` when a biometric
    ///   key cannot prompt; ``OryClientError/deviceAuthenticationNotEnrolled`` if this device
    ///   has no key, or only a key enrolled with ``OryDeviceProtection/none``;
    ///   ``OryClientError/deviceAuthenticationUnavailable`` on the Simulator or an unsupported
    ///   device; or another ``OryClientError`` on signing, network, or server failure.
    func loginWithDevice(pin: String?) async throws -> OryAuthenticatedSession
}

extension OryDeviceLogin {

    /// Signs in passwordlessly with this device's biometric key.
    ///
    /// See ``loginWithDevice(pin:)``.
    public func loginWithDevice() async throws -> OryAuthenticatedSession {
        try await loginWithDevice(pin: nil)
    }
}
