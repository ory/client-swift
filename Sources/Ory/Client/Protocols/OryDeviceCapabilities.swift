import Foundation

/// Querying what device authentication this device supports.
public protocol OryDeviceCapabilities: Sendable {

    /// Whether this device can perform device authentication (second factor bound to the
    /// Secure Enclave).
    ///
    /// `false` on the Simulator, on unsupported devices, and when the App Attest
    /// capability is missing. Check this before offering to enroll a device — for example
    /// to hide the "Enable on this device" button — so you never call
    /// ``OryDeviceEnrollment/enrollDevice(name:protection:)`` where it cannot succeed.
    ///
    /// ```swift
    /// if client.isDeviceAuthenticationAvailable {
    ///     // Show the enrollment option.
    /// }
    /// ```
    var isDeviceAuthenticationAvailable: Bool { get }

    /// The passwordless device-authentication methods this device can set up **right now**.
    ///
    /// ``OryDeviceAuthenticationMethod/pin`` is present on any device that supports device
    /// authentication; ``OryDeviceAuthenticationMethod/biometric`` is present only when the device has usable Face ID /
    /// Touch ID / Optic ID. The set is empty when device authentication is unavailable (for
    /// example on the Simulator without a relaxed authenticator). It reflects device
    /// capability, not what is already enrolled — a device offers one method per install
    /// (enrolling one replaces another).
    ///
    /// Use it to decide which enrollment buttons to show:
    ///
    /// ```swift
    /// let methods = client.availableDeviceAuthenticationMethods
    /// showPINSetup = methods.contains(.pin)
    /// showBiometricSetup = methods.contains(.biometric)
    /// ```
    var availableDeviceAuthenticationMethods: Set<OryDeviceAuthenticationMethod> { get }

    /// The biometric hardware on this device, or ``OryBiometryType/none`` when biometrics
    /// cannot be used. Use it to label your UI — for example "Sign in with Face ID" versus
    /// "Sign in with Touch ID".
    var biometryType: OryBiometryType { get }
}
