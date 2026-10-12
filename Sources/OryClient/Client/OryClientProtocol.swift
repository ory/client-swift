import Foundation

/// The Ory client interface.
///
/// Depend on this protocol rather than the concrete ``OryClient`` so you can inject a
/// test double (see `OryClientTestDoubles`) in your own tests:
///
/// ```swift
/// final class ProfileViewModel {
///     private let ory: OryClientProtocol
///     init(ory: OryClientProtocol) { self.ory = ory }
/// }
/// ```
///
/// It composes focused protocols by concern. When a narrower dependency reads clearer,
/// depend on just the slice you need — for example ``OryLoginFlow`` for a sign-in screen,
/// or ``OryDeviceEnrollment`` for a device-setup screen — instead of the whole client.
public protocol OryClientProtocol:
    OrySessionManagement,
    OryLoginFlow,
    OryRegistrationFlow,
    OryVerificationFlow,
    OryRecoveryFlow,
    OrySettingsFlow,
    OryDeviceCapabilities,
    OryDeviceEnrollment,
    OryDeviceStepUp,
    OryDeviceLogin,
    OryDeviceManagement {}
