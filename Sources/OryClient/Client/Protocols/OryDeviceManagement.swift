import Foundation

/// Listing the identity's enrolled devices, and removing or resetting a key.
///
/// `OryClient` rejects overlapping device mutations and key-based authentication sharing a scope with
/// ``OryClientError/deviceAuthenticationOperationInProgress``. Offer a retry after the
/// active operation finishes; the rejected call has no side effects.
/// Device listing remains a read-only snapshot and can run during an active operation.
public protocol OryDeviceManagement: Sendable {

    /// Lists every device enrolled for device authentication on the signed-in identity.
    ///
    /// This is what a "your devices" screen renders. Each entry says how it verifies its
    /// holder, when it was enrolled, whether it locked itself after too many wrong PINs, and
    /// whether it is the device the app is running on.
    ///
    /// ```swift
    /// for device in try await client.enrolledDevices() {
    ///     let suffix = device.isCurrentDevice ? " (this device)" : ""
    ///     print("\(device.name)\(suffix), enrolled \(device.enrolledAt)")
    /// }
    /// ```
    ///
    /// Offer it alongside ``removeDevice(_:)``: an identity is capped at 30 enrolled keys, and
    /// reinstalling the app leaves the old key behind on the server, so a long-lived account
    /// accumulates entries only the user can clean up.
    ///
    /// - Returns: The enrolled devices, in the order the server lists them. Empty when the
    ///   identity has none.
    /// - Throws: ``OryClientError/notAuthenticated`` without a session, or another
    ///   ``OryClientError`` on network or server failure.
    func enrolledDevices() async throws -> [OryEnrolledDevice]

    /// Removes another device's enrolled key — the lost-phone case.
    ///
    /// Pass an entry from ``enrolledDevices()``. Afterwards that device can no longer sign in
    /// or act as a second factor; its user must enroll again.
    ///
    /// Removing the entry whose ``OryEnrolledDevice/isCurrentDevice`` is `true` also clears
    /// this device's local key, exactly like ``removeDevice()``. Warn the user first — it
    /// signs this device out of device authentication.
    ///
    /// ```swift
    /// try await client.removeDevice(lostPhone)
    /// ```
    ///
    /// - Parameter device: The device to revoke.
    /// - Throws: ``OryClientError/secondFactorRequired`` if the project requires a higher
    ///   assurance level than this session has, ``OryClientError/reauthenticationRequired`` if
    ///   the session is older than the project's privileged window,
    ///   ``OryClientError/notAuthenticated`` without a session, or another ``OryClientError``
    ///   on network or server failure.
    func removeDevice(_ device: OryEnrolledDevice) async throws

    /// Removes this device's enrolled key, so it can no longer act as a second factor.
    ///
    /// Because removing a second factor is itself a protected change, the client first
    /// steps the session up to AAL2 with the enrolled key, then removes the credential and
    /// clears the locally stored key. After this call the user must enroll again to use
    /// device authentication on this device.
    ///
    /// ```swift
    /// try await client.removeDevice()
    /// // The device is no longer a second factor.
    /// ```
    ///
    /// - Throws: ``OryClientError/deviceAuthenticationNotEnrolled`` if this device has no
    ///   enrolled key, ``OryClientError/deviceAuthenticationUnavailable`` on the Simulator
    ///   or an unsupported device, ``OryClientError/notAuthenticated`` if no user is
    ///   signed in, or another ``OryClientError`` on signing, network, or server failure.
    func removeDevice() async throws

    /// Forgets this device's enrolled key **locally**, without contacting the server.
    ///
    /// Unlike ``removeDevice()``, this makes no network call and does not require the Secure
    /// Enclave key — use it to recover when the local key is stale (the server credential
    /// was removed elsewhere, or a reinstall wiped the Secure Enclave key while the stored
    /// id lingered), or to reset before enrolling a different account on this device. After
    /// this call ``OryDeviceEnrollment/deviceEnrollment()`` returns
    /// ``OryDeviceEnrollmentState/notEnrolled`` and the user can enroll again; the server
    /// credential, if any, is untouched.
    ///
    /// - Throws: ``OryClientError/storage(underlying:)`` if the store cannot be cleared.
    func forgetDevice() async throws

    /// Sets a new PIN for this device's PIN key without needing the old one — the recovery
    /// path for a forgotten or locked PIN.
    ///
    /// The device proves itself by possession of its enrolled key (a silent signature, no
    /// biometric prompt) and the server re-issues a fresh secret bound to `newPin`. The signing
    /// key is unchanged, so ``OryDeviceStepUp/authenticateWithDevice(pin:)`` and
    /// ``OryDeviceLogin/loginWithDevice(pin:)`` keep working with `newPin`. A locked key is unlocked by the rotation.
    ///
    /// **Whether a forgotten PIN can actually be reset depends on the project.** Changing
    /// settings requires the assurance level the project's settings policy demands, which by
    /// default is the highest the identity can reach. A PIN key that has locked itself no
    /// longer counts as a second factor, so after the next sign-in a plain password session is
    /// enough — this is the forgotten-PIN path. A *working* PIN key still requires AAL2, and if
    /// it is the identity's only second factor the only way to satisfy that is the PIN itself:
    /// the call then throws ``OryClientError/secondFactorRequired``. Reach AAL2 first (for
    /// example ``OryDeviceStepUp/authenticateWithDevice(pin:)`` with the current PIN, or
    /// another second factor) and call again.
    ///
    /// The caller must already have a session — for example from a password sign-in.
    ///
    /// ```swift
    /// do {
    ///     try await client.resetDevicePIN(newPin: chosenPIN)
    ///     // The user can now sign in with the new PIN.
    /// } catch OryClientError.secondFactorRequired {
    ///     // The key still works, so the project requires a second factor to change settings.
    ///     // Ask for the current PIN and step up, or offer another factor.
    /// } catch OryClientError.deviceAuthenticationNotEnrolled {
    ///     // This device has no PIN key to reset.
    /// }
    /// ```
    ///
    /// - Parameter newPin: The new PIN to protect the re-issued secret with.
    /// - Important: As with ``OryDeviceProtection/pin(_:)``, `OryClient` does
    ///   **not** validate the PIN — the server never sees it, so any policy (length, complexity,
    ///   disallowing trivial PINs) is your app's responsibility. The client accepts any non-empty
    ///   string. Validate `newPin` yourself before calling.
    /// - Throws: ``OryClientError/secondFactorRequired`` if the project requires a higher
    ///   assurance level than this session has, ``OryClientError/reauthenticationRequired`` if
    ///   the session is valid but older than the project's privileged window (15 minutes on Ory
    ///   Network), ``OryClientError/deviceAuthenticationNotEnrolled`` if this device has no PIN
    ///   key, ``OryClientError/deviceAuthenticationUnavailable`` on the Simulator or an
    ///   unsupported device, ``OryClientError/notAuthenticated`` without a session, or another
    ///   ``OryClientError`` on signing, network, or server failure.
    func resetDevicePIN(newPin: String) async throws
}
