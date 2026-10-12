import Foundation

/// The result of an accepted settings submission.
///
/// Returned by ``OrySettingsFlow/submitSettingsFlow(_:values:pressing:)`` when the server
/// accepted the change. Always check ``verification`` before showing a plain saved
/// confirmation: when it is present, the user still has to verify a changed address.
///
/// ```swift
/// switch try await client.submitSettingsFlow(flow, values: values, pressing: action) {
/// case let .success(result):
///     if let verification = result.verification {
///         let next = try await client.getVerificationFlow(id: verification.flowID)
///         renderVerification(next) // submit the emailed code with submitVerificationFlow
///     } else {
///         showSaved(result.identity)
///     }
/// case let .pending(next):
///     renderSettings(next)
/// @unknown default:
///     showUnsupportedStep()
/// }
/// ```
public struct OrySettingsResult: Sendable {

    /// The identity as the server stored it after this submission.
    ///
    /// When ``verification`` is present, what this contains depends on the project's
    /// settings hooks. With `verify_new_address`, the change waits for verification, so this
    /// still has the current traits. With `show_verification_ui`, the change is already saved,
    /// so this has the new traits and the new address is unverified.
    public let identity: OryIdentity

    /// The verification the user should complete next for a changed address, or `nil` when
    /// nothing needs verifying.
    ///
    /// Fetch it with ``OryVerificationFlow/getVerificationFlow(id:)`` and complete it with
    /// ``OryVerificationFlow/submitVerificationFlow(_:values:pressing:)``. After successful
    /// verification, call ``OrySessionManagement/currentSession()`` to read the identity with
    /// the change applied and the address verified.
    public let verification: OryVerificationHandle?

    /// Creates a settings result. Provided for tests and previews.
    public init(identity: OryIdentity, verification: OryVerificationHandle? = nil) {
        self.identity = identity
        self.verification = verification
    }
}
