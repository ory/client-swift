import Foundation

/// The outcome of submitting a flow.
///
/// A failed validation or an additional step is **not** an error — the server returns
/// an updated flow to render again. Only genuine failures (network, expired session,
/// server error) are thrown.
///
/// ```swift
/// switch try await client.submitLoginFlow(flow, values: values, pressing: action) {
/// case let .success(authenticated):
///     show(authenticated.session)              // signed in; the token is stored for you
/// case let .pending(nextFlow):
///     render(nextFlow)                          // show new messages or the next step
/// @unknown default:
///     showUnsupportedStep()                     // a result added in a later release
/// }
/// ```
///
/// - Important: New cases are added in minor releases. End a `switch` that lists every case
///   with `@unknown default:`, so a new case raises a warning instead of a build error.
public enum OryFlowResult<Success: Sendable>: Sendable {

    /// The submission succeeded. Check the result for any required continuation,
    /// such as verifying an address before a settings change can be applied.
    case success(Success)

    /// The flow needs another round: re-render `flow` to show messages or the next step.
    case pending(OryFlow)
}

/// The result of a successful authentication.
///
/// The session token has already been stored in the configured ``OrySessionStorage``;
/// subsequent calls such as ``OryClientProtocol/currentSession()`` are authenticated
/// automatically.
public struct OryAuthenticatedSession: Sendable {

    /// The newly authenticated session.
    public let session: OrySession

    /// Creates an authenticated session. Provided for tests and previews.
    public init(session: OrySession) {
        self.session = session
    }
}
