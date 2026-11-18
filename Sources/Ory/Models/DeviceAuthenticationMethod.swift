/// A passwordless device-authentication method the user can set up on this device.
///
/// Query ``OryClientProtocol/availableDeviceAuthenticationMethods`` to decide which enrollment options
/// to offer: ``pin`` is available on any device that supports device authentication, while
/// ``biometric`` appears only when the device has usable Face ID / Touch ID / Optic ID.
///
/// - Important: New cases are added in minor releases. End a `switch` that lists every case
///   with `@unknown default:`, so a new case raises a warning instead of a build error, or use
///   `default:` when you handle only some cases.
public enum OryDeviceAuthenticationMethod: Sendable, Hashable {

    /// Passwordless sign-in with a user-chosen PIN plus this device
    /// (``OryDeviceProtection/pin(_:)`` with ``OryClientProtocol/enrollDevice(name:protection:)``,
    /// then ``OryClientProtocol/loginWithDevice(pin:)``).
    case pin

    /// Passwordless sign-in with device biometrics — Face ID / Touch ID / Optic ID
    /// (``OryDeviceProtection/biometrics`` with ``OryClientProtocol/enrollDevice(name:protection:)``,
    /// then ``OryClientProtocol/loginWithDevice(pin:)``).
    case biometric
}
