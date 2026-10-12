import Foundation

/// The login flow's data operations.
protocol LoginRepository: Sendable {

    /// Creates a native login flow and maps it to a renderable ``OryFlow``.
    func createLoginFlow() async throws -> OryFlow

    /// Submits the merged form to a login flow's action URL.
    func submitLogin(url: URL, fields: [String: String], sessionToken: String?) async throws -> LoginSubmissionOutcome
}

/// The internal outcome of submitting a login flow, before token storage and result
/// shaping happen in the client.
enum LoginSubmissionOutcome: Sendable {

    /// Authentication succeeded. `token` is stored by the client when present.
    case success(session: OrySession, token: String?)

    /// Validation failed or another step is required; re-render the flow.
    case pending(OryFlow)
}
