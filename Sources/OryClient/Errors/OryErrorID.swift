import Foundation

/// The machine-readable identifier Ory attaches to an error response, for example
/// `session_aal2_required`.
///
/// This is the stable way to tell server conditions apart — the accompanying message text is
/// human-facing and may be localized or reworded. ``OryClientError`` already raises a dedicated
/// case for the conditions an app must act on, so reach for this only when you need a
/// distinction the client does not model:
///
/// ```swift
/// catch let OryClientError.server(_, id, _) where id == .identityDisabled {
///     showAccountSuspendedScreen()
/// }
/// ```
///
/// It is a wrapper around `String` rather than an enum on purpose: Ory adds identifiers over
/// time, and an unknown one has to keep decoding into a usable value on an app built before it
/// existed. Comparing against the constants below is always safe; switching exhaustively over
/// every possible value is not, because there is no such thing.
public struct OryErrorID: RawRepresentable, Sendable, Hashable, CustomStringConvertible {

    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public var description: String { rawValue }
}

// The identifiers Ory ships today. Values that gain a dedicated ``OryClientError`` case are
// still listed, because the raw error remains observable through interceptors and logs.
public extension OryErrorID {

    /// The session is valid but too old for a privileged change; re-authenticate first.
    /// Surfaces as ``OryClientError/reauthenticationRequired``.
    static let sessionRefreshRequired = OryErrorID(rawValue: "session_refresh_required")

    /// The flow expired. Surfaces as ``OryClientError/flowExpired(replacementFlowID:)``.
    static let selfServiceFlowExpired = OryErrorID(rawValue: "self_service_flow_expired")

    /// The flow was superseded by a newer one, typically because it was resumed twice.
    static let selfServiceFlowReplaced = OryErrorID(rawValue: "self_service_flow_replaced")

    /// The requested flow is not enabled for this project.
    static let selfServiceFlowDisabled = OryErrorID(rawValue: "self_service_flow_disabled")

    /// The flow can only continue in a browser. Native apps should not see this.
    static let browserLocationChangeRequired = OryErrorID(rawValue: "browser_location_change_required")

    /// A session already exists, so this flow cannot be started.
    static let sessionAlreadyAvailable = OryErrorID(rawValue: "session_already_available")

    /// The project requires a verified email or phone number before signing in.
    static let sessionVerifiedAddressRequired = OryErrorID(rawValue: "session_verified_address_required")

    /// A first factor is required before a second one can be added.
    static let sessionAAL1Required = OryErrorID(rawValue: "session_aal1_required")

    /// A second factor is required. Surfaces as ``OryClientError/secondFactorRequired``.
    static let sessionAAL2Required = OryErrorID(rawValue: "session_aal2_required")

    /// A second factor must be enrolled first.
    /// Surfaces as ``OryClientError/secondFactorEnrollmentRequired``.
    static let sessionAAL2EnrollmentRequired = OryErrorID(rawValue: "session_aal2_enrollment_required")

    /// No active session. Surfaces as ``OryClientError/sessionExpired``.
    static let sessionInactive = OryErrorID(rawValue: "session_inactive")

    /// The requested `return_to` URL is not on the project's allow list.
    static let selfServiceFlowReturnToForbidden = OryErrorID(rawValue: "self_service_flow_return_to_forbidden")

    /// The flow was started by a different identity than the one continuing it.
    static let securityIdentityMismatch = OryErrorID(rawValue: "security_identity_mismatch")

    /// The account is disabled. Nothing the app can do — direct the user to support.
    static let identityDisabled = OryErrorID(rawValue: "identity_disabled")

    /// CSRF validation failed. Should not occur on native flows.
    static let securityCSRFViolation = OryErrorID(rawValue: "security_csrf_violation")
}
