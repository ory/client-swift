import Foundation

/// The result of a successful registration.
///
/// Whether the new user is signed in immediately depends on your project's
/// configuration. When "sign in after registration" is enabled, ``session`` is
/// present and its token has already been stored — you can go straight to your app's
/// content. Otherwise ``session`` is `nil` (for example the project requires email
/// verification first), and you should route the user accordingly.
///
/// ```swift
/// switch try await client.submitRegistrationFlow(flow, values: values, pressing: action) {
/// case let .success(result):
///     if result.session != nil {
///         showApp()               // signed in
///     } else {
///         showVerificationNeeded() // account created, not yet signed in
///     }
/// case let .pending(nextFlow):
///     render(nextFlow)
/// @unknown default:
///     showUnsupportedStep()
/// }
/// ```
public struct OryRegistrationResult: Sendable {

    /// The identity that was created.
    public let identity: OryIdentity

    /// The session, if the project signs the user in right after registration. When
    /// present, its token is already stored in the configured ``OrySessionStorage``.
    public let session: OryAuthenticatedSession?

    /// The verification the user must complete next, if the project requires it before
    /// sign-in. When set, ``session`` is `nil`; render it via
    /// ``OryClientProtocol/getVerificationFlow(id:)``.
    public let verification: OryVerificationHandle?

    /// Creates a registration result. Provided for tests and previews.
    public init(identity: OryIdentity, session: OryAuthenticatedSession?, verification: OryVerificationHandle? = nil) {
        self.identity = identity
        self.session = session
        self.verification = verification
    }
}
