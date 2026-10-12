/// How the key enrolled with ``OryDeviceEnrollment/enrollDevice(name:protection:)`` verifies
/// the person holding the device.
///
/// The protection decides what the device can do later:
///
/// | Protection      | Step-up to AAL2                                         | Passwordless sign-in                         |
/// |-----------------|---------------------------------------------------------|----------------------------------------------|
/// | ``none``        | `authenticateWithDevice()`, silent                      | Not available                                |
/// | ``pin(_:)``     | `authenticateWithDevice(pin:)`                          | `loginWithDevice(pin:)`                      |
/// | ``biometrics``  | `authenticateWithDevice()`, prompts for biometrics      | `loginWithDevice()`, prompts for biometrics  |
///
/// Offer only what ``OryDeviceCapabilities/availableDeviceAuthenticationMethods`` contains:
/// ``pin(_:)`` needs ``OryDeviceAuthenticationMethod/pin`` and ``biometrics`` needs
/// ``OryDeviceAuthenticationMethod/biometric``.
///
/// - Important: New cases are added in minor releases. End a `switch` that lists every case
///   with `@unknown default:`, so a new case raises a warning instead of a build error, or use
///   `default:` when you handle only some cases.
public enum OryDeviceProtection: Sendable, Equatable {

    /// Possession of the device only. The key works as a second factor for step-up, never as a
    /// sole first factor.
    case none

    /// The user's PIN. The device can sign in passwordlessly with the PIN and can step up.
    ///
    /// The PIN never leaves the device. `OryClient` does **not** validate it: the server never
    /// sees the PIN, so no length, complexity, or format policy can be enforced by `OryClient`,
    /// the Ory backend, or the Ory Console, and any non-empty string is accepted, even `"1"`.
    /// Enforcing a policy is your app's responsibility; validate the PIN before enrolling.
    case pin(String)

    /// Face ID, Touch ID, or Optic ID. The device can sign in passwordlessly after a biometric
    /// check and can step up.
    ///
    /// Your app's `Info.plist` must contain an `NSFaceIDUsageDescription` string for the
    /// Face ID prompt to appear.
    case biometrics
}

/// Whether this device has an enrolled key, and how that key verifies its holder.
///
/// Returned by ``OryDeviceEnrollment/deviceEnrollment()``. Use it to decide what to show:
///
/// ```swift
/// switch try await client.deviceEnrollment() {
/// case .notEnrolled:
///     // Offer "Set up this device" and the password sign-in.
/// case .enrolled(.pin):
///     // Show a PIN pad, then call loginWithDevice(pin:).
/// case .enrolled(.platform):
///     // Show "Sign in with Face ID", then call loginWithDevice().
/// default:
///     // A second factor only: use authenticateWithDevice() when AAL2 is required.
/// }
/// ```
///
/// - Important: New cases are added in minor releases. End a `switch` that lists every case
///   with `@unknown default:`, so a new case raises a warning instead of a build error, or use
///   `default:` when you handle only some cases.
public enum OryDeviceEnrollmentState: Sendable, Hashable {

    /// This device has no enrolled key.
    case notEnrolled

    /// This device has an enrolled key that verifies its holder as described by the associated
    /// ``OryDeviceUserVerification``.
    case enrolled(OryDeviceUserVerification)
}
