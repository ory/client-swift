import Foundation

/// The result of a successful sign-in.
///
/// The session token is already stored in the configured ``OrySessionStorage``, so later calls
/// such as ``OrySessionManagement/currentSession()`` are authenticated. Check ``verification``
/// and ``secondFactorEnrollment`` before showing your app: the project can ask for one more step.
///
/// ```swift
/// switch try await client.submitLoginFlow(flow, values: values, pressing: action) {
/// case let .success(result):
///     if let enrollment = result.secondFactorEnrollment {
///         let settings = try await client.getSettingsFlow(id: enrollment.flowID)
///         renderSecondFactorSetup(settings)   // the project requires a second factor
///     } else if let verification = result.verification {
///         let next = try await client.getVerificationFlow(id: verification.flowID)
///         renderVerification(next)            // a code was sent to verification.address
///     } else {
///         showApp(result.session)
///     }
/// case let .pending(nextFlow):
///     render(nextFlow)
/// @unknown default:
///     showUnsupportedStep()
/// }
/// ```
public struct OryLoginResult: Sendable, Hashable {

    /// The session the sign-in created or upgraded.
    ///
    /// When ``secondFactorEnrollment`` is set, the session does not yet meet the project's
    /// required assurance level and ``OrySession/identity`` is `nil`.
    public let session: OrySession

    /// The verification the project asks the user to complete after signing in, when its login
    /// hooks send one (`show_verification_ui`). The user is already signed in.
    public let verification: OryVerificationHandle?

    /// The settings flow in which the user must add a second factor, when the project requires
    /// one and the user has none. Until then, ``OrySessionManagement/currentSession()`` throws
    /// ``OryClientError/secondFactorEnrollmentRequired``.
    ///
    /// Ory sends this only when the project enables the `use_continue_with_transitions` feature
    /// flag.
    public let secondFactorEnrollment: OrySettingsHandle?

    /// Creates a sign-in result. Provided for tests and previews.
    public init(
        session: OrySession,
        verification: OryVerificationHandle? = nil,
        secondFactorEnrollment: OrySettingsHandle? = nil
    ) {
        self.session = session
        self.verification = verification
        self.secondFactorEnrollment = secondFactorEnrollment
    }
}
