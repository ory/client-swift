import Foundation

/// The verification flow's data operations.
protocol VerificationRepository: Sendable {

    /// Creates a native verification flow and maps it to a renderable ``OryFlow``.
    func createVerificationFlow() async throws -> OryFlow

    /// Fetches an existing verification flow by id (e.g. the one registration created).
    func getVerificationFlow(id: String) async throws -> OryFlow

    /// Submits the merged form to a verification flow's action URL.
    func submitVerification(url: URL, fields: [String: String]) async throws -> VerificationOutcome
}

/// The internal outcome of submitting a verification flow.
///
/// Verification is multi-step and state-driven: the server returns the flow at each
/// step, and completion is signaled by its state rather than an HTTP status.
enum VerificationOutcome: Sendable {

    /// The flow reached its verified state (`passed_challenge`).
    case completed

    /// A further step or a validation error; re-render the flow (e.g. now enter the
    /// code that was sent).
    case pending(OryFlow)
}
